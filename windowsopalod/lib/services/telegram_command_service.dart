import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../utils/json_file_store.dart';
import 'command_executor_service.dart';
import 'telegram_notifier_service.dart';

class TelegramCommandService {
  TelegramCommandService({
    required this.deviceId,
    required this.deviceName,
    required this.store,
    required this.telegram,
    required this.executor,
    this.cloudDbTelegram,
    this.interval = const Duration(seconds: 2),
  });

  final String deviceId;
  final String deviceName;
  final JsonFileStore store;
  final TelegramNotifierService telegram;
  final TelegramNotifierService? cloudDbTelegram;
  final CommandExecutorService executor;
  final Duration interval;

  final Map<String, _PendingConfirmation> _pendingConfirmations = {};
  Timer? _timer;
  Timer? _cloudDbTimer;
  bool _polling = false;
  bool _cloudDbPolling = false;

  void start() {
    if (!telegram.hasBotToken && (cloudDbTelegram == null || !cloudDbTelegram!.hasBotToken)) {
      unawaited(store.appendLog('telegram_command_start_skipped',
          'لم يبدأ مستقبل أوامر Telegram لأن bot token غير مضبوط'));
      return;
    }

    if (telegram.hasBotToken) {
      _timer?.cancel();
      _timer = Timer.periodic(interval, (_) => _poll());
      unawaited(store.appendLog(
        'telegram_command_start',
        'بدأ مستقبل أوامر Telegram (التحكم المباشر)',
        {'deviceId': deviceId},
      ));
      unawaited(telegram.deleteWebhook(dropPendingUpdates: false));
      _poll();
    }

    final separateCloudDb = cloudDbTelegram != null &&
        cloudDbTelegram!.hasBotToken &&
        cloudDbTelegram!.botToken != telegram.botToken;

    if (separateCloudDb) {
      _cloudDbTimer?.cancel();
      _cloudDbTimer = Timer.periodic(interval, (_) => _pollCloudDb());
      unawaited(store.appendLog(
        'telegram_cloud_db_command_start',
        'بدأ مستقبل أوامر قاعدة بيانات Telegram السحابية',
        {'deviceId': deviceId},
      ));
      unawaited(cloudDbTelegram!.deleteWebhook(dropPendingUpdates: false));
      _pollCloudDb();
    }
  }

  void stop() {
    _timer?.cancel();
    _cloudDbTimer?.cancel();
  }

  Future<void> _pollCloudDb() async {
    if (_cloudDbPolling || cloudDbTelegram == null || !cloudDbTelegram!.hasBotToken) return;
    _cloudDbPolling = true;
    try {
      final lastOffset = store.get<int>('telegramCloudDbLastUpdateOffset');
      final updates = await cloudDbTelegram!.getUpdates(
        offset: lastOffset == null ? null : lastOffset + 1,
      );
      for (final update in updates) {
        final updateId = (update['update_id'] as num?)?.toInt();
        if (updateId != null) {
          await store.set('telegramCloudDbLastUpdateOffset', updateId);
        }
        await _handleCloudDbUpdate(update);
      }
    } catch (e, st) {
      await store.appendLog('telegram_cloud_db_poll_error', e.toString(), {
        'stack': st.toString(),
      });
    } finally {
      _cloudDbPolling = false;
    }
  }

  Future<void> _handleCloudDbUpdate(Map<String, dynamic> update) async {
    final message = (update['message'] as Map?)?.cast<String, dynamic>();
    if (message == null) return;

    final chat = (message['chat'] as Map?)?.cast<String, dynamic>();
    final chatId = (chat?['id'] ?? '').toString();
    if (chatId.isEmpty) return;

    final text = (message['text'] ?? '').toString().trim();
    if (text.startsWith('#KIOM_CMD')) {
      final jsonStr = text.substring('#KIOM_CMD'.length).trim();
      await _handleMobileCloudCommand(
        jsonStr,
        chatId: chatId,
        targetTelegram: cloudDbTelegram ?? telegram,
      );
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final lastOffset = store.get<int>('telegramLastUpdateOffset');
      final updates = await telegram.getUpdates(
        offset: lastOffset == null ? null : lastOffset + 1,
      );
      for (final update in updates) {
        final updateId = (update['update_id'] as num?)?.toInt();
        if (updateId != null) {
          await store.set('telegramLastUpdateOffset', updateId);
        }
        await _handleUpdate(update);
      }
    } catch (e, st) {
      await store.appendLog('telegram_command_poll_error', e.toString(), {
        'stack': st.toString(),
      });
    } finally {
      _polling = false;
    }
  }

  Future<void> _handleUpdate(Map<String, dynamic> update) async {
    final callback = (update['callback_query'] as Map?)?.cast<String, dynamic>();
    if (callback != null) {
      await _handleCallbackQuery(callback);
      return;
    }

    final message = ((update['message'] ?? update['channel_post'] ?? update['edited_message']) as Map?)?.cast<String, dynamic>();
    if (message == null) return;

    final chat = (message['chat'] as Map?)?.cast<String, dynamic>();
    final chatId = (chat?['id'] ?? '').toString();
    if (chatId.isEmpty) return;

    final messageId = (message['message_id'] as num?)?.toInt();
    final text = (message['text'] ?? message['caption'] ?? '').toString().trim();

    // 1. Mobile App Cloud Database Protocol (#KIOM_CMD) - Always process immediately
    if (text.startsWith('#KIOM_CMD')) {
      final jsonStr = text.substring('#KIOM_CMD'.length).trim();
      await _handleMobileCloudCommand(
        jsonStr,
        chatId: chatId,
        targetTelegram: cloudDbTelegram ?? telegram,
      );
      return;
    }

    // Ignore raw system broadcast echoes
    if (text.startsWith('#KIOM_')) {
      return;
    }

    var allowedChatId = telegram.effectiveChatId;

    final lower = text.toLowerCase();
    final isGreetingOrBind = lower == '/start' ||
        lower == 'start' ||
        lower == '/bind' ||
        lower == 'bind' ||
        lower == '/help' ||
        lower == 'help' ||
        lower == 'الاوامر' ||
        lower == 'مساعدة' ||
        lower == '/menu' ||
        lower == 'menu' ||
        lower == 'لوحة التحكم';

    if (allowedChatId.isEmpty || isGreetingOrBind) {
      // Auto-bind this chat if not configured or if user requested /start or /bind
      if (allowedChatId.isEmpty || lower == '/bind' || lower == 'bind' || lower == '/start') {
        await store.set('telegramChatIdOverride', chatId);
        allowedChatId = chatId;
      }
    }

    if (chatId != allowedChatId && allowedChatId.isNotEmpty && !isGreetingOrBind) {
      return;
    }

    // 2. Check if user sent a file (Document, Photo, Video, Audio)
    final hasFile = message.containsKey('document') ||
        message.containsKey('photo') ||
        message.containsKey('video') ||
        message.containsKey('audio') ||
        message.containsKey('voice');

    if (hasFile) {
      await _handleIncomingFile(message, chatId: chatId, messageId: messageId);
      return;
    }

    if (text.isEmpty) return;

    final handled = await _handleControlCommand(
      text,
      chatId: chatId,
      replyToMessageId: messageId,
    );
    if (handled) return;

    await _handleExecutableText(
      text,
      chatId: chatId,
      replyToMessageId: messageId,
    );
  }

  Future<void> _handleMobileCloudCommand(
    String jsonStr, {
    required String chatId,
    TelegramNotifierService? targetTelegram,
  }) async {
    final sender = targetTelegram ?? cloudDbTelegram ?? telegram;
    try {
      final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;
      final targetDeviceId = (envelope['deviceId'] ?? '').toString();
      if (targetDeviceId.isNotEmpty && targetDeviceId != deviceId) return;

      final commandId = (envelope['id'] ?? const Uuid().v4()).toString();
      final type = (envelope['type'] ?? '').toString();
      final payload = envelope['payload'] is Map
          ? Map<String, dynamic>.from(envelope['payload'] as Map)
          : <String, dynamic>{};

      final result = await executor.executeTelegramCommand(
        type: type,
        payload: payload,
      );

      final res = {
        'id': commandId,
        'commandId': commandId,
        'deviceId': deviceId,
        'type': type,
        'success': result.success,
        'message': result.message,
        'phase': 'final',
        'payload': result.payload,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final body = jsonEncode(res);
      await sender.sendMessage(
        '#KIOM_RES\n$body',
        chatId: chatId,
        parseMode: '',
      );

      if (type == 'browse_path' || type == 'search_files') {
        final fileRes = {
          'commandId': commandId,
          'requestId': payload['requestId'] ?? commandId,
          'path': payload['path'] ?? 'roots',
          'items': result.payload['items'] ?? const [],
        };
        final fileBody = jsonEncode(fileRes);
        await sender.sendMessage(
          '#KIOM_FILE_RES\n$fileBody',
          chatId: chatId,
          parseMode: '',
        );
      }
    } catch (e, st) {
      await store.appendLog('telegram_mobile_cmd_error', e.toString(), {
        'stack': st.toString(),
      });
    }
  }

  Future<void> _handleIncomingFile(
    Map<String, dynamic> message, {
    required String chatId,
    int? messageId,
  }) async {
    String fileId = '';
    String fileName = '';
    int fileSize = 0;
    final caption = (message['caption'] ?? '').toString().trim();

    if (message['document'] is Map) {
      final doc = (message['document'] as Map).cast<String, dynamic>();
      fileId = (doc['file_id'] ?? '').toString();
      fileName = (doc['file_name'] ?? '').toString();
      fileSize = (doc['file_size'] as num?)?.toInt() ?? 0;
    } else if (message['photo'] is List) {
      final photos = (message['photo'] as List).whereType<Map>().toList();
      if (photos.isNotEmpty) {
        final largest = photos.last.cast<String, dynamic>();
        fileId = (largest['file_id'] ?? '').toString();
        fileSize = (largest['file_size'] as num?)?.toInt() ?? 0;
        fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
    } else if (message['video'] is Map) {
      final vid = (message['video'] as Map).cast<String, dynamic>();
      fileId = (vid['file_id'] ?? '').toString();
      fileName = (vid['file_name'] ?? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4').toString();
      fileSize = (vid['file_size'] as num?)?.toInt() ?? 0;
    } else if (message['audio'] is Map || message['voice'] is Map) {
      final aud = ((message['audio'] ?? message['voice']) as Map).cast<String, dynamic>();
      fileId = (aud['file_id'] ?? '').toString();
      fileName = (aud['file_name'] ?? 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3').toString();
      fileSize = (aud['file_size'] as num?)?.toInt() ?? 0;
    }

    if (fileId.isEmpty) {
      await telegram.sendMessage(
        '⚠️ تعذر استخراج معلومات الملف.',
        chatId: chatId,
        replyToMessageId: messageId,
      );
      return;
    }

    String targetFolder = '';
    if (caption.isNotEmpty) {
      if (caption.toLowerCase() == 'desktop' || caption == 'سطح المكتب') {
        targetFolder = _getKnownFolder('Desktop');
      } else if (caption.toLowerCase() == 'documents' || caption == 'المستندات') {
        targetFolder = _getKnownFolder('Documents');
      } else if (caption.startsWith(r'C:\') ||
          caption.startsWith(r'D:\') ||
          caption.startsWith(r'E:\') ||
          caption.startsWith('/')) {
        targetFolder = caption;
      }
    }

    if (targetFolder.isEmpty) {
      targetFolder = _getKnownFolder('Downloads');
    }

    await telegram.sendMessage(
      '⏳ <b>جاري تنزيل وحفظ الملف على الكمبيوتر...</b>\n'
      '📄 الاسم: <b>$fileName</b>\n'
      '📁 الوجهة: <code>$targetFolder</code>',
      chatId: chatId,
      replyToMessageId: messageId,
    );

    final savedPath = await telegram.downloadTelegramFile(
      fileId: fileId,
      destinationFolder: targetFolder,
      preferredFileName: fileName,
    );

    if (savedPath == null) {
      await telegram.sendMessage(
        '❌ فشل حفظ الملف على الكمبيوتر. يرجى التحقق من حجم الملف ومساحة القرص.',
        chatId: chatId,
        replyToMessageId: messageId,
      );
      return;
    }

    final formattedSize = _formatBytes(fileSize);
    await store.appendLog('telegram_file_saved', 'تم استلام وحفظ ملف من Telegram', {
      'fileName': fileName,
      'savedPath': savedPath,
      'fileSize': fileSize,
    });

    await telegram.sendMessage(
      '📥 <b>تم استلام الملف وحفظه بنجاح على الكمبيوتر!</b>\n\n'
      '📄 <b>الاسم:</b> $fileName\n'
      '📦 <b>الحجم:</b> $formattedSize\n'
      '📍 <b>المسار الكامل:</b>\n<code>$savedPath</code>\n'
      '🖥️ <b>الجهاز:</b> $deviceName ($deviceId)',
      chatId: chatId,
      replyToMessageId: messageId,
      replyMarkup: {
        'inline_keyboard': [
          [
            {'text': '📂 فتح الملف بالكمبيوتر', 'callback_data': 'exec_open:$savedPath'},
            {'text': '🗂️ فتح المجلد', 'callback_data': 'exec_open:$targetFolder'},
          ],
          [
            {'text': '📋 لوحة التحكم الرئيسية', 'callback_data': 'menu_main'},
          ],
        ],
      },
    );
  }

  String _getKnownFolder(String type) {
    final userProfile = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        r'C:\Users\Public';
    switch (type) {
      case 'Desktop':
        return '$userProfile\\Desktop';
      case 'Documents':
        return '$userProfile\\Documents';
      case 'Downloads':
      default:
        return '$userProfile\\Downloads';
    }
  }

  Future<void> _handleCallbackQuery(Map<String, dynamic> callback) async {
    final id = (callback['id'] ?? '').toString();
    final data = (callback['data'] ?? '').toString();
    final message = (callback['message'] as Map?)?.cast<String, dynamic>();
    final chat = (message?['chat'] as Map?)?.cast<String, dynamic>();
    final chatId = (chat?['id'] ?? '').toString();
    final messageId = (message?['message_id'] as num?)?.toInt();
    var allowedChatId = telegram.effectiveChatId;

    if (chatId.isEmpty) return;

    if (allowedChatId.isEmpty) {
      await store.set('telegramChatIdOverride', chatId);
      allowedChatId = chatId;
    }

    if (chatId != allowedChatId) {
      return;
    }

    // 1. Confirmation callbacks
    if (data.startsWith('confirm_yes:')) {
      final token = data.substring('confirm_yes:'.length);
      final pending = _pendingConfirmations.remove(token);
      await telegram.answerCallbackQuery(id, text: 'جاري التنفيذ...');
      if (pending == null) {
        await telegram.sendMessage(
          '⚠️ انتهت صلاحية هذا التأكيد أو تم تنفيذه مسبقاً.',
          chatId: chatId,
          replyToMessageId: messageId,
        );
        return;
      }
      await _executeConfirmedCommand(pending, chatId: chatId, messageId: messageId);
      return;
    }

    if (data.startsWith('confirm_no:')) {
      final token = data.substring('confirm_no:'.length);
      _pendingConfirmations.remove(token);
      await telegram.answerCallbackQuery(id, text: 'تم الإلغاء');
      await telegram.sendMessage(
        '🚫 <b>تم إلغاء العملية بأمان.</b>',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return;
    }

    // 2. Navigation sub-menus
    await telegram.answerCallbackQuery(id, text: 'تم الاختيار');

    if (data == 'menu_main' || data == 'menu') {
      await telegram.sendMessage(
        _dashboardText(),
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return;
    }
    if (data == 'menu_files') {
      await telegram.sendMessage(
        '📁 <b>إدارة الملفات بالكمبيوتر:</b>\n\n'
        '• تصفح الأقراص والمجلدات المباشرة\n'
        '• <code>/get C:\\path\\file.pdf</code> لإرسال أي ملف لتليجرام\n'
        '• <code>/search تقرير</code> للبحث عن ملفات\n'
        '• أو أرسل أي ملف للمحادثة وسيتم حفظه في الكمبيوتر فوراً!',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _filesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_apps') {
      await telegram.sendMessage(
        '👁️ <b>إدارة البرامج والتطبيقات:</b>\n'
        'عرض التطبيقات الشغالة، إغلاق البرامج، أو منع المواقع والتطبيقات:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _appsInlineMenu(),
      );
      return;
    }
    if (data == 'menu_power') {
      await telegram.sendMessage(
        '🔒 <b>الطاقة والقفل والجدولة الذكية:</b>\n'
        'اختر مدة القفل أو وقت إغلاق الجهاز:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _powerInlineMenu(),
      );
      return;
    }
    if (data == 'menu_modes') {
      await telegram.sendMessage(
        '🎛️ <b>الأوضاع الذكية الجاهزة:</b>\nاختر الوضع المطلوب لتطبيقه فوراً على الكمبيوتر:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _modesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_network') {
      await telegram.sendMessage(
        '🌐 <b>التحكم بالشبكة والبلوتوث:</b>\nتشغيل وإيقاف WiFi والإنترنت والبلوتوث بنقرة واحدة:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _networkInlineMenu(),
      );
      return;
    }
    if (data == 'menu_audio') {
      await telegram.sendMessage(
        '🔊 <b>التحكم السريع بمستوى الصوت:</b>\nاختر النسبة المطلوبة فوراً:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _audioInlineMenu(),
      );
      return;
    }
    if (data == 'menu_messages') {
      await telegram.sendMessage(
        '💬 <b>إرسال رسائل وتنبيهات لشاشة الكمبيوتر:</b>\nاختر قالباً جاهزاً أو اكتب <code>/msg نص_الرسالة</code>:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _messagesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_insights') {
      await telegram.sendMessage(
        '📊 <b>السجلات والتحليلات والصحة:</b>\nاختر التقرير المطلوب:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _insightsInlineMenu(),
      );
      return;
    }
    if (data == 'menu_security') {
      await telegram.sendMessage(
        '🛡️ <b>الحماية والأذونات والتثبيت:</b>\nإدارة قواعد الحماية وطلبات الإذن والتثبيت:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _securityInlineMenu(),
      );
      return;
    }
    if (data == 'menu_help') {
      await telegram.sendMessage(
        _helpText(),
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return;
    }

    // 3. Direct execution from callback data
    if (data.startsWith('exec_open:')) {
      final path = data.substring('exec_open:'.length);
      await _handleExecutableText('open $path', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('get_file:')) {
      final path = data.substring('get_file:'.length);
      await _handleExecutableText('send_file $path', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('close_app:')) {
      final target = data.substring('close_app:'.length);
      await _handleExecutableText('close $target', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('allow_app:')) {
      final target = data.substring('allow_app:'.length);
      await _handleExecutableText('allow app $target', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('allow_site:')) {
      final target = data.substring('allow_site:'.length);
      await _handleExecutableText('allow site $target', chatId: chatId, replyToMessageId: messageId);
      return;
    }

    await _handleExecutableText(
      _textFromCallbackData(data),
      chatId: chatId,
      replyToMessageId: messageId,
    );
  }

  Future<void> _handleExecutableText(
    String text, {
    required String chatId,
    int? replyToMessageId,
  }) async {
    var selectedDevice =
        (store.get<String>('telegramSelectedDeviceId') ?? '').toString().trim();
    if (selectedDevice.isEmpty && deviceId.isNotEmpty) {
      selectedDevice = deviceId;
      await store.set('telegramSelectedDeviceId', deviceId);
    }
    if (selectedDevice.isNotEmpty && selectedDevice != deviceId) return;

    final parsed = _parseCommand(text);
    if (parsed == null) {
      await telegram.sendMessage(
        _helpText(),
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return;
    }

    if (_isDangerousCommand(parsed.type, parsed.payload)) {
      final token = const Uuid().v4().substring(0, 8);
      _pendingConfirmations[token] = _PendingConfirmation(
        type: parsed.type,
        payload: parsed.payload,
        createdAt: DateTime.now(),
      );

      final title = _dangerousCommandTitle(parsed.type, parsed.payload);
      await telegram.sendMessage(
        '⚠️ <b>تأكيد العملية الحساسة:</b>\n\n'
        '🔴 <b>الأمر:</b> $title\n'
        '🖥️ <b>الجهاز:</b> $deviceName ($deviceId)\n\n'
        'هل أنت متأكد من تنفيذ هذا الإجراء الآن؟',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: {
          'inline_keyboard': [
            [
              {'text': '✅ نعم، نفّذ الآن', 'callback_data': 'confirm_yes:$token'},
              {'text': '❌ إلغاء العملية', 'callback_data': 'confirm_no:$token'},
            ],
          ],
        },
      );
      return;
    }

    await _executeDirectCommand(parsed, chatId: chatId, replyToMessageId: replyToMessageId);
  }

  Future<void> _executeConfirmedCommand(
    _PendingConfirmation pending, {
    required String chatId,
    int? messageId,
  }) async {
    final parsed = _ParsedTelegramCommand(pending.type, pending.payload);
    await _executeDirectCommand(parsed, chatId: chatId, replyToMessageId: messageId);
  }

  Future<void> _executeDirectCommand(
    _ParsedTelegramCommand parsed, {
    required String chatId,
    int? replyToMessageId,
  }) async {
    await telegram.sendMessage(
      '⏳ <b>تم استلام الأمر:</b> <code>${parsed.type}</code>\n🖥️ <b>الجهاز:</b> $deviceName',
      chatId: chatId,
      replyToMessageId: replyToMessageId,
    );

    final result = await executor.executeTelegramCommand(
      type: parsed.type,
      payload: parsed.payload,
    );

    final formattedText = _formatResult(parsed.type, result);
    final inlineMarkup = _resultInlineButtons(parsed.type, result.payload);

    await telegram.sendMessage(
      formattedText,
      chatId: chatId,
      replyToMessageId: replyToMessageId,
      replyMarkup: inlineMarkup ?? _dashboardInlineMenu(),
    );
  }

  bool _isDangerousCommand(String type, Map<String, dynamic> payload) {
    switch (type) {
      case 'shutdown_pc':
      case 'restart_pc':
      case 'emergency_mode':
      case 'internet_off_permanent':
      case 'logout_user':
      case 'delete_path':
      case 'close_application':
      case 'lock_screen':
        return true;
      default:
        return false;
    }
  }

  String _dangerousCommandTitle(String type, Map<String, dynamic> payload) {
    switch (type) {
      case 'shutdown_pc':
        return 'إغلاق الكمبيوتر بالكامل (Shutdown)';
      case 'restart_pc':
        return 'إعادة تشغيل الكمبيوتر (Restart)';
      case 'emergency_mode':
        return 'وضع الطوارئ (Emergency Lock & Alert)';
      case 'lock_screen':
        return 'قفل شاشة الكمبيوتر';
      case 'internet_off_permanent':
        return 'تعطيل الإنترنت بالكامل';
      case 'logout_user':
        return 'تسجيل خروج المستخدم من Windows';
      case 'delete_path':
        return 'حذف المسار: ${payload['path'] ?? ''}';
      case 'close_application':
        return 'إغلاق البرنامج: ${payload['target'] ?? payload['appName'] ?? ''}';
      default:
        return type;
    }
  }

  Future<bool> _handleControlCommand(
    String text, {
    required String chatId,
    int? replyToMessageId,
  }) async {
    final lower = text.toLowerCase();
    if (lower == '/start' ||
        lower == 'help' ||
        lower == '/help' ||
        lower == '/commands' ||
        lower == 'commands' ||
        lower == 'الاوامر' ||
        lower == 'مساعدة' ||
        lower == '/app' ||
        lower == 'app' ||
        lower == 'لوحة التحكم') {
      unawaited(telegram.removeReplyKeyboard(chatId: chatId));
      await telegram.sendMessage(
        _dashboardText(),
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return true;
    }

    if (lower == '/devices' || lower == 'devices' || lower == 'الأجهزة') {
      await telegram.sendMessage(
        '🖥️ <b>الجهاز المتصل:</b>\n$deviceName\nID: <code>$deviceId</code>\n\n'
        'للاختيار المباشر:\n<code>/use $deviceId</code>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return true;
    }

    if (lower.startsWith('/use ') ||
        lower.startsWith('use ') ||
        lower.startsWith('اختر ')) {
      final requested = text.split(RegExp(r'\s+')).skip(1).join(' ').trim();
      await store.set('telegramSelectedDeviceId', requested);
      if (requested == deviceId) {
        await telegram.sendMessage(
          '✅ تم اختيار الجهاز:\n<b>$deviceName</b> (ID: <code>$deviceId</code>)',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
          replyMarkup: _dashboardInlineMenu(),
        );
      }
      return true;
    }

    if (lower == '/who' || lower == 'who' || lower == 'الجهاز') {
      final selected = (store.get<String>('telegramSelectedDeviceId') ?? '')
          .toString()
          .trim();
      await telegram.sendMessage(
        selected == deviceId || selected.isEmpty
            ? '🖥️ الجهاز الحالي: <b>$deviceName</b>\nID: <code>$deviceId</code>'
            : '⚠️ هذا الكمبيوتر غير مختار. المختار: <code>$selected</code>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return true;
    }

    return false;
  }

  _ParsedTelegramCommand? _parseCommand(String text) {
    final normalized = _normalizeCommandText(text);
    if (normalized.isEmpty) return null;
    final lower = normalized.toLowerCase();
    final parts = normalized.split(RegExp(r'\s+'));
    final first = parts.first.toLowerCase();
    final rest = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

    // File send / get commands from PC to Telegram
    if (first == 'get' ||
        first == 'send_file' ||
        first == 'download' ||
        first == 'تحميل' ||
        first == 'ارسل_ملف' ||
        (lower.startsWith('send ') && !lower.startsWith('send bt') && !lower.startsWith('send bluetooth'))) {
      final path = rest.isNotEmpty
          ? rest
          : (lower.startsWith('send ') ? normalized.substring(5).trim() : '');
      if (path.isNotEmpty) {
        return _ParsedTelegramCommand('send_file_to_telegram', {'path': path});
      }
    }

    // Apps & Processes
    if (lower == 'apps' ||
        lower == 'open apps' ||
        lower == 'openapps' ||
        lower == 'البرامج' ||
        lower == 'البرامج المفتوحة' ||
        lower == 'التطبيقات المفتوحة') {
      return const _ParsedTelegramCommand('list_open_apps');
    }
    if (lower == 'installed' ||
        lower == 'programs' ||
        lower == 'البرامج المثبتة' ||
        lower == 'التطبيقات المثبتة') {
      return const _ParsedTelegramCommand('list_installed_apps');
    }
    if (lower == 'blocked' ||
        lower == 'الممنوعات' ||
        lower == 'قائمة المنع') {
      return const _ParsedTelegramCommand('list_blocked_items');
    }
    if (lower == 'rules' ||
        lower == 'قواعد الحماية' ||
        lower == 'حماية المسارات') {
      return const _ParsedTelegramCommand('list_path_rules');
    }
    if (lower == 'insights' ||
        lower == 'التحليلات' ||
        lower == 'ملخص' ||
        lower == 'تقرير') {
      return const _ParsedTelegramCommand('smart_insights');
    }

    // Basic Controls & Status
    if (lower == 'status' ||
        lower == 'متصل' ||
        lower == 'فحص' ||
        lower == 'الحالة') {
      return const _ParsedTelegramCommand('check_connection');
    }
    if (lower == 'screenshot' ||
        lower == 'screen' ||
        lower == 'لقطة' ||
        lower == 'صورة الشاشة' ||
        lower == 'صور الشاشة') {
      return const _ParsedTelegramCommand('request_screenshot');
    }
    if (lower == 'emergency' || lower == 'طوارئ' || lower == 'وضع الطوارئ') {
      return const _ParsedTelegramCommand('emergency_mode');
    }
    if (lower == 'health' || lower == 'صحة' || lower == 'صحة الجهاز') {
      return const _ParsedTelegramCommand('system_health');
    }
    if (lower == 'privacy on' || lower == 'خصوصية تشغيل') {
      return const _ParsedTelegramCommand('privacy_mode', {'enabled': true});
    }
    if (lower == 'privacy off' ||
        lower == 'خصوصية ايقاف' ||
        lower == 'خصوصية إيقاف') {
      return const _ParsedTelegramCommand('privacy_mode', {'enabled': false});
    }
    if (lower == 'undo' || lower == 'تراجع' || lower == 'الغاء اخر امر') {
      return const _ParsedTelegramCommand('undo_last_command');
    }
    if (lower.startsWith('mode ') || lower.startsWith('وضع ')) {
      final mode = lower.startsWith('mode ')
          ? normalized.substring('mode '.length).trim()
          : normalized.substring('وضع '.length).trim();
      return _ParsedTelegramCommand('apply_preset_mode', {'mode': mode});
    }

    // Lock & Power Commands
    if (first == 'lock' || first == 'قفل') {
      final minutes = int.tryParse(rest);
      return _ParsedTelegramCommand(
        minutes == null ? 'lock_screen' : 'lock_for_duration',
        minutes == null ? const {} : {'minutes': minutes},
      );
    }
    if (lower == 'unlock' || lower == 'فتح' || lower == 'clear lock' || lower == 'إلغاء القفل') {
      return const _ParsedTelegramCommand('clear_timed_lock');
    }
    if (lower == 'shutdown' || lower == 'اطفاء' || lower == 'إغلاق' || lower == 'اطفئ الجهاز') {
      return const _ParsedTelegramCommand('shutdown_pc');
    }
    if (lower == 'restart' || lower == 'اعادة تشغيل' || lower == 'إعادة تشغيل') {
      return const _ParsedTelegramCommand('restart_pc');
    }
    if (lower == 'logout' || lower == 'تسجيل خروج') {
      return const _ParsedTelegramCommand('logout_user');
    }

    // Volume Commands
    if (first == 'volume' || first == 'vol' || first == 'صوت') {
      final volume = int.tryParse(rest);
      if (volume != null) {
        return _ParsedTelegramCommand('set_volume', {'volume': volume});
      }
    }
    if (lower == 'volup' || lower == 'vol+' || lower == 'volume up' || lower == 'رفع الصوت' || lower == 'علي الصوت') {
      return const _ParsedTelegramCommand('volume_up');
    }
    if (lower == 'voldown' || lower == 'vol-' || lower == 'volume down' || lower == 'خفض الصوت' || lower == 'وطي الصوت') {
      return const _ParsedTelegramCommand('volume_down');
    }
    if (lower == 'mute' || lower == 'كتم' || lower == 'كتم الصوت') {
      return const _ParsedTelegramCommand('mute_volume');
    }
    if (lower == 'unmute' || lower == 'الغاء كتم' || lower == 'إلغاء الكتم') {
      return const _ParsedTelegramCommand('unmute_volume');
    }

    // WiFi & Internet Commands
    if ((first == 'wifi' && rest.toLowerCase() == 'on') ||
        lower == 'تشغيل الواي فاي' ||
        lower == 'واي فاي تشغيل') {
      return const _ParsedTelegramCommand('wifi_on');
    }
    if ((first == 'wifi' && rest.toLowerCase() == 'off') ||
        lower == 'ايقاف الواي فاي' ||
        lower == 'إيقاف الواي فاي' ||
        lower == 'واي فاي ايقاف') {
      return const _ParsedTelegramCommand('wifi_off');
    }
    if (lower == 'internet off' ||
        lower == 'net off' ||
        lower == 'ايقاف الانترنت نهائيا' ||
        lower == 'إيقاف الانترنت نهائياً' ||
        lower == 'قطع الانترنت') {
      return const _ParsedTelegramCommand('internet_off_permanent');
    }
    if (lower == 'internet on' ||
        lower == 'net on' ||
        lower == 'تشغيل الانترنت' ||
        lower == 'تشغيل الإنترنت' ||
        lower == 'اعادة الانترنت') {
      return const _ParsedTelegramCommand('internet_on');
    }

    // Bluetooth Commands
    if ((first == 'bluetooth' || first == 'bt') && rest.toLowerCase() == 'on') {
      return const _ParsedTelegramCommand('bluetooth_on');
    }
    if ((first == 'bluetooth' || first == 'bt') &&
        rest.toLowerCase() == 'off') {
      return const _ParsedTelegramCommand('bluetooth_off');
    }
    if ((first == 'bluetooth' || first == 'bt') &&
        (rest.toLowerCase() == 'devices' || rest.toLowerCase() == 'list')) {
      return const _ParsedTelegramCommand('list_bluetooth_devices');
    }
    if ((first == 'bluetooth' || first == 'bt') &&
        rest.toLowerCase().startsWith('send ')) {
      final path = rest.substring('send '.length).trim();
      return _ParsedTelegramCommand('send_bluetooth_file', {'path': path});
    }
    if ((first == 'bluetooth' || first == 'bt') &&
        rest.toLowerCase().startsWith('receive')) {
      final savePath = rest.substring('receive'.length).trim();
      return _ParsedTelegramCommand('open_bluetooth_receive',
          savePath.isEmpty ? const {} : {'savePath': savePath});
    }

    // App & Website Blocking / Permissions
    if (first == 'close' || first == 'kill' || first == 'اغلق' || first == 'إغلاق_تطبيق') {
      return _ParsedTelegramCommand('close_application', {'target': rest});
    }
    if (lower.startsWith('block app ') || lower.startsWith('منع تطبيق ')) {
      final target = lower.startsWith('block app ')
          ? normalized.substring('block app '.length).trim()
          : normalized.substring('منع تطبيق '.length).trim();
      return _ParsedTelegramCommand('block_application', {'target': target});
    }
    if (lower.startsWith('allow app ') || lower.startsWith('سماح لتطبيق ')) {
      final target = lower.startsWith('allow app ')
          ? normalized.substring('allow app '.length).trim()
          : normalized.substring('سماح لتطبيق '.length).trim();
      return _ParsedTelegramCommand('allow_application', {'target': target});
    }
    if (lower.startsWith('block site ') || lower.startsWith('حظر موقع ')) {
      final target = lower.startsWith('block site ')
          ? normalized.substring('block site '.length).trim()
          : normalized.substring('حظر موقع '.length).trim();
      return _ParsedTelegramCommand('block_website', {'domain': target});
    }
    if (lower.startsWith('allow site ') || lower.startsWith('سماح لموقع ')) {
      final target = lower.startsWith('allow site ')
          ? normalized.substring('allow site '.length).trim()
          : normalized.substring('سماح لموقع '.length).trim();
      return _ParsedTelegramCommand('allow_website', {'domain': target});
    }

    // Files & Explorer Commands
    if (lower.startsWith('browse ') || lower.startsWith('تصفح ')) {
      final path = lower.startsWith('browse ')
          ? normalized.substring('browse '.length).trim()
          : normalized.substring('تصفح '.length).trim();
      return _ParsedTelegramCommand('browse_path', {'path': path});
    }
    if (lower.startsWith('search ') || lower.startsWith('find ') || lower.startsWith('بحث ')) {
      final query = lower.startsWith('search ')
          ? normalized.substring('search '.length).trim()
          : lower.startsWith('find ')
              ? normalized.substring('find '.length).trim()
              : normalized.substring('بحث '.length).trim();
      return _ParsedTelegramCommand('search_files', {'query': query, 'rootPath': 'home'});
    }
    if (lower.startsWith('open ') || lower.startsWith('افتح ')) {
      final path = lower.startsWith('open ')
          ? normalized.substring('open '.length).trim()
          : normalized.substring('افتح '.length).trim();
      return _ParsedTelegramCommand('open_path', {'path': path});
    }
    if (lower.startsWith('delete ') || lower.startsWith('حذف ')) {
      final path = lower.startsWith('delete ')
          ? normalized.substring('delete '.length).trim()
          : normalized.substring('حذف '.length).trim();
      return _ParsedTelegramCommand('delete_path', {'path': path});
    }
    if (lower.startsWith('hide ') || lower.startsWith('إخفاء ')) {
      final path = lower.startsWith('hide ')
          ? normalized.substring('hide '.length).trim()
          : normalized.substring('إخفاء '.length).trim();
      return _ParsedTelegramCommand('hide_path', {'path': path});
    }
    if (lower.startsWith('unhide ') || lower.startsWith('إظهار ')) {
      final path = lower.startsWith('unhide ')
          ? normalized.substring('unhide '.length).trim()
          : normalized.substring('إظهار '.length).trim();
      return _ParsedTelegramCommand('unhide_path', {'path': path});
    }

    // Messages & Dialogs
    if (lower.startsWith('message ') ||
        lower.startsWith('msg ') ||
        lower.startsWith('رسالة ')) {
      final prefix = lower.startsWith('message ')
          ? 'message '
          : lower.startsWith('msg ')
              ? 'msg '
              : 'رسالة ';
      final message = normalized.substring(prefix.length).trim();
      return _ParsedTelegramCommand('show_message', {'message': message});
    }

    // System Utilities
    if (lower == 'logs' || lower == 'سجلات' || lower == 'السجلات') {
      return const _ParsedTelegramCommand('request_logs');
    }
    if (lower == 'qr' || lower == 'رمز الربط') {
      return const _ParsedTelegramCommand('show_pairing_qr');
    }
    if (lower == 'permissions' ||
        lower == 'اذونات' ||
        lower == 'أذونات' ||
        lower == 'الأذونات') {
      return const _ParsedTelegramCommand('show_permission_center');
    }
    if (lower == 'stop commands' || lower == 'ايقاف الاوامر' || lower == '/stop') {
      return const _ParsedTelegramCommand('stop_all_commands');
    }

    return null;
  }

  String _normalizeCommandText(String text) {
    var normalized = text.trim();
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
      final spaceIndex = normalized.indexOf(' ');
      final firstToken = spaceIndex == -1
          ? normalized
          : normalized.substring(0, spaceIndex);
      final commandOnly = firstToken.split('@').first;
      normalized = spaceIndex == -1
          ? commandOnly
          : '$commandOnly ${normalized.substring(spaceIndex + 1)}';
    }

    normalized = normalized.replaceFirst(
      RegExp(r'^[^A-Za-z0-9\u0600-\u06FF/]+'),
      '',
    );
    return normalized.trim();
  }

  String _formatResult(String type, CommandExecutionResult result) {
    final prefix = result.success ? '✅ <b>تمت العملية بنجاح</b>' : '❌ <b>فشلت العملية</b>';
    final payload = _briefPayload(type, result.payload);
    return _truncate(
      '$prefix\n'
      '📌 <b>الأمر:</b> <code>$type</code>\n'
      '💬 <b>النتيجة:</b> ${result.message}'
      '${payload.isEmpty ? '' : '\n\n$payload'}',
    );
  }

  String _briefPayload(String type, Map<String, dynamic> payload) {
    if (payload.isEmpty) return '';

    // File lists
    if (type == 'browse_path' || type == 'search_files') {
      final items = (payload['items'] as List?) ?? const [];
      final lines = items.take(12).map((item) {
        if (item is! Map) return item.toString();
        final name = (item['name'] ?? '').toString();
        final path = (item['path'] ?? '').toString();
        final isDir = item['type'] == 'directory' || item['type'] == 'drive';
        final icon = isDir ? '📁' : '📄';
        return '$icon <b>$name</b>\n   <code>/get $path</code>';
      }).join('\n');
      return lines;
    }

    // Open apps
    if (type == 'list_open_apps' || type == 'open_apps') {
      final apps = (payload['apps'] as List?) ?? const [];
      final lines = apps.take(15).map((app) {
        if (app is! Map) return app.toString();
        final name = (app['appName'] ?? app['name'] ?? 'App').toString();
        final pid = (app['processId'] ?? app['pid'] ?? '').toString();
        final title = (app['windowTitle'] ?? app['title'] ?? '').toString();
        return '🔹 <b>$name</b> (PID: <code>$pid</code>)\n   ${title.isNotEmpty ? title : ''}';
      }).join('\n');
      return lines;
    }

    // Installed apps
    if (type == 'list_installed_apps' || type == 'installed_apps') {
      final apps = (payload['apps'] as List?) ?? const [];
      final lines = apps.take(15).map((app) {
        if (app is! Map) return app.toString();
        final name = (app['name'] ?? app['displayName'] ?? 'App').toString();
        final version = (app['version'] ?? '').toString();
        return '📦 <b>$name</b> ${version.isNotEmpty ? '($version)' : ''}';
      }).join('\n');
      return lines;
    }

    // Blocked items
    if (type == 'list_blocked_items' || type == 'blocked_items') {
      final items = (payload['items'] as List?) ?? const [];
      final lines = items.map((item) {
        if (item is! Map) return item.toString();
        final target = (item['target'] ?? item['domain'] ?? '').toString();
        final type = (item['type'] ?? 'app').toString();
        final icon = type == 'site' ? '🌐' : '🚫';
        return '$icon <b>$target</b> ($type)';
      }).join('\n');
      return lines.isNotEmpty ? lines : 'لا توجد عناصر ممنوعة حالياً.';
    }

    // Path rules
    if (type == 'list_path_rules' || type == 'path_rules') {
      final rules = (payload['rules'] as List?) ?? const [];
      final lines = rules.map((r) {
        if (r is! Map) return r.toString();
        final path = (r['path'] ?? '').toString();
        final lockType = (r['lockType'] ?? 'permissionRequired').toString();
        return '🛡️ <b>$path</b> ($lockType)';
      }).join('\n');
      return lines.isNotEmpty ? lines : 'لا توجد قواعد حماية مسارات حالياً.';
    }

    // Smart Insights
    if (type == 'smart_insights') {
      final open = payload['openAppsCount'] ?? 0;
      final installed = payload['installedAppsCount'] ?? 0;
      final blocked = payload['blockedItemsCount'] ?? 0;
      final rules = payload['pathRulesCount'] ?? 0;
      final logs = payload['logsCount'] ?? 0;
      return '📊 <b>إحصائيات النظام السريعة:</b>\n'
          '• البرامج الشغالة الآن: $open\n'
          '• إجمالي البرامج المثبتة: $installed\n'
          '• العناصر والمواقع الممنوعة: $blocked\n'
          '• قواعد حماية المسارات: $rules\n'
          '• إجمالي السجلات المسجلة: $logs';
    }

    return '';
  }

  Map<String, dynamic>? _resultInlineButtons(String type, Map<String, dynamic> payload) {
    if (type == 'browse_path' || type == 'search_files') {
      final items = (payload['items'] as List?) ?? const [];
      final fileButtons = <List<Map<String, String>>>[];
      for (final item in items.take(4)) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final path = (item['path'] ?? '').toString();
        final isDir = item['type'] == 'directory' || item['type'] == 'drive';
        if (!isDir && path.isNotEmpty) {
          fileButtons.add([
            {
              'text':
                  '⬇️ تحميل: ${name.length > 18 ? '${name.substring(0, 18)}...' : name}',
              'callback_data': 'get_file:$path',
            },
            {
              'text': '📂 فتح',
              'callback_data': 'exec_open:$path',
            },
          ]);
        }
      }
      fileButtons.add([
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);
      return {'inline_keyboard': fileButtons};
    }

    if (type == 'list_open_apps' || type == 'open_apps') {
      final apps = (payload['apps'] as List?) ?? const [];
      final buttons = <List<Map<String, String>>>[];
      for (final app in apps.take(4)) {
        if (app is! Map) continue;
        final name = (app['appName'] ?? app['name'] ?? 'App').toString();
        final pid = (app['processId'] ?? app['pid'] ?? '').toString();
        if (name.isNotEmpty) {
          buttons.add([
            {
              'text': '❌ إغلاق: $name',
              'callback_data': 'close_app:${pid.isNotEmpty ? pid : name}',
            },
          ]);
        }
      }
      buttons.add([
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);
      return {'inline_keyboard': buttons};
    }

    return null;
  }

  String _truncate(String text, {int max = 3800}) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...\n(تم اختصار النص)';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _textFromCallbackData(String data) {
    switch (data) {
      case 'status':
        return 'status';
      case 'screenshot':
        return 'screenshot';
      case 'health':
        return 'health';
      case 'emergency':
        return 'emergency';
      case 'lock':
        return 'lock';
      case 'lock_5':
        return 'lock 5';
      case 'lock_15':
        return 'lock 15';
      case 'lock_30':
        return 'lock 30';
      case 'lock_60':
        return 'lock 60';
      case 'lock_120':
        return 'lock 120';
      case 'unlock':
        return 'unlock';
      case 'shutdown':
        return 'shutdown';
      case 'shutdown_15':
        return 'shutdown 15';
      case 'shutdown_30':
        return 'shutdown 30';
      case 'restart':
        return 'restart';
      case 'logout':
        return 'logout';
      case 'mode_study':
        return 'mode study';
      case 'mode_work':
        return 'mode work';
      case 'mode_kids':
        return 'mode kids';
      case 'mode_protection':
        return 'mode protection';
      case 'privacy_on':
        return 'privacy on';
      case 'privacy_off':
        return 'privacy off';
      case 'undo':
        return 'undo';
      case 'logs':
        return 'logs';
      case 'wifi_on':
        return 'wifi on';
      case 'wifi_off':
        return 'wifi off';
      case 'net_off':
        return 'internet off';
      case 'net_on':
        return 'internet on';
      case 'vol_up':
        return 'volup';
      case 'vol_down':
        return 'voldown';
      case 'vol_mute':
        return 'mute';
      case 'vol_unmute':
        return 'unmute';
      case 'vol_10':
        return 'volume 10';
      case 'vol_25':
        return 'volume 25';
      case 'vol_50':
        return 'volume 50';
      case 'vol_75':
        return 'volume 75';
      case 'vol_100':
        return 'volume 100';
      case 'bt_on':
        return 'bluetooth on';
      case 'bt_off':
        return 'bluetooth off';
      case 'bt_devices':
        return 'bluetooth devices';
      case 'open_apps':
        return 'open_apps';
      case 'installed_apps':
        return 'installed_apps';
      case 'blocked_items':
        return 'blocked_items';
      case 'path_rules':
        return 'path_rules';
      case 'smart_insights':
        return 'smart_insights';
      case 'qr':
        return 'qr';
      case 'permissions':
        return 'permissions';
      case 'msg_break':
        return 'message حان وقت الاستراحة، يرجى الابتعاد عن الشاشة.';
      case 'msg_save':
        return 'message تنبيه: يرجى حفظ جميع أعمالك وإغلاق البرامج.';
      case 'msg_urgent':
        return 'message تنبيه عاجل: مطلوب التحدث مع مسؤول النظام.';
      case 'browse_downloads':
        return 'browse ${_getKnownFolder('Downloads')}';
      case 'browse_desktop':
        return 'browse ${_getKnownFolder('Desktop')}';
      case 'browse_documents':
        return 'browse ${_getKnownFolder('Documents')}';
      case 'browse_c':
        return r'browse C:\';
      case 'browse_d':
        return r'browse D:\';
      case 'browse_roots':
        return 'browse roots';
      default:
        return data;
    }
  }

  String _dashboardText() {
    return '⚡ <b>لوحة تحكم KIOM التفاعلية بالكمبيوتر (سحابة Telegram):</b>\n'
        '🖥️ <b>الجهاز:</b> $deviceName ($deviceId)\n\n'
        'اختر أحد الأقسام أدناه للتحكم الشامل، أو أرسل أي ملف للمحادثة ليتم حفظه بالكمبيوتر فوراً:';
  }

  Map<String, dynamic> _dashboardInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('📸 لقطة شاشة', 'screenshot'),
          button('📊 صحة الجهاز', 'health'),
          button('⚡ وضع الطوارئ', 'emergency'),
        ],
        [
          button('📁 مدير الملفات', 'menu_files'),
          button('👁️ البرامج والتطبيقات', 'menu_apps'),
          button('🔒 قفل وطاقة', 'menu_power'),
        ],
        [
          button('🎛️ الأوضاع الذكية', 'menu_modes'),
          button('🌐 الشبكة والبلوتوث', 'menu_network'),
          button('🔊 التحكم بالصوت', 'menu_audio'),
        ],
        [
          button('💬 إرسال رسالة', 'menu_messages'),
          button('📈 السجلات والتحليلات', 'menu_insights'),
          button('🛡️ الأمان والحماية', 'menu_security'),
        ],
        [
          button('↩️ تراجع عن أمر', 'undo'),
          button('🔑 رمز QR', 'qr'),
          button('📖 دليل الأوامر', 'menu_help'),
        ],
      ],
    };
  }

  Map<String, dynamic> _filesInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('📥 مجلد التنزيلات', 'browse_downloads'),
          button('🖥️ سطح المكتب', 'browse_desktop'),
        ],
        [
          button('📁 المستندات', 'browse_documents'),
          button('💾 القرص C:\\', 'browse_c'),
          button('💾 القرص D:\\', 'browse_d'),
        ],
        [
          button('💾 جميع الأقراص', 'browse_roots'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _appsInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('👁️ التطبيقات المفتوحة الحالية', 'open_apps'),
        ],
        [
          button('📦 البرامج المثبتة على الكمبيوتر', 'installed_apps'),
        ],
        [
          button('🚫 قائمة العناصر والمواقع الممنوعة', 'blocked_items'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _powerInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('⏱️ قفل 5 دقائق', 'lock_5'),
          button('⏱️ قفل 15 دقيقة', 'lock_15'),
          button('⏱️ قفل 30 دقيقة', 'lock_30'),
        ],
        [
          button('⏱️ قفل ساعة', 'lock_60'),
          button('⏱️ قفل ساعتين', 'lock_120'),
          button('🔒 قفل دائم', 'lock'),
        ],
        [
          button('🔓 إلغاء وفتح القفل', 'unlock'),
        ],
        [
          button('🔴 إغلاق الكمبيوتر فوراً', 'shutdown'),
          button('⏱️ إغلاق بعد 30د', 'shutdown_30'),
        ],
        [
          button('🔄 إعادة التشغيل (Restart)', 'restart'),
          button('👤 تسجيل الخروج', 'logout'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _modesInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('📚 وضع الدراسة', 'mode_study'),
          button('💼 وضع العمل والتركيز', 'mode_work'),
        ],
        [
          button('👶 وضع الأطفال', 'mode_kids'),
          button('🛡️ الحماية القصوى', 'mode_protection'),
        ],
        [
          button('🕶️ تشغيل الخصوصية', 'privacy_on'),
          button('👁️ إيقاف الخصوصية', 'privacy_off'),
        ],
        [
          button('⚡ وضع الطوارئ', 'emergency'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _networkInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('📶 تشغيل WiFi', 'wifi_on'),
          button('📴 إيقاف WiFi', 'wifi_off'),
        ],
        [
          button('🚫 قطع الإنترنت نهائياً', 'net_off'),
          button('🌐 إعادة الإنترنت', 'net_on'),
        ],
        [
          button('🔵 تشغيل Bluetooth', 'bt_on'),
          button('⚫ إيقاف Bluetooth', 'bt_off'),
        ],
        [
          button('📱 فحص أجهزة Bluetooth', 'bt_devices'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _audioInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('🔇 كتم الصوت', 'vol_mute'),
          button('🔊 إلغاء الكتم', 'vol_unmute'),
        ],
        [
          button('➕ +10%', 'vol_up'),
          button('➖ -10%', 'vol_down'),
        ],
        [
          button('10%', 'vol_10'),
          button('25%', 'vol_25'),
          button('50%', 'vol_50'),
          button('75%', 'vol_75'),
          button('100%', 'vol_100'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _messagesInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('☕ حان وقت الاستراحة', 'msg_break'),
        ],
        [
          button('💾 تنبيه: يرجى حفظ العمل', 'msg_save'),
        ],
        [
          button('⚠️ تنبيه عاجل من الإدارة', 'msg_urgent'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _insightsInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('📊 التحليلات الذكية والملخص', 'smart_insights'),
          button('📊 صحة ومواصفات الجهاز', 'health'),
        ],
        [
          button('📜 طلب سجلات النشاط', 'logs'),
          button('📸 التقاط صورة الشاشة', 'screenshot'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Map<String, dynamic> _securityInlineMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('🛡️ قواعد حماية المسارات', 'path_rules'),
          button('🚫 قائمة الممنوعات', 'blocked_items'),
        ],
        [
          button('⚙️ فتح شاشة الأذونات بالكمبيوتر', 'permissions'),
          button('🔑 إظهار رمز الربط QR', 'qr'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  String _helpText() {
    return '📖 <b>الدليل الشامل للتحكم بالكمبيوتر عبر سحابة Telegram:</b>\n\n'
        '📁 <b>الملفات وتبادل البيانات:</b>\n'
        '• أرسل أي ملف للمحادثة وسيتم حفظه في <code>Downloads</code> بالكمبيوتر تلقائياً.\n'
        '• <code>/get C:\\path\\file.ext</code>: إرسال أي ملف من الكمبيوتر إلى Telegram.\n'
        '• <code>/search تقرير</code>: بحث عن ملفات في الكمبيوتر وتحميلها.\n'
        '• <code>/open C:\\path\\file.ext</code>: فتح ملف على شاشة الكمبيوتر.\n'
        '• <code>/delete C:\\path\\file.ext</code>: حذف ملف.\n'
        '• <code>/browse roots</code>: استعراض أقراص وملفات الكمبيوتر.\n\n'
        '👁️ <b>البرامج والتطبيقات:</b>\n'
        '• <code>/apps</code>: عرض البرامج المفتوحة ونوافذ المتصفح.\n'
        '• <code>/close chrome.exe</code>: إغلاق برنامج.\n'
        '• <code>/blockapp game.exe</code>: منع تشغيل برنامج.\n'
        '• <code>/allowapp game.exe</code>: السماح لبرنامج.\n'
        '• <code>/blocksite youtube.com</code>: حظر موقع.\n'
        '• <code>/allowsite youtube.com</code>: السماح لموقع.\n'
        '• <code>/installed</code>: عرض البرامج المثبتة.\n\n'
        '🔒 <b>التحكم والطاقة:</b>\n'
        '• <code>status</code>: فحص الاتصال.\n'
        '• <code>screenshot</code>: لقطة شاشة فورية.\n'
        '• <code>health</code>: صحة الجهاز (CPU, RAM, Disks).\n'
        '• <code>lock</code>: قفل شاشة الكمبيوتر.\n'
        '• <code>lock 30</code>: قفل لمدة 30 دقيقة.\n'
        '• <code>unlock</code>: إلغاء القفل.\n'
        '• <code>emergency</code>: وضع الطوارئ الشامل.\n'
        '• <code>shutdown</code>: إغلاق الكمبيوتر (مع زر تأكيد).\n'
        '• <code>restart</code>: إعادة التشغيل (مع زر تأكيد).\n'
        '• <code>wifi on/off</code> | <code>internet on/off</code> | <code>bt on/off</code>\n'
        '• <code>volume 50</code> | <code>volup</code> | <code>voldown</code> | <code>mute</code>\n'
        '• <code>msg مرحباً</code>: إظهار رسالة منبثقة على شاشة الكمبيوتر.\n'
        '• <code>mode study/work/kids/protection</code>: الأوضاع الذكية.\n'
        '• <code>privacy on/off</code>: وضع الخصوصية.\n'
        '• <code>undo</code>: التراجع عن آخر أمر.';
  }
}

class _PendingConfirmation {
  const _PendingConfirmation({
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

class _ParsedTelegramCommand {
  const _ParsedTelegramCommand(
    this.type, [
    this.payload = const <String, dynamic>{},
  ]);

  final String type;
  final Map<String, dynamic> payload;
}
