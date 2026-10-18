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

  String _lastPolledBotToken = '';
  String _lastPolledCloudDbToken = '';
  final Map<int, Map<String, dynamic>> _logActionItems = {};
  final Map<String, Map<String, dynamic>> _appActionItems = {};

  Future<void> _pollCloudDb() async {
    if (_cloudDbPolling || cloudDbTelegram == null || !cloudDbTelegram!.hasBotToken) return;
    _cloudDbPolling = true;
    try {
      final currentToken = cloudDbTelegram!.botToken;
      if (currentToken != _lastPolledCloudDbToken) {
        _lastPolledCloudDbToken = currentToken;
        final saved = store.get<String>('telegram_saved_cloud_db_token');
        if (saved != currentToken) {
          await store.set('telegram_saved_cloud_db_token', currentToken);
          await store.set('telegramCloudDbLastUpdateOffset', null);
        }
      }

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
    final message = ((update['message'] ?? update['channel_post']) as Map?)?.cast<String, dynamic>();
    if (message == null) return;

    final chat = (message['chat'] as Map?)?.cast<String, dynamic>();
    final chatId = (chat?['id'] ?? '').toString();
    if (chatId.isEmpty) return;

    final messageId = (message['message_id'] as num?)?.toInt();
    final text = (message['text'] ?? message['caption'] ?? '').toString().trim();
    if (text.startsWith('#KIOM_CMD')) {
      final jsonStr = text.substring('#KIOM_CMD'.length).trim();
      await _handleMobileCloudCommand(
        jsonStr,
        chatId: chatId,
        messageId: messageId,
        targetTelegram: cloudDbTelegram ?? telegram,
      );
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final currentToken = telegram.botToken;
      if (currentToken != _lastPolledBotToken) {
        _lastPolledBotToken = currentToken;
        final saved = store.get<String>('telegram_saved_bot_token');
        if (saved != currentToken) {
          await store.set('telegram_saved_bot_token', currentToken);
          await store.set('telegramLastUpdateOffset', null);
        }
      }

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
        messageId: messageId,
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

    // Auto-authorize if no chat ID was set, or if user explicitly requested start/bind
    if (allowedChatId.isEmpty || isGreetingOrBind) {
      await store.set('telegramChatIdOverride', chatId);
      allowedChatId = chatId;
    }

    // If chat is still empty, accept this sender as active controller
    if (allowedChatId.isEmpty) {
      allowedChatId = chatId;
      await store.set('telegramChatIdOverride', chatId);
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
    int? messageId,
    TelegramNotifierService? targetTelegram,
  }) async {
    final sender = targetTelegram ?? cloudDbTelegram ?? telegram;
    try {
      final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;
      final targetDeviceId = (envelope['deviceId'] ?? '').toString();
      // If targeted at ANOTHER device, do NOT execute and do NOT delete!
      if (targetDeviceId.isNotEmpty &&
          targetDeviceId != deviceId &&
          targetDeviceId != 'primary_pc' &&
          targetDeviceId != 'all' &&
          !deviceId.startsWith(targetDeviceId)) {
        return;
      }

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

      // Delete the executed mobile command message if messageId is known
      if (messageId != null) {
        unawaited(sender.deleteMessage(messageId: messageId, chatId: chatId));
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

  Future<void> _editOrSendMessage(
    String text, {
    required String chatId,
    int? messageId,
    Map<String, dynamic>? replyMarkup,
    String parseMode = 'HTML',
  }) async {
    if (messageId != null) {
      final edited = await telegram.editMessageText(
        text: text,
        chatId: chatId,
        messageId: messageId,
        replyMarkup: replyMarkup,
        parseMode: parseMode,
      );
      if (edited) return;
    }
    await telegram.sendMessage(
      text,
      chatId: chatId,
      replyMarkup: replyMarkup,
      parseMode: parseMode,
    );
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
        await _editOrSendMessage(
          '⚠️ انتهت صلاحية هذا التأكيد أو تم تنفيذه مسبقاً.',
          chatId: chatId,
          messageId: messageId,
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
      await _editOrSendMessage(
        '🚫 <b>تم إلغاء العملية بأمان.</b>',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return;
    }

    // 2. Navigation sub-menus
    await telegram.answerCallbackQuery(id, text: 'تم الاختيار');

    if (data == 'menu_main' || data == 'menu') {
      await _editOrSendMessage(
        _dashboardText(),
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return;
    }
    if (data == 'menu_files') {
      await _editOrSendMessage(
        '📁 <b>إدارة الملفات بالكمبيوتر:</b>\n\n'
        '• تصفح الأقراص والمجلدات المباشرة\n'
        '• <code>/get C:\\path\\file.pdf</code> لإرسال أي ملف لتليجرام\n'
        '• <code>/search تقرير</code> للبحث عن ملفات\n'
        '• أو أرسل أي ملف للمحادثة وسيتم حفظه في الكمبيوتر فوراً!',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _filesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_apps') {
      await _editOrSendMessage(
        '👁️ <b>إدارة البرامج والتطبيقات:</b>\n'
        'عرض التطبيقات الشغالة، إغلاق البرامج، أو منع المواقع والتطبيقات:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _appsInlineMenu(),
      );
      return;
    }
    if (data == 'menu_power') {
      await _editOrSendMessage(
        '🔒 <b>الطاقة والقفل والجدولة الذكية:</b>\n'
        'اختر مدة القفل أو وقت إغلاق الجهاز:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _powerInlineMenu(),
      );
      return;
    }
    if (data == 'menu_modes') {
      await _editOrSendMessage(
        '🎛️ <b>الأوضاع الذكية الجاهزة:</b>\nاختر الوضع المطلوب لتطبيقه فوراً على الكمبيوتر:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _modesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_network') {
      await _editOrSendMessage(
        '🌐 <b>التحكم بالشبكة والبلوتوث:</b>\nتشغيل وإيقاف WiFi والإنترنت والبلوتوث بنقرة واحدة:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _networkInlineMenu(),
      );
      return;
    }
    if (data == 'menu_audio') {
      await _editOrSendMessage(
        '🔊 <b>التحكم السريع بمستوى الصوت:</b>\nاختر النسبة المطلوبة فوراً:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _audioInlineMenu(),
      );
      return;
    }
    if (data == 'menu_messages') {
      await _editOrSendMessage(
        '💬 <b>إرسال رسائل وتنبيهات لشاشة الكمبيوتر:</b>\nاختر قالباً جاهزاً أو اكتب <code>/msg نص_الرسالة</code>:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _messagesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_insights') {
      await _editOrSendMessage(
        '📊 <b>السجلات والتحليلات والصحة:</b>\nاختر التقرير المطلوب:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _insightsInlineMenu(),
      );
      return;
    }
    if (data == 'menu_security') {
      await _editOrSendMessage(
        '🛡️ <b>الحماية والأذونات والتثبيت:</b>\nإدارة قواعد الحماية وطلبات الإذن والتثبيت:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _securityInlineMenu(),
      );
      return;
    }
    if (data == 'menu_help') {
      await _editOrSendMessage(
        _helpText(),
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return;
    }

    // 3. Direct execution from callback data
    if (data.startsWith('inst_allow_15:') ||
        data.startsWith('inst_allow_60:') ||
        data.startsWith('inst_allow_perm:') ||
        data.startsWith('inst_reject:')) {
      final isPerm = data.startsWith('inst_allow_perm:');
      final is60 = data.startsWith('inst_allow_60:');
      final isReject = data.startsWith('inst_reject:');

      final reqId = isReject
          ? data.substring('inst_reject:'.length)
          : (isPerm
              ? data.substring('inst_allow_perm:'.length)
              : (is60 ? data.substring('inst_allow_60:'.length) : data.substring('inst_allow_15:'.length)));

      if (isReject) {
        await executor.executeTelegramCommand(
          type: 'reject_install',
          payload: {'requestId': reqId},
        );
        await _editOrSendMessage(
          '🚫 <b>تم رفض محاولة التثبيت وحظر المثبت بنجاح.</b>',
          chatId: chatId,
          messageId: messageId,
        );
      } else {
        final durationSecs = isPerm ? 3650 * 86400 : (is60 ? 3600 : 900);
        await executor.executeTelegramCommand(
          type: 'approve_install',
          payload: {
            'requestId': reqId,
            'durationSeconds': durationSecs,
            'always': isPerm,
          },
        );
        final durText = isPerm ? 'دائم' : (is60 ? 'ساعة واحدة' : '15 دقيقة');
        await _editOrSendMessage(
          '✅ <b>تمت الموافقة على التثبيت بنجاح (المدة: $durText).</b>\nيمكن تشغيل المثبت الآن بحرية.',
          chatId: chatId,
          messageId: messageId,
        );
      }
      return;
    }

    if (data.startsWith('dl_url:')) {
      final url = data.substring('dl_url:'.length);
      await _handleControlCommand('download $url', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('cloud_upload:')) {
      final path = data.substring('cloud_upload:'.length);
      await _handleControlCommand('cloud_upload $path', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('copy_clip:')) {
      final text = data.substring('copy_clip:'.length);
      await _handleExecutableText('copy $text', chatId: chatId, replyToMessageId: messageId);
      return;
    }
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
    if (data.startsWith('log_filter:')) {
      final filterParam = data.substring('log_filter:'.length);
      await _handleLogFilterCallback(filterParam, chatId: chatId, messageId: messageId);
      return;
    }
    if (data.startsWith('lock_type_menu:')) {
      final path = data.substring('lock_type_menu:'.length);
      await _editOrSendMessage(
        '🛡️ <b>اختيار نوع الحماية والقفل للمسار:</b>\n<code>$path</code>\n\nاختر نوع القفل المناسب:',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: _allLockTypesMenu(path),
      );
      return;
    }
    if (data.startsWith('lock_type:')) {
      final rest = data.substring('lock_type:'.length);
      final colon = rest.indexOf(':');
      if (colon != -1) {
        final lockType = rest.substring(0, colon);
        final path = rest.substring(colon + 1);
        await executor.executeTelegramCommand(
          type: 'protect_path',
          payload: {'path': path, 'lockType': lockType},
        );
        final typeLabel = switch (lockType) {
          'password' => 'بكلمة مرور',
          'permissionRequired' => 'باشتراط إذن الهاتف',
          'readOnly' => 'قراءة فقط',
          _ => 'نهائي',
        };
        await _editOrSendMessage(
          '✅ <b>تم قفل وحماية المسار بنجاح (نوع القفل: $typeLabel):</b>\n<code>$path</code>',
          chatId: chatId,
          messageId: messageId,
          replyMarkup: {
            'inline_keyboard': [
              [{'text': '🔓 إلغاء القفل', 'callback_data': 'unprotect_path:$path'}],
              [{'text': '🔙 العودة للسجل', 'callback_data': 'logs'}],
            ],
          },
        );
      }
      return;
    }
    if (data.startsWith('lock_timed_menu:')) {
      final path = data.substring('lock_timed_menu:'.length);
      await _editOrSendMessage(
        '⏳ <b>اختيار مهلة القفل المؤقت للمسار:</b>\n<code>$path</code>',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: {
          'inline_keyboard': [
            [
              {'text': '⏳ 15 دقيقة', 'callback_data': 'lock_timed:$path:15'},
              {'text': '⏳ 30 دقيقة', 'callback_data': 'lock_timed:$path:30'},
            ],
            [
              {'text': '⏳ ساعة واحدة', 'callback_data': 'lock_timed:$path:60'},
              {'text': '⏳ 6 ساعات', 'callback_data': 'lock_timed:$path:360'},
            ],
            [
              {'text': '⏳ 24 ساعة (يوم)', 'callback_data': 'lock_timed:$path:1440'},
            ],
            [
              {'text': '🔙 عودة', 'callback_data': 'lock_type_menu:$path'},
            ],
          ],
        },
      );
      return;
    }
    if (data.startsWith('lock_timed:')) {
      final rest = data.substring('lock_timed:'.length);
      final lastColon = rest.lastIndexOf(':');
      if (lastColon != -1) {
        final path = rest.substring(0, lastColon);
        final mins = int.tryParse(rest.substring(lastColon + 1)) ?? 60;
        await executor.executeTelegramCommand(
          type: 'protect_path',
          payload: {'path': path, 'lockType': 'blocked', 'durationMinutes': mins},
        );
        await _editOrSendMessage(
          '⏳ <b>تم تفعيل القفل المؤقت بنجاح لمدة $mins دقيقة:</b>\n<code>$path</code>',
          chatId: chatId,
          messageId: messageId,
          replyMarkup: {
            'inline_keyboard': [
              [{'text': '🔓 إلغاء القفل فوراً', 'callback_data': 'unprotect_path:$path'}],
              [{'text': '🔙 العودة للسجل', 'callback_data': 'logs'}],
            ],
          },
        );
      }
      return;
    }
    if (data.startsWith('kill_proc:')) {
      final rest = data.substring('kill_proc:'.length);
      final parts = rest.split(':');
      final pid = parts[0];
      final name = parts.length > 1 ? parts[1] : pid;
      await SafeProcessRunner.run('taskkill.exe', ['/PID', pid, '/F']);
      await _editOrSendMessage(
        '❌ <b>تم إغلاق وإنهاء العملية فوراً بنجاح!</b>\n📦 التطبيق: <code>$name</code>\nPID: <code>$pid</code>',
        chatId: chatId,
        messageId: messageId,
        replyMarkup: {
          'inline_keyboard': [
            [{'text': '🔄 تحديث قائمة التطبيقات', 'callback_data': 'apps'}],
            [{'text': '🏠 القائمة الرئيسية', 'callback_data': 'menu_main'}],
          ],
        },
      );
      return;
    }
    if (data.startsWith('close_after:')) {
      final rest = data.substring('close_after:'.length);
      final parts = rest.split(':');
      final name = parts[0];
      final mins = parts.length > 1 ? (int.tryParse(parts[1]) ?? 15) : 15;
      await executor.executeTelegramCommand(
        type: 'close_application_after_delay',
        payload: {'target': name, 'delayMinutes': mins},
      );
      await _editOrSendMessage(
        '⏳ <b>تمت جدولة إغلاق التطبيق ($name) بعد $mins دقيقة بنجاح.</b>',
        chatId: chatId,
        messageId: messageId,
      );
      return;
    }
    if (data.startsWith('block_app_timed:')) {
      final rest = data.substring('block_app_timed:'.length);
      final parts = rest.split(':');
      final name = parts[0];
      final mins = parts.length > 1 ? (int.tryParse(parts[1]) ?? 60) : 60;
      await executor.executeTelegramCommand(
        type: 'block_application',
        payload: {'target': name, 'durationSeconds': mins * 60},
      );
      await _editOrSendMessage(
        '⏳ <b>تم حظر ومنع تشغيل التطبيق ($name) مؤقتاً لمدة $mins دقيقة بنجاح.</b>',
        chatId: chatId,
        messageId: messageId,
      );
      return;
    }
    if (data.startsWith('sync_onedrive:')) {
      final path = data.substring('sync_onedrive:'.length);
      await executor.windowsControl.syncFileToOneDrive(path);
      await _editOrSendMessage(
        '☁️ <b>تمت مزامنة الملف إلى OneDrive السحابي بنجاح!</b>\n<code>$path</code>',
        chatId: chatId,
        messageId: messageId,
      );
      return;
    }
    if (data.startsWith('sync_gdrive:')) {
      final path = data.substring('sync_gdrive:'.length);
      await executor.windowsControl.syncFileToGoogleDrive(path);
      await _editOrSendMessage(
        '☁️ <b>تمت مزامنة الملف إلى Google Drive السحابي بنجاح!</b>\n<code>$path</code>',
        chatId: chatId,
        messageId: messageId,
      );
      return;
    }
    if (data.startsWith('exec_open_url:')) {
      final domain = data.substring('exec_open_url:'.length);
      await executor.windowsControl.openBrowserUrl('https://$domain');
      await _editOrSendMessage(
        '🌐 <b>تم فتح الموقع على متصفح الكمبيوتر:</b>\n<code>$domain</code>',
        chatId: chatId,
        messageId: messageId,
      );
      return;
    }
    if (data.startsWith('browse_folder:')) {
      final path = data.substring('browse_folder:'.length);
      await _handleExecutableText('browse $path', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('lock_path:')) {
      final path = data.substring('lock_path:'.length);
      await _handleExecutableText('protect $path', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('unprotect_path:') || data.startsWith('unlock_path:') || data.startsWith('unlock_file:')) {
      final prefix = data.startsWith('unprotect_path:')
          ? 'unprotect_path:'
          : (data.startsWith('unlock_path:') ? 'unlock_path:' : 'unlock_file:');
      final path = data.substring(prefix.length);
      await _handleExecutableText('unprotect $path', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('delete_file:')) {
      final path = data.substring('delete_file:'.length);
      await _handleExecutableText('delete $path', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('close_app:')) {
      final target = data.substring('close_app:'.length);
      await _handleExecutableText('close $target', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('block_app:')) {
      final target = data.substring('block_app:'.length);
      await _handleExecutableText('block app $target', chatId: chatId, replyToMessageId: messageId);
      return;
    }
    if (data.startsWith('block_site:')) {
      final target = data.substring('block_site:'.length);
      await _handleExecutableText('block site $target', chatId: chatId, replyToMessageId: messageId);
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
    if (data.startsWith('allow_item:')) {
      final target = data.substring('allow_item:'.length);
      await _handleExecutableText('allow $target', chatId: chatId, replyToMessageId: messageId);
      return;
    }

    final callbackText = _textFromCallbackData(data);
    final handled = await _handleControlCommand(
      callbackText,
      chatId: chatId,
      replyToMessageId: messageId,
    );
    if (handled) return;

    await _handleExecutableText(
      callbackText,
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
        '⚠️ <b>الأمر غير معروف:</b> <code>$text</code>\n\n'
        'اختر أحد الأزرار التفاعلية أدناه للتحكم السريع، أو اضغط <b>📖 دليل الأوامر</b> لمعرفة الصيغ المتاحة:',
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

    // Delete user command input to keep chat clean
    if (replyToMessageId != null) {
      unawaited(telegram.deleteMessage(messageId: replyToMessageId, chatId: chatId));
    }

    final formattedText = _formatResult(parsed.type, result);
    final inlineMarkup = _resultInlineButtons(parsed.type, result.payload);

    await telegram.sendMessage(
      formattedText,
      chatId: chatId,
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

    if (lower == '/logs' ||
        lower == 'logs' ||
        lower == 'سجل' ||
        lower == 'السجل' ||
        lower == 'سجل العمليات' ||
        lower == 'سجل الانشطة' ||
        lower == 'سجل الأنشطة') {
      await telegram.sendMessage(
        '📜 <b>سجل الأنشطة والعمليات التفاعلي:</b>\n'
        'اختر تصنيف السجل أو الفترة الزمنية المطلوبة أدناه، أو أرسل أمر مخصص بالصيغة:\n'
        '• <code>/logs اليوم</code> أو <code>/logs امس</code>\n'
        '• <code>/logs ملفات</code> أو <code>/logs برامج</code> أو <code>/logs ممنوعات</code>\n'
        '• <code>/logs from 2026-10-18 08:00 to 2026-10-18 20:00</code>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _logFilterInlineMenu(),
      );
      return true;
    }

    if (lower.startsWith('/logs ') || lower.startsWith('logs ') || lower.startsWith('سجل ')) {
      final queryParam = text.substring(text.indexOf(' ') + 1).trim();
      await _handleCustomLogsQuery(queryParam, chatId: chatId, replyToMessageId: replyToMessageId);
      return true;
    }

    if (lower.startsWith('/act_') || lower.startsWith('act_')) {
      final normalized = _normalizeCommandText(text);
      final parts = normalized.split('_');
      final idx = int.tryParse(parts.last) ?? 0;
      final item = _logActionItems[idx];
      if (item != null) {
        final itemType = (item['type'] ?? 'file').toString();
        final path = (item['path'] ?? '').toString();
        final target = (item['target'] ?? '').toString();
        final title = (item['title'] ?? item['msg'] ?? '').toString();

        if (itemType == 'file' && path.isNotEmpty) {
          final fileName = path.replaceAll('/', r'\').split(r'\').last;
          await telegram.sendMessage(
            '📁 <b>لوحة التحكم في الملف/المسار:</b>\n'
            '📄 <b>الاسم:</b> <code>$fileName</code>\n'
            '📍 <b>المسار:</b> <code>$path</code>\n\n'
            'اختر الإجراء المطلوب تطبيقه فوراً:',
            chatId: chatId,
            replyToMessageId: replyToMessageId,
            replyMarkup: _fileActionInlineMenu(path),
          );
          return true;
        } else if (itemType == 'app') {
          final appName = target.isNotEmpty ? target : title;
          await telegram.sendMessage(
            '🖥️ <b>لوحة التحكم في التطبيق:</b>\n'
            '📦 <b>التطبيق:</b> <code>$appName</code>\n\n'
            'اختر الإجراء المطلوب تطبيقه:',
            chatId: chatId,
            replyToMessageId: replyToMessageId,
            replyMarkup: _appActionInlineMenu(name: appName, pid: (item['pid'] ?? '').toString(), title: title),
          );
          return true;
        } else if (itemType == 'site') {
          final siteDomain = target.isNotEmpty ? target : title;
          await telegram.sendMessage(
            '🌐 <b>لوحة التحكم في الموقع:</b>\n'
            '🔗 <b>الموقع:</b> <code>$siteDomain</code>\n\n'
            'اختر الإجراء المطلوب:',
            chatId: chatId,
            replyToMessageId: replyToMessageId,
            replyMarkup: _siteActionInlineMenu(siteDomain),
          );
          return true;
        }
      }
    }

    if (lower.startsWith('/app_') || lower.startsWith('app_') || lower.startsWith('/proc_') || lower.startsWith('proc_')) {
      final normalized = _normalizeCommandText(text);
      final token = normalized.substring(normalized.indexOf('_') + 1).trim();
      final app = _appActionItems[token] ??
          _appActionItems.values.firstWhere(
            (a) => (a['name'] ?? '').toString().toLowerCase().contains(token.toLowerCase()),
            orElse: () => {'pid': token, 'name': token, 'title': token},
          );
      final pid = (app['pid'] ?? token).toString();
      final name = (app['name'] ?? token).toString();
      final title = (app['title'] ?? '').toString();

      await telegram.sendMessage(
        '🖥️ <b>لوحة التحكم في التطبيق:</b>\n'
        '📦 <b>الاسم:</b> <b>$name</b> (PID: <code>$pid</code>)\n'
        '${title.isNotEmpty ? '📑 <b>العنوان:</b> <code>$title</code>\n\n' : '\n'}'
        'اختر الإجراء المطلوب تطبيقه على التطبيق:',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _appActionInlineMenu(name: name, pid: pid, title: title),
      );
      return true;
    }

    if (lower.startsWith('/setwebapp ') || lower.startsWith('/set_webapp ')) {
      final url = text.substring(text.indexOf(' ') + 1).trim();
      if (url.startsWith('https://')) {
        await store.set('telegramWebAppUrl', url);
        final fullUrl = _buildFullWebAppUrl(url, targetChatId: chatId) ?? url;
        unawaited(telegram.setChatMenuButton(webAppUrl: fullUrl, chatId: chatId));
        await telegram.sendMessage(
          '📱 <b>تم تفعيل وتعيين رابط التطبيق المصغر (Mini App) بنجاح!</b>\n\n'
          '🔗 <b>الرابط:</b> <code>$url</code>\n'
          '✅ تم أيضاً ربطه بالمحادثة تلقائياً وضبط زر القائمة (Menu Button) في تيليجرام لفتح التطبيق بضغطة واحدة.',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
          replyMarkup: {
            'inline_keyboard': [
              [
                {'text': '🚀 فتح التطبيق المصغر الآن', 'web_app': {'url': fullUrl}},
              ],
            ],
          },
        );
      } else {
        await telegram.sendMessage(
          '⚠️ <b>تنبيه:</b> يجب أن يبدأ رابط الـ Mini App بـ <code>https://</code> حصراً وفقاً لشروط Telegram Web Apps.\n\n'
          'مثال:\n<code>/setwebapp https://your-domain.github.io/uzak-894651-84561/telegram_mini_app/</code>',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
        );
      }
      return true;
    }

    if (lower == '/webapp' ||
        lower == '/miniapp' ||
        lower == 'webapp' ||
        lower == 'miniapp' ||
        lower == 'تطبيق' ||
        lower == 'التطبيق') {
      final rawUrl = (store.get<String>('telegramWebAppUrl') ?? '').trim();
      final fullUrl = _buildFullWebAppUrl(rawUrl, targetChatId: chatId);
      if (fullUrl != null && fullUrl.isNotEmpty) {
        await telegram.sendMessage(
          '📱 <b>تطبيق لوحة تحكم KIOM المصغر (Telegram Mini App):</b>\n\n'
          'اضغط على الزر أدناه لفتح لوحة التحكم التفاعلية مباشرة داخل تيليجرام 👇',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
          replyMarkup: {
            'inline_keyboard': [
              [
                {'text': '🚀 فتح لوحة التحكم التفاعلية (Mini App)', 'web_app': {'url': fullUrl}},
              ],
            ],
          },
        );
      } else {
        await telegram.sendMessage(
          '📱 <b>ميزة التطبيق المصغر (Telegram Mini App):</b>\n\n'
          'تتيح لك فتح لوحة تحكم رسومية كاملة داخل تيليجرام دون الحاجة لتثبيت تطبيقات خارجية!\n\n'
          '📌 <b>لربط التطبيق المصغر:</b>\n'
          '1. ارفع مجلد <code>telegram_mini_app</code> إلى أي استضافة مجانية تدعم HTTPS مثل (GitHub Pages / Vercel / Cloudflare).\n'
          '2. أرسل الأمر:\n'
          '<code>/setwebapp https://your-url.com</code>\n\n'
          '✨ يمكنك أيضاً ضبطه عبر @BotFather باستخدام الأمر <code>/newapp</code> أو <code>/setmenubutton</code>.',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
        );
      }
      return true;
    }
    if (lower.startsWith('/allow_install') ||
        lower.startsWith('/allowinstall') ||
        lower.startsWith('allow install') ||
        lower.startsWith('allow_install') ||
        lower.startsWith('سماح تثبيت') ||
        lower.startsWith('سماح بالتثبيت') ||
        lower.startsWith('السماح بالتثبيت')) {
      final parts = text.split(RegExp(r'\s+'));
      final mins = parts.length > 1 ? (int.tryParse(parts[1]) ?? 15) : 15;
      final until = DateTime.now().add(Duration(minutes: mins));
      await store.set('installGuardGlobalPassUntil', until.toIso8601String());
      await telegram.sendMessage(
        '🔓 <b>تم فتح نافذة السماح بتثبيت البرامج لمدة $mins دقيقة.</b>\n\n'
        '⏰ سارية المفعول حتى: <b>${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}</b>\n'
        '🛡️ سيتم إعادة قفل وحظر التثبيت تلقائياً بعد انتهاء المدة.',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      return true;
    }

    if (lower == '/block_install' ||
        lower == 'block install' ||
        lower == 'block_install' ||
        lower == 'منع التثبيت' ||
        lower == 'قفل التثبيت' ||
        lower == 'حظر التثبيت') {
      await store.set('installGuardGlobalPassUntil', null);
      await store.set('installGuardMode', 'smart_guard');
      await telegram.sendMessage(
        '🛡️ <b>تم تفعيل حظر وقفل تثبيت البرامج فوراً.</b>\n'
        'سيتم اعتراض وإغلاق أي برنامج تثبيت جديد تلقائياً وإرسال تنبيه للموافقة.',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      return true;
    }

    if (lower.startsWith('/alarm') ||
        lower.startsWith('alarm') ||
        lower.startsWith('/siren') ||
        lower.startsWith('siren') ||
        lower == 'إنذار' ||
        lower == 'انذار' ||
        lower == 'صافرة' ||
        lower.startsWith('صافرة انذار') ||
        lower.startsWith('صافرة إنذار')) {
      final parts = text.split(RegExp(r'\s+'));
      final secs = parts.length > 1 ? (int.tryParse(parts[1]) ?? 8) : 8;
      unawaited(executor.windowsControl.triggerSirenAlarm(seconds: secs));
      await telegram.sendMessage(
        '🚨 <b>تم إطلاق صافرة الإنذار بأقصى صوت على الكمبيوتر!</b>\n'
        '🔊 المدة: $secs ثوانٍ بأقصى درجة صوت.',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      return true;
    }

    if (lower.startsWith('/open ') ||
        lower.startsWith('open ') ||
        lower.startsWith('/browse_url ') ||
        lower.startsWith('browse_url ') ||
        lower.startsWith('افتح ')) {
      final rawUrl = text.substring(text.indexOf(' ') + 1).trim();
      final url = rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
          ? rawUrl
          : 'https://$rawUrl';
      final res = await executor.windowsControl.openBrowserUrl(url);
      await telegram.sendMessage(
        res.success
            ? '🌐 <b>تم فتح الرابط على متصفح الكمبيوتر:</b>\n<code>$url</code>'
            : '⚠️ <b>تعذر فتح الرابط:</b> ${res.message}',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      return true;
    }

    if (lower.startsWith('/press ') ||
        lower.startsWith('press ') ||
        lower.startsWith('/key ') ||
        lower.startsWith('key ')) {
      final key = text.substring(text.indexOf(' ') + 1).trim();
      final res = await executor.windowsControl.simulateKeyPress(key);
      await telegram.sendMessage(
        res.success
            ? '⌨️ <b>تمت محاكاة ضغطة الزر:</b> <code>$key</code>'
            : '⚠️ <b>فشل إرسال الزر:</b> ${res.message}',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      return true;
    }

    if (lower.startsWith('/download ') ||
        lower.startsWith('download ') ||
        lower.startsWith('/dl ') ||
        lower.startsWith('dl ') ||
        lower.startsWith('تحميل ')) {
      final args = text
          .substring(text.indexOf(' ') + 1)
          .trim()
          .split(RegExp(r'\s+'));
      final url = args.first;
      final target = args.length > 1 ? args.sublist(1).join(' ') : null;
      await telegram.sendMessage(
        '⏳ <b>جاري بدء تحميل الملف على الكمبيوتر في الخلفية...</b>\n🔗 الرابط: <code>$url</code>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      final res = await executor.windowsControl
          .downloadRemoteFile(url, targetFolder: target);
      if (res.success && res.payload['SavedPath'] != null) {
        final savedPath = res.payload['SavedPath'].toString();
        final fileName = res.payload['FileName']?.toString() ?? 'ملف محمل';
        final sizeBytes = res.payload['Size'] is num
            ? (res.payload['Size'] as num).toInt()
            : 0;
        final sizeStr = sizeBytes > 0 ? _formatBytes(sizeBytes) : '';

        await telegram.sendMessage(
          '✅ <b>تم تنزيل الملف بنجاح على الكمبيوتر!</b>\n\n'
          '📁 <b>الاسم:</b> <code>$fileName</code>\n'
          '📍 <b>المسار:</b> <code>$savedPath</code>'
          '${sizeStr.isNotEmpty ? '\n📦 <b>الحجم:</b> $sizeStr' : ''}\n\n'
          'اختر الإجراء المطلوب تطبيقه على هذا الملف فوراً:',
          chatId: chatId,
          replyMarkup: {
            'inline_keyboard': [
              [
                {'text': '📂 فتح الملف بالكمبيوتر', 'callback_data': 'exec_open:$savedPath'},
                {'text': '⬇️ إرسال لـ Telegram', 'callback_data': 'get_file:$savedPath'},
              ],
              [
                {'text': '🛡️ حماية وقفل الملف', 'callback_data': 'lock_path:$savedPath'},
                {'text': '☁️ رفع لرابط سحابي', 'callback_data': 'cloud_upload:$savedPath'},
              ],
              [
                {'text': '🗑️ حذف الملف', 'callback_data': 'delete_file:$savedPath'},
                {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
              ],
            ],
          },
        );
      } else {
        await telegram.sendMessage(
          '❌ <b>فشل التحميل:</b> ${res.message}',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
        );
      }
      return true;
    }

    if ((lower.startsWith('http://') || lower.startsWith('https://')) &&
        !lower.contains(' ') &&
        !lower.startsWith('https://t.me/')) {
      final url = text.trim();
      final uri = Uri.tryParse(url);
      final fileName = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'ملف';
      await telegram.sendMessage(
        '🔗 <b>تم استلام رابط ملف:</b>\n<code>$url</code>\n\n'
        'اختر الإجراء المطلوب تنفيذه على الكمبيوتر فوراً:',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: {
          'inline_keyboard': [
            [
              {'text': '📥 تنزيل الملف على الكمبيوتر فوراً', 'callback_data': 'dl_url:$url'},
              {'text': '🌐 فتح الرابط في المتصفح', 'callback_data': 'exec_open:$url'},
            ],
            [
              {'text': '🚫 حظر هذا الموقع', 'callback_data': 'block_site:${uri?.host ?? url}'},
              {'text': '🔙 إلغاء', 'callback_data': 'menu_main'},
            ],
          ],
        },
      );
      return true;
    }

    if (lower == '/cleanup' ||
        lower == 'cleanup' ||
        lower == '/clean_temp' ||
        lower == 'clean temp' ||
        lower == 'تنظيف الجهاز' ||
        lower == 'تنظيف') {
      await telegram.sendMessage(
        '🧹 <b>جاري تنظيف الملفات المؤقتة وسلة المحذوفات...</b>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      final res = await executor.windowsControl.cleanupSystemTempFiles();
      await telegram.sendMessage(
        res.success
            ? '✅ <b>${res.message}</b>'
            : '⚠️ <b>${res.message}</b>',
        chatId: chatId,
        replyMarkup: _dashboardInlineMenu(),
      );
      return true;
    }

    if (lower == '/tasks' ||
        lower == 'tasks' ||
        lower == '/processes' ||
        lower == 'processes' ||
        lower == 'المهام' ||
        lower == 'العمليات') {
      final res = await executor.windowsControl.getRunningProcessesReport();
      final items = (res.payload['items'] as List?) ?? const [];
      final lines = items.take(12).map((item) {
        if (item is! Map) return item.toString();
        final name = item['Name'] ?? 'proc';
        final pid = item['Id'] ?? '';
        final mem = item['MemMB'] ?? 0;
        final title = item['Title'] ?? '';
        return '▫️ <b>$name</b> (PID: <code>$pid</code>) • RAM: ${mem}MB ${title.toString().isNotEmpty ? '\n   └ $title' : ''}';
      }).join('\n');
      final buttons = <List<Map<String, String>>>[];
      for (final item in items.take(4)) {
        if (item is! Map) continue;
        final name = (item['Name'] ?? '').toString();
        final pid = (item['Id'] ?? '').toString();
        if (name.isNotEmpty) {
          buttons.add([
            {'text': '❌ إنهاء $name (PID: $pid)', 'callback_data': 'close_app:$pid'},
            {'text': '🚫 حظر $name', 'callback_data': 'block_app:$name'},
          ]);
        }
      }
      buttons.add([
        {'text': '🔄 تحديث العمليات', 'callback_data': 'tasks'},
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);

      await telegram.sendMessage(
        '📊 <b>العمليات الأكثر استهلاكاً للذاكرة والمعالج:</b>\n\n$lines',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: {'inline_keyboard': buttons},
      );
      return true;
    }

    if (lower == '/webcam' ||
        lower == 'webcam' ||
        lower == '/camera' ||
        lower == 'camera' ||
        lower == 'كاميرا' ||
        lower == 'ويبكام') {
      await telegram.sendMessage(
        '📸 <b>جاري التقاط صورة من كاميرا الويب...</b>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      final res = await executor.windowsControl.captureWebcamPhoto();
      if (res.success && res.payload['filePath'] != null) {
        final path = res.payload['filePath'].toString();
        await telegram.sendPhoto(
          filePath: path,
          chatId: chatId,
          caption:
              '📸 <b>لقطة كاميرا الويب:</b>\n🖥️ $deviceName - ${DateTime.now()}',
          replyToMessageId: replyToMessageId,
        );
      } else {
        await telegram.sendMessage(
          '⚠️ <b>تعذر التقاط صورة الكاميرا:</b> ${res.message}',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
        );
      }
      return true;
    }

    if (lower.startsWith('/mic') ||
        lower.startsWith('mic') ||
        lower.startsWith('/listen') ||
        lower.startsWith('listen') ||
        lower.startsWith('تسجيل') ||
        lower.startsWith('ميكروفون')) {
      final parts = text.split(RegExp(r'\s+'));
      final secs = parts.length > 1 ? (int.tryParse(parts[1]) ?? 8) : 8;
      await telegram.sendMessage(
        '🎙️ <b>جاري تسجيل الصوت من ميكروفون الكمبيوتر لمدة $secs ثوانٍ...</b>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      final res =
          await executor.windowsControl.recordMicrophoneAudio(seconds: secs);
      if (res.success && res.payload['filePath'] != null) {
        final path = res.payload['filePath'].toString();
        await telegram.sendVoice(
          filePath: path,
          chatId: chatId,
          caption: '🎙️ <b>تسجيل ميكروفون الكمبيوتر ($secs ث):</b>\n🖥️ $deviceName',
          replyToMessageId: replyToMessageId,
        );
      } else {
        await telegram.sendMessage(
          '⚠️ <b>تعذر تسجيل الصوت:</b> ${res.message}',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
        );
      }
      return true;
    }

    if (lower.startsWith('/upload_to ') ||
        lower.startsWith('/gdrive_upload ') ||
        lower.startsWith('/onedrive_upload ') ||
        lower.startsWith('/cloud_post ')) {
      final args =
          text.substring(text.indexOf(' ') + 1).trim().split(RegExp(r'\s+'));
      if (args.length < 2) {
        await telegram.sendMessage(
          '⚠️ <b>طريقة الاستخدام:</b>\n<code>/upload_to &lt;مسار_الملف&gt; &lt;رابط_الرفع&gt;</code>\n\nمثال:\n<code>/upload_to C:\\Users\\Admin\\Documents\\report.pdf https://your-onedrive-or-gdrive-upload-url</code>',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
        );
        return true;
      }
      final filePath = args.first;
      final uploadUrl = args.sublist(1).join(' ').trim();
      await telegram.sendMessage(
        '⏳ <b>جاري رفع الملف إلى الرابط السحابي في الخلفية...</b>\n📁 الملف: <code>$filePath</code>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      final res = await executor.windowsControl
          .uploadFileToCloudUrl(filePath, uploadUrl);
      await telegram.sendMessage(
        res.success
            ? '✅ <b>${res.message}</b>'
            : '❌ <b>فشل الرفع:</b> ${res.message}',
        chatId: chatId,
      );
      return true;
    }

    if (lower.startsWith('/sync_onedrive ') ||
        lower.startsWith('/to_onedrive ')) {
      final filePath = text.substring(text.indexOf(' ') + 1).trim();
      final res = await executor.windowsControl
          .copyToCloudSyncFolder(filePath, provider: 'onedrive');
      await telegram.sendMessage(
        res.success
            ? '☁️ <b>${res.message}</b>'
            : '⚠️ <b>تعذر النسخ لـ OneDrive:</b> ${res.message}',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      return true;
    }

    if (lower.startsWith('/sync_gdrive ') ||
        lower.startsWith('/to_gdrive ')) {
      final filePath = text.substring(text.indexOf(' ') + 1).trim();
      final res = await executor.windowsControl
          .copyToCloudSyncFolder(filePath, provider: 'gdrive');
      await telegram.sendMessage(
        res.success
            ? '☁️ <b>${res.message}</b>'
            : '⚠️ <b>تعذر النسخ لـ Google Drive:</b> ${res.message}',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      return true;
    }

    if (lower.startsWith('/cloud_upload ') ||
        lower.startsWith('cloud_upload ') ||
        lower.startsWith('/upload ') ||
        lower.startsWith('upload ') ||
        lower.startsWith('رفع ') ||
        lower.startsWith('رفع_ملف ')) {
      final filePath = text.substring(text.indexOf(' ') + 1).trim();
      await telegram.sendMessage(
        '⏳ <b>جاري رفع الملف للسحابة في الخلفية...</b>\n📁 الملف: <code>$filePath</code>',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
      );
      final res = await executor.windowsControl.uploadToFastCloud(filePath);
      if (res.success && res.payload['DirectUrl'] != null) {
        final directUrl = res.payload['DirectUrl'].toString();
        final fileName = res.payload['FileName']?.toString() ?? 'ملف';
        await telegram.sendMessage(
          '☁️ <b>تم رفع الملف بنجاح!</b>\n\n'
          '📁 <b>الملف:</b> <code>$fileName</code>\n'
          '🔗 <b>رابط التحميل المباشر:</b>\n<code>$directUrl</code>',
          chatId: chatId,
          replyMarkup: {
            'inline_keyboard': [
              [
                {'text': '🌐 فتح الرابط بالمتصفح', 'callback_data': 'exec_open:$directUrl'},
                {'text': '📋 نسخ الرابط للحافظة', 'callback_data': 'copy_clip:$directUrl'},
              ],
              [
                {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
              ],
            ],
          },
        );
      } else {
        await telegram.sendMessage(
          res.success
              ? '☁️ <b>${res.message}</b>'
              : '❌ <b>فشل الرفع:</b> ${res.message}',
          chatId: chatId,
        );
      }
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
        lower == 'open_apps' ||
        lower == 'openapps' ||
        lower == 'البرامج' ||
        lower == 'البرامج المفتوحة' ||
        lower == 'التطبيقات المفتوحة') {
      return const _ParsedTelegramCommand('list_open_apps');
    }
    if (lower == 'installed' ||
        lower == 'installed_apps' ||
        lower == 'installed apps' ||
        lower == 'installedapps' ||
        lower == 'programs' ||
        lower == 'البرامج المثبتة' ||
        lower == 'التطبيقات المثبتة') {
      return const _ParsedTelegramCommand('list_installed_apps');
    }
    if (lower == 'blocked' ||
        lower == 'blocked_items' ||
        lower == 'blocked items' ||
        lower == 'blockeditems' ||
        lower == 'الممنوعات' ||
        lower == 'قائمة المنع') {
      return const _ParsedTelegramCommand('list_blocked_items');
    }
    if (lower == 'rules' ||
        lower == 'path_rules' ||
        lower == 'path rules' ||
        lower == 'pathrules' ||
        lower == 'قواعد الحماية' ||
        lower == 'حماية المسارات') {
      return const _ParsedTelegramCommand('list_path_rules');
    }
    if (lower == 'insights' ||
        lower == 'smart_insights' ||
        lower == 'smart insights' ||
        lower == 'smartinsights' ||
        lower == 'التحليلات' ||
        lower == 'ملخص' ||
        lower == 'تقرير') {
      return const _ParsedTelegramCommand('smart_insights');
    }

    if (lower == 'open_items' ||
        lower == 'open items' ||
        lower == 'open_files' ||
        lower == 'open files' ||
        lower == 'open_sites' ||
        lower == 'open sites' ||
        lower == 'open_tabs' ||
        lower == 'open tabs' ||
        lower == 'tabs' ||
        lower == 'المواقع المفتوحة' ||
        lower == 'الملفات المفتوحة' ||
        lower == 'التبويبات المفتوحة' ||
        lower == 'المستندات المفتوحة') {
      return const _ParsedTelegramCommand('list_open_items');
    }

    if (lower == 'cleanup' ||
        lower == 'clean_temp' ||
        lower == 'clean' ||
        lower == 'تنظيف' ||
        lower == 'تنظيف الجهاز') {
      return const _ParsedTelegramCommand('cleanup_temp');
    }

    if (lower == 'tasks' ||
        lower == 'processes' ||
        lower == 'procs' ||
        lower == 'المهام' ||
        lower == 'العمليات') {
      return const _ParsedTelegramCommand('list_processes');
    }

    if (lower == 'qr' || lower == 'رمز الربط' || lower == 'كود الربط') {
      return const _ParsedTelegramCommand('show_pairing_qr');
    }
    if (lower == 'permissions' || lower == 'الاذونات' || lower == 'الصلاحيات') {
      return const _ParsedTelegramCommand('show_permission_center');
    }
    if (lower == 'logs' || lower == 'السجلات' || lower == 'سجل النشاط') {
      return const _ParsedTelegramCommand('request_logs');
    }

    // Direct callback shortcuts for modes, privacy, browse, messages
    if (lower == 'mode_study') return const _ParsedTelegramCommand('apply_preset_mode', {'mode': 'study'});
    if (lower == 'mode_work') return const _ParsedTelegramCommand('apply_preset_mode', {'mode': 'work'});
    if (lower == 'mode_kids') return const _ParsedTelegramCommand('apply_preset_mode', {'mode': 'kids'});
    if (lower == 'mode_protection') return const _ParsedTelegramCommand('apply_preset_mode', {'mode': 'protection'});

    if (lower == 'privacy_on') return const _ParsedTelegramCommand('privacy_mode', {'enabled': true});
    if (lower == 'privacy_off') return const _ParsedTelegramCommand('privacy_mode', {'enabled': false});

    if (lower == 'browse_downloads') return _ParsedTelegramCommand('browse_path', {'path': _getKnownFolder('Downloads')});
    if (lower == 'browse_desktop') return _ParsedTelegramCommand('browse_path', {'path': _getKnownFolder('Desktop')});
    if (lower == 'browse_documents') return _ParsedTelegramCommand('browse_path', {'path': _getKnownFolder('Documents')});
    if (lower == 'browse_c') return const _ParsedTelegramCommand('browse_path', {'path': r'C:\'});
    if (lower == 'browse_d') return const _ParsedTelegramCommand('browse_path', {'path': r'D:\'});
    if (lower == 'browse_roots') return const _ParsedTelegramCommand('browse_path', {'path': 'roots'});

    if (lower == 'msg_break') {
      return const _ParsedTelegramCommand('show_message', {
        'title': 'تنبيه النظام',
        'message': 'حان وقت الاستراحة، يرجى الابتعاد عن الشاشة.',
      });
    }
    if (lower == 'msg_save') {
      return const _ParsedTelegramCommand('show_message', {
        'title': 'تنبيه النظام',
        'message': 'تنبيه: يرجى حفظ جميع أعمالك وإغلاق البرامج.',
      });
    }
    if (lower == 'msg_urgent') {
      return const _ParsedTelegramCommand('show_message', {
        'title': 'تنبيه عاجل',
        'message': 'تنبيه عاجل: مطلوب التحدث مع مسؤول النظام.',
      });
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
    if (lower == 'specs' || lower == 'sysinfo' || lower == 'مواصفات' || lower == 'معلومات الجهاز') {
      return const _ParsedTelegramCommand('system_specs');
    }
    if (lower == 'clip' || lower == 'clipboard' || lower == 'الحافظة') {
      return const _ParsedTelegramCommand('get_clipboard');
    }
    if (lower.startsWith('copy ') || lower.startsWith('نسخ ') || lower.startsWith('انسخ ')) {
      final textToCopy = lower.startsWith('copy ')
          ? normalized.substring(5).trim()
          : (lower.startsWith('نسخ ') ? normalized.substring(4).trim() : normalized.substring(5).trim());
      return _ParsedTelegramCommand('set_clipboard', {'text': textToCopy});
    }
    if (first == 'say' || first == 'speak' || first == 'تحدث' || first == 'انطق' || first == 'قل') {
      return _ParsedTelegramCommand('text_to_speech', {'text': rest});
    }
    if (first == 'ps' || first == 'powershell') {
      return _ParsedTelegramCommand('powershell_exec', {'script': rest});
    }
    if (first == 'cmd') {
      return _ParsedTelegramCommand('cmd_exec', {'command': rest});
    }
    if (lower.startsWith('toast ') || lower.startsWith('alert ') || lower.startsWith('تنبيه ')) {
      final msg = lower.startsWith('toast ')
          ? normalized.substring(6).trim()
          : (lower.startsWith('alert ') ? normalized.substring(6).trim() : normalized.substring(6).trim());
      return _ParsedTelegramCommand('windows_toast', {'title': 'KIOM Remote Alert', 'message': msg});
    }
    if (lower == 'allow all' ||
        lower == 'allow_all' ||
        lower == 'allow_all_permissions' ||
        lower == 'grant all' ||
        lower == 'grant_all' ||
        lower == 'تفعيل كل الاذونات' ||
        lower == 'تفعيل الاذونات' ||
        lower == 'تفعيل الصلاحيات' ||
        lower == 'تفعيل كل الصلاحيات' ||
        lower == 'تفعيل الكل' ||
        lower == 'سماح للكل') {
      return const _ParsedTelegramCommand('allow_all_permissions');
    }
    if (lower.startsWith('mode ') || lower.startsWith('وضع ')) {
      final mode = lower.startsWith('mode ')
          ? normalized.substring('mode '.length).trim()
          : normalized.substring('وضع '.length).trim();
      return _ParsedTelegramCommand('apply_preset_mode', {'mode': mode});
    }

    // Lock & Power Commands
    if (lower.startsWith('lock_')) {
      final minutes = int.tryParse(lower.substring('lock_'.length));
      if (minutes != null) {
        return _ParsedTelegramCommand('lock_for_duration', {'minutes': minutes});
      }
    }
    if (lower.startsWith('shutdown_')) {
      final minutes = int.tryParse(lower.substring('shutdown_'.length));
      if (minutes != null) {
        return _ParsedTelegramCommand('shutdown_pc', {'delaySeconds': minutes * 60});
      }
    }
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
    if (lower.startsWith('vol_')) {
      final vol = int.tryParse(lower.substring('vol_'.length));
      if (vol != null) {
        return _ParsedTelegramCommand('set_volume', {'volume': vol});
      }
    }
    if (first == 'volume' || first == 'vol' || first == 'صوت') {
      final volume = int.tryParse(rest);
      if (volume != null) {
        return _ParsedTelegramCommand('set_volume', {'volume': volume});
      }
    }
    if (lower == 'volup' || lower == 'vol_up' || lower == 'vol+' || lower == 'volume up' || lower == 'رفع الصوت' || lower == 'علي الصوت') {
      return const _ParsedTelegramCommand('volume_up');
    }
    if (lower == 'voldown' || lower == 'vol_down' || lower == 'vol-' || lower == 'volume down' || lower == 'خفض الصوت' || lower == 'وطي الصوت') {
      return const _ParsedTelegramCommand('volume_down');
    }
    if (lower == 'mute' || lower == 'vol_mute' || lower == 'كتم' || lower == 'كتم الصوت') {
      return const _ParsedTelegramCommand('mute_volume');
    }
    if (lower == 'unmute' || lower == 'vol_unmute' || lower == 'الغاء كتم' || lower == 'إلغاء الكتم') {
      return const _ParsedTelegramCommand('unmute_volume');
    }

    // WiFi & Internet Commands
    if (lower == 'wifi_on' ||
        (first == 'wifi' && rest.toLowerCase() == 'on') ||
        lower == 'تشغيل الواي فاي' ||
        lower == 'واي فاي تشغيل') {
      return const _ParsedTelegramCommand('wifi_on');
    }
    if (lower == 'wifi_off' ||
        (first == 'wifi' && rest.toLowerCase() == 'off') ||
        lower == 'ايقاف الواي فاي' ||
        lower == 'إيقاف الواي فاي' ||
        lower == 'واي فاي ايقاف') {
      return const _ParsedTelegramCommand('wifi_off');
    }
    if (lower == 'net_off' ||
        lower == 'internet off' ||
        lower == 'net off' ||
        lower == 'internet_off' ||
        lower == 'ايقاف الانترنت نهائيا' ||
        lower == 'إيقاف الانترنت نهائياً' ||
        lower == 'قطع الانترنت') {
      return const _ParsedTelegramCommand('internet_off_permanent');
    }
    if (lower == 'net_on' ||
        lower == 'internet on' ||
        lower == 'net on' ||
        lower == 'internet_on' ||
        lower == 'تشغيل الانترنت' ||
        lower == 'تشغيل الإنترنت' ||
        lower == 'اعادة الانترنت') {
      return const _ParsedTelegramCommand('internet_on');
    }

    // Bluetooth Commands
    if (lower == 'bt_on' ||
        lower == 'bluetooth_on' ||
        ((first == 'bluetooth' || first == 'bt') && rest.toLowerCase() == 'on')) {
      return const _ParsedTelegramCommand('bluetooth_on');
    }
    if (lower == 'bt_off' ||
        lower == 'bluetooth_off' ||
        ((first == 'bluetooth' || first == 'bt') && rest.toLowerCase() == 'off')) {
      return const _ParsedTelegramCommand('bluetooth_off');
    }
    if (lower == 'bt_devices' ||
        lower == 'bluetooth_devices' ||
        ((first == 'bluetooth' || first == 'bt') &&
            (rest.toLowerCase() == 'devices' || rest.toLowerCase() == 'list'))) {
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
    if (first == 'close' ||
        first == 'kill' ||
        first == 'closeapp' ||
        first == 'killapp' ||
        first == 'close_app' ||
        first == 'kill_app' ||
        first == 'اغلق' ||
        first == 'أغلق' ||
        first == 'انهاء' ||
        first == 'إنهاء' ||
        first == 'إغلاق_تطبيق' ||
        first == 'اغلاق_تطبيق') {
      final target = _cleanTargetString(rest);
      return _ParsedTelegramCommand('close_application', {'target': target});
    }

    // Explicit Website Block
    const blockSitePrefixes = [
      'blocksite ',
      'block_site ',
      'block site ',
      'blockwebsite ',
      'block_website ',
      'block website ',
      'حظر موقع ',
      'حظر_موقع ',
      'منع موقع ',
      'منع_موقع ',
      'قفل موقع ',
    ];
    for (final prefix in blockSitePrefixes) {
      if (lower.startsWith(prefix)) {
        final rawTarget = normalized.substring(prefix.length).trim();
        final domain = _cleanTargetString(rawTarget);
        return _ParsedTelegramCommand('block_website', {'domain': domain});
      }
    }

    // Explicit Website Allow / Unblock
    const allowSitePrefixes = [
      'allowsite ',
      'allow_site ',
      'allow site ',
      'unblocksite ',
      'unblock_site ',
      'unblock site ',
      'allowwebsite ',
      'allow_website ',
      'allow website ',
      'unblockwebsite ',
      'unblock_website ',
      'سماح لموقع ',
      'سماح موقع ',
      'سماح_موقع ',
      'فك حظر موقع ',
      'رفع حظر موقع ',
      'الغاء حظر موقع ',
      'إلغاء حظر موقع ',
    ];
    for (final prefix in allowSitePrefixes) {
      if (lower.startsWith(prefix)) {
        final rawTarget = normalized.substring(prefix.length).trim();
        final domain = _cleanTargetString(rawTarget);
        return _ParsedTelegramCommand('allow_website', {'domain': domain});
      }
    }

    // Explicit App Block
    const blockAppPrefixes = [
      'blockapp ',
      'block_app ',
      'block app ',
      'blockapplication ',
      'block_application ',
      'block application ',
      'منع تطبيق ',
      'منع_تطبيق ',
      'حظر تطبيق ',
      'حظر_تطبيق ',
      'قفل تطبيق ',
    ];
    for (final prefix in blockAppPrefixes) {
      if (lower.startsWith(prefix)) {
        final rawTarget = normalized.substring(prefix.length).trim();
        final app = _cleanTargetString(rawTarget);
        return _ParsedTelegramCommand('block_application', {'target': app});
      }
    }

    // Explicit App Allow / Unblock
    const allowAppPrefixes = [
      'allowapp ',
      'allow_app ',
      'allow app ',
      'unblockapp ',
      'unblock_app ',
      'unblock app ',
      'allowapplication ',
      'allow_application ',
      'allow application ',
      'unblockapplication ',
      'unblock_application ',
      'سماح لتطبيق ',
      'سماح تطبيق ',
      'سماح_تطبيق ',
      'فك حظر تطبيق ',
      'رفع منع تطبيق ',
      'الغاء منع تطبيق ',
      'إلغاء منع تطبيق ',
    ];
    for (final prefix in allowAppPrefixes) {
      if (lower.startsWith(prefix)) {
        final rawTarget = normalized.substring(prefix.length).trim();
        final app = _cleanTargetString(rawTarget);
        return _ParsedTelegramCommand('allow_application', {'target': app});
      }
    }

    // Heuristic "block <target>" / "حظر <target>" / "منع <target>"
    if (lower.startsWith('block ') || lower.startsWith('حظر ') || lower.startsWith('منع ')) {
      final prefix = lower.startsWith('block ')
          ? 'block '
          : (lower.startsWith('حظر ') ? 'حظر ' : 'منع ');
      final rawTarget = normalized.substring(prefix.length).trim();
      final cleaned = _cleanTargetString(rawTarget);
      if (cleaned.contains('.') && !cleaned.toLowerCase().endsWith('.exe')) {
        return _ParsedTelegramCommand('block_website', {'domain': cleaned});
      } else {
        return _ParsedTelegramCommand('block_application', {'target': cleaned});
      }
    }

    // Heuristic "unblock <target>" / "allow <target>" / "سماح <target>"
    if (lower.startsWith('unblock ') ||
        lower.startsWith('allow ') ||
        lower.startsWith('فك حظر ') ||
        lower.startsWith('رفع حظر ') ||
        lower.startsWith('سماح ')) {
      final prefix = [
        'unblock ',
        'allow ',
        'فك حظر ',
        'رفع حظر ',
        'سماح ',
      ].firstWhere((p) => lower.startsWith(p));
      final rawTarget = normalized.substring(prefix.length).trim();
      final cleaned = _cleanTargetString(rawTarget);
      if (cleaned.contains('.') && !cleaned.toLowerCase().endsWith('.exe')) {
        return _ParsedTelegramCommand('allow_website', {'domain': cleaned});
      } else {
        return _ParsedTelegramCommand('allow_application', {'target': cleaned});
      }
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
    const protectPrefixes = [
      'protect ',
      'lock_path ',
      'lockpath ',
      'lock_file ',
      'lockfile ',
      'lock_folder ',
      'lockfolder ',
      'lock ',
      'قفل ملف ',
      'قفل_ملف ',
      'قفل مجلد ',
      'قفل_مجلد ',
      'قفل مسار ',
      'قفل_مسار ',
      'حماية مسار ',
      'حماية مجلد ',
      'حماية ملف ',
      'حماية ',
      'قفل ',
    ];
    for (final prefix in protectPrefixes) {
      if (lower.startsWith(prefix)) {
        final path = normalized.substring(prefix.length).trim();
        return _ParsedTelegramCommand('protect_path', {'path': path});
      }
    }

    const unprotectPrefixes = [
      'unprotect ',
      'unlock_path ',
      'unlockpath ',
      'unlock_file ',
      'unlockfile ',
      'unlock_folder ',
      'unlockfolder ',
      'unlock ',
      'فك قفل ملف ',
      'فك قفل مجلد ',
      'فك قفل مسار ',
      'فك قفل ',
      'فك_قفل ',
      'الغاء حماية ملف ',
      'إلغاء حماية ملف ',
      'الغاء حماية مجلد ',
      'إلغاء حماية مجلد ',
      'الغاء حماية مسار ',
      'إلغاء حماية مسار ',
      'الغاء حماية ',
      'إلغاء حماية ',
      'سماح مسار ',
      'سماح ملف ',
      'سماح مجلد ',
    ];
    for (final prefix in unprotectPrefixes) {
      if (lower.startsWith(prefix)) {
        final path = normalized.substring(prefix.length).trim();
        return _ParsedTelegramCommand('unprotect_path', {'path': path});
      }
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

  String _cleanTargetString(String input) {
    var text = input.trim();
    // Strip markdown links e.g. [youtube.com](http://youtube.com)
    final mdMatch = RegExp(r'\[([^\]]+)\]\([^)]+\)').firstMatch(text);
    if (mdMatch != null) {
      text = mdMatch.group(1) ?? text;
    }
    // Strip surrounding brackets, quotes, backticks
    text = text.replaceAll(RegExp(r'''^[\[\(\"\'`<]+|[\]\)\"\'>`]+$'''), '').trim();
    // If it's a full URL, extract hostname
    if (text.startsWith('http://') || text.startsWith('https://')) {
      final uri = Uri.tryParse(text);
      if (uri != null && uri.host.isNotEmpty) {
        text = uri.host;
      }
    }
    return text.replaceAll(RegExp(r'^www\.'), '').trim();
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

    // Activity Logs
    if (type == 'request_logs' || type == 'logs') {
      final logs = (payload['logs'] as List?) ?? const [];
      if (logs.isEmpty) return '📜 لا توجد سجلات مطابقة للشروط أو الفترة المحددة.';
      _logActionItems.clear();
      final buffer = StringBuffer();
      buffer.writeln('📜 <b>سجل الأنشطة والعمليات (${logs.length}):</b>\n');

      var i = 1;
      for (final log in logs.take(20)) {
        if (log is! Map) continue;
        final action = (log['type'] ?? log['action'] ?? 'log').toString();
        final msg = (log['message'] ?? log['text'] ?? '').toString();
        final timeStr = (log['createdAt'] ?? log['created_at'] ?? log['timestamp'] ?? '').toString();
        final extra = (log['extra'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

        var shortTime = '';
        if (timeStr.isNotEmpty) {
          final dt = DateTime.tryParse(timeStr);
          if (dt != null) {
            shortTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
          }
        }

        // Determine item type
        String itemType = 'log';
        String path = (extra['path'] ?? extra['appPath'] ?? '').toString();
        String target = (extra['target'] ?? extra['domain'] ?? extra['appName'] ?? '').toString();
        String title = (extra['title'] ?? '').toString();

        if (action.contains('path') || action.contains('file') || path.isNotEmpty) {
          itemType = 'file';
          if (path.isEmpty && msg.contains(r':\')) {
            final match = RegExp(r'[A-Za-z]:\\[^\s\r\n]+').firstMatch(msg);
            if (match != null) path = match.group(0)!;
          }
        } else if (action.contains('app') || target.endsWith('.exe')) {
          itemType = 'app';
        } else if (action.contains('site') || target.contains('.')) {
          itemType = 'site';
        }

        _logActionItems[i] = {
          'index': i,
          'type': itemType,
          'action': action,
          'path': path,
          'target': target,
          'title': title,
          'msg': msg,
          'time': shortTime,
          'extra': extra,
        };

        final icon = switch (itemType) {
          'file' => '📁',
          'app' => '🖥️',
          'site' => '🌐',
          _ => '▫️',
        };

        buffer.writeln('$i️⃣ $icon <b>$action</b>: $msg');
        if (path.isNotEmpty) {
          buffer.writeln('   📍 <code>$path</code>');
        } else if (target.isNotEmpty) {
          buffer.writeln('   🎯 <code>$target</code>');
        }
        if (shortTime.isNotEmpty) {
          buffer.writeln('   ⏱️ $shortTime');
        }
        buffer.writeln('   👉 /act_${itemType}_$i\n');
        i++;
      }

      buffer.writeln('💡 <i>اضغط على أي أمر /act أعلاه لعرض خيارات التحكم الكاملة (فتح، قفل، إرسال، حذف، حظر).</i>');
      return buffer.toString().trim();
    }

    // File lists
    if (type == 'browse_path' || type == 'search_files') {
      final items = (payload['items'] as List?) ?? const [];
      if (items.isEmpty) return '📂 المسار فارغ أو لا توجد نتائج مطابقة.';
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
      if (apps.isEmpty) return 'ℹ️ لا توجد تطبيقات مفتوحة بنوافذ نشطة حالياً.';
      _appActionItems.clear();
      final buffer = StringBuffer();
      buffer.writeln('🖥️ <b>التطبيقات والنوافذ المفتوحة حالياً (${apps.length}):</b>\n');

      var i = 1;
      for (final app in apps.take(20)) {
        if (app is! Map) continue;
        final name = (app['appName'] ?? app['name'] ?? app['processName'] ?? 'App').toString();
        final pid = (app['processId'] ?? app['pid'] ?? '').toString();
        final title = (app['windowTitle'] ?? app['title'] ?? '').toString();
        final site = (app['siteName'] ?? '').toString();
        final page = (app['pageTitle'] ?? '').toString();
        final sub = site.isNotEmpty ? '🌐 $site' : (page.isNotEmpty ? '📄 $page' : title);

        _appActionItems[pid] = {
          'name': name,
          'pid': pid,
          'title': title.isNotEmpty ? title : sub,
          'app': app,
        };
        _appActionItems[name.toLowerCase()] = _appActionItems[pid]!;

        buffer.writeln('$i️⃣ <b>$name</b> (PID: <code>$pid</code>)');
        if (sub.isNotEmpty) {
          buffer.writeln('   └ $sub');
        }
        buffer.writeln('   👉 /app_$pid\n');
        i++;
      }

      buffer.writeln('💡 <i>اضغط على أي أمر /app أعلاه للتحكم المباشر بالتطبيق (إغلاق فوري، قفل، حظر، إغلاق بعد مدة).</i>');
      return buffer.toString().trim();
    }

    // Installed apps
    if (type == 'list_installed_apps' || type == 'installed_apps') {
      final apps = (payload['apps'] as List?) ?? const [];
      if (apps.isEmpty) return '📦 لم يتم العثور على برامج مثبتة مسجلة.';
      final lines = apps.take(20).map((app) {
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

    // Comprehensive Open Items (Files, Tabs, Documents, Apps)
    if (type == 'list_open_items' ||
        type == 'open_items' ||
        type == 'list_open_files' ||
        type == 'open_files' ||
        type == 'list_open_sites' ||
        type == 'open_sites') {
      final tabs = (payload['browserTabs'] as List?) ?? const [];
      final docs = (payload['documents'] as List?) ?? const [];
      final folders = (payload['folders'] as List?) ?? const [];
      final apps = (payload['apps'] as List?) ?? const [];

      final buffer = StringBuffer();
      buffer.writeln('📋 <b>تقرير تفصيلي بكافة الملفات والمواقع المفتوحة:</b>\n');

      if (tabs.isNotEmpty) {
        buffer.writeln('🌐 <b>المواقع والتبويبات النشطة (${tabs.length}):</b>');
        for (final tab in tabs.take(8)) {
          final title = (tab['Title'] ?? '').toString();
          final browser = (tab['Browser'] ?? '').toString();
          final pid = (tab['Id'] ?? '').toString();
          buffer.writeln('  ▫️ <b>$browser:</b> $title');
          if (pid.isNotEmpty) {
            buffer.writeln('     👉 /app_$pid');
          }
        }
        buffer.writeln('');
      }

      if (docs.isNotEmpty) {
        buffer.writeln('📄 <b>المستندات والملفات المفتوحة (${docs.length}):</b>');
        for (final doc in docs.take(8)) {
          final title = (doc['Title'] ?? '').toString();
          final path = (doc['Path'] ?? '').toString();
          final pid = (doc['Id'] ?? '').toString();
          buffer.writeln('  ▫️ <b>$title</b>${path.isNotEmpty ? '\n     <code>$path</code>' : ''}');
          if (pid.isNotEmpty) {
            buffer.writeln('     👉 /app_$pid');
          }
        }
        buffer.writeln('');
      }

      if (folders.isNotEmpty) {
        buffer.writeln('📁 <b>مجلدات Explorer المفتوحة (${folders.length}):</b>');
        for (final f in folders.take(6)) {
          final name = (f['Name'] ?? '').toString();
          final path = (f['Path'] ?? '').toString();
          buffer.writeln('  ▫️ 📁 <b>$name</b>\n     <code>$path</code>');
          if (path.isNotEmpty) {
            buffer.writeln('     👉 /lock $path');
          }
        }
        buffer.writeln('');
      }

      if (apps.isNotEmpty) {
        buffer.writeln('🖥️ <b>التطبيقات والنوافذ الأخرى (${apps.length}):</b>');
        for (final a in apps.take(6)) {
          final name = (a['ProcessName'] ?? '').toString();
          final title = (a['Title'] ?? '').toString();
          final pid = (a['Id'] ?? '').toString();
          buffer.writeln('  ▫️ <b>$name:</b> $title');
          if (pid.isNotEmpty) {
            buffer.writeln('     👉 /app_$pid');
          }
        }
      }

      return buffer.toString().trim();
    }
        for (final a in apps.take(6)) {
          final name = (a['ProcessName'] ?? '').toString();
          final title = (a['Title'] ?? '').toString();
          buffer.writeln('  ▫️ <b>$name:</b> $title');
        }
      }

      return buffer.toString().trim();
    }

    // Process List
    if (type == 'list_processes' || type == 'top_processes') {
      final items = (payload['items'] as List?) ?? const [];
      final lines = items.take(15).map((item) {
        if (item is! Map) return item.toString();
        final name = item['Name'] ?? 'proc';
        final pid = item['Id'] ?? '';
        final mem = item['MemMB'] ?? 0;
        final title = item['Title'] ?? '';
        return '▫️ <b>$name</b> (PID: <code>$pid</code>) • RAM: ${mem}MB ${title.toString().isNotEmpty ? '\n   └ $title' : ''}';
      }).join('\n');
      return '📊 <b>العمليات الأكثر استهلاكاً للذاكرة:</b>\n\n$lines';
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
    if (type == 'list_open_items' ||
        type == 'open_items' ||
        type == 'list_open_files' ||
        type == 'open_files' ||
        type == 'list_open_sites' ||
        type == 'open_sites') {
      final buttons = <List<Map<String, String>>>[];
      final tabs = (payload['browserTabs'] as List?) ?? const [];
      final docs = (payload['documents'] as List?) ?? const [];
      final folders = (payload['folders'] as List?) ?? const [];

      for (final tab in tabs.take(3)) {
        if (tab is! Map) continue;
        final title = (tab['Title'] ?? '').toString();
        final domain = _cleanTargetString(title);
        if (domain.isNotEmpty) {
          buttons.add([
            {'text': '🚫 حظر موقع: $domain', 'callback_data': 'block_site:$domain'},
          ]);
        }
      }

      for (final doc in docs.take(2)) {
        if (doc is! Map) continue;
        final title = (doc['Title'] ?? '').toString();
        final path = (doc['Path'] ?? '').toString();
        if (path.isNotEmpty) {
          buttons.add([
            {'text': '⬇️ تحميل ($title)', 'callback_data': 'get_file:$path'},
            {'text': '🛡️ قفل المسار', 'callback_data': 'lock_path:$path'},
          ]);
        }
      }

      for (final f in folders.take(2)) {
        if (f is! Map) continue;
        final name = (f['Name'] ?? '').toString();
        final path = (f['Path'] ?? '').toString();
        if (path.isNotEmpty) {
          buttons.add([
            {'text': '📁 تصفح: $name', 'callback_data': 'browse_folder:$path'},
            {'text': '🛡️ قفل المجلد', 'callback_data': 'lock_path:$path'},
          ]);
        }
      }

      buttons.add([
        {'text': '🔄 تحديث القائمة الشاملة', 'callback_data': 'open_items'},
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);
      return {'inline_keyboard': buttons};
    }
    if (type == 'browse_path' || type == 'search_files') {
      final items = (payload['items'] as List?) ?? const [];
      final fileButtons = <List<Map<String, String>>>[];
      for (final item in items.take(4)) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final path = (item['path'] ?? '').toString();
        final isDir = item['type'] == 'directory' || item['type'] == 'drive';
        if (path.isEmpty) continue;
        if (isDir) {
          fileButtons.add([
            {
              'text': '📁 تصفح: ${name.length > 16 ? '${name.substring(0, 16)}...' : name}',
              'callback_data': 'browse_folder:$path',
            },
            {
              'text': '🛡️ قفل المسار',
              'callback_data': 'lock_path:$path',
            },
          ]);
        } else {
          fileButtons.add([
            {
              'text': '⬇️ تحميل (${name.length > 14 ? '${name.substring(0, 14)}...' : name})',
              'callback_data': 'get_file:$path',
            },
            {
              'text': '📂 فتح',
              'callback_data': 'exec_open:$path',
            },
            {
              'text': '🗑️ حذف',
              'callback_data': 'delete_file:$path',
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
      for (final app in apps.take(5)) {
        if (app is! Map) continue;
        final name = (app['appName'] ?? app['name'] ?? '').toString();
        final pid = (app['processId'] ?? app['pid'] ?? '').toString();
        final site = (app['siteName'] ?? '').toString();
        if (name.isEmpty) continue;
        final row = <Map<String, String>>[
          {
            'text': '❌ إغلاق: $name',
            'callback_data': 'close_app:${pid.isNotEmpty ? pid : name}',
          },
          {
            'text': '🚫 حظر: $name',
            'callback_data': 'block_app:$name',
          },
        ];
        if (site.isNotEmpty) {
          row.add({
            'text': '🌐 حظر موقع $site',
            'callback_data': 'block_site:$site',
          });
        }
        buttons.add(row);
      }
      buttons.add([
        {'text': '🔄 تحديث القائمة', 'callback_data': 'open_apps'},
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);
      return {'inline_keyboard': buttons};
    }

    if (type == 'list_installed_apps' || type == 'installed_apps') {
      final apps = (payload['apps'] as List?) ?? const [];
      final buttons = <List<Map<String, String>>>[];
      for (final app in apps.take(6)) {
        if (app is! Map) continue;
        final name = (app['name'] ?? app['displayName'] ?? '').toString();
        if (name.isEmpty) continue;
        buttons.add([
          {
            'text': '🚫 حظر التطبيق: $name',
            'callback_data': 'block_app:$name',
          },
        ]);
      }
      buttons.add([
        {'text': '🔄 تحديث', 'callback_data': 'installed_apps'},
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);
      return {'inline_keyboard': buttons};
    }

    if (type == 'list_blocked_items' || type == 'blocked_items') {
      final items = (payload['items'] as List?) ?? const [];
      final buttons = <List<Map<String, String>>>[];
      for (final item in items.take(6)) {
        if (item is! Map) continue;
        final target = (item['target'] ?? item['domain'] ?? '').toString();
        if (target.isEmpty) continue;
        buttons.add([
          {
            'text': '🔓 فك حظر: $target',
            'callback_data': 'allow_item:$target',
          },
        ]);
      }
      buttons.add([
        {'text': '🔄 تحديث', 'callback_data': 'blocked_items'},
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);
      return {'inline_keyboard': buttons};
    }

    if (type == 'list_path_rules' || type == 'path_rules') {
      final rules = (payload['rules'] as List?) ?? const [];
      final buttons = <List<Map<String, String>>>[];
      for (final rule in rules.take(6)) {
        if (rule is! Map) continue;
        final path = (rule['path'] ?? '').toString();
        if (path.isEmpty) continue;
        final fileName = path.replaceAll('/', r'\').split(r'\').last;
        buttons.add([
          {
            'text': '🔓 إلغاء قفل: $fileName',
            'callback_data': 'unprotect_path:$path',
          },
        ]);
      }
      buttons.add([
        {'text': '🔄 تحديث', 'callback_data': 'path_rules'},
        {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
      ]);
      return {'inline_keyboard': buttons};
    }

    if (type == 'request_logs' || type == 'logs') {
      return {
        'inline_keyboard': [
          [
            {'text': '📁 ملفات ومسارات', 'callback_data': 'log_filter:type:files'},
            {'text': '🖥️ برامج وتطبيقات', 'callback_data': 'log_filter:type:apps'},
          ],
          [
            {'text': '🚫 عمليات ممنوعة', 'callback_data': 'log_filter:type:blocked'},
            {'text': '⚡ أوامر منفذة', 'callback_data': 'log_filter:type:commands'},
          ],
          [
            {'text': '📅 اليوم', 'callback_data': 'log_filter:range:today'},
            {'text': '📆 أمس', 'callback_data': 'log_filter:range:yesterday'},
            {'text': '🕐 آخر ساعة', 'callback_data': 'log_filter:range:1h'},
          ],
          [
            {'text': '🔄 تحديث وتصفية السجل', 'callback_data': 'logs'},
            {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
          ],
        ],
      };
    }
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
      case 'specs':
        return 'specs';
      case 'clip':
        return 'clip';
      case 'webcam':
        return '/webcam';
      case 'mic':
        return '/mic 10';
      case 'alarm':
        return '/alarm 10';
      case 'allow_install_15':
        return '/allow_install 15';
      case 'block_install':
        return '/block_install';
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
      case 'allow_all_permissions':
        return 'allow_all_permissions';
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
      case 'open_items':
        return 'open_items';
      case 'cleanup':
        return 'cleanup';
      case 'tasks':
        return 'tasks';
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

  String? _buildFullWebAppUrl(String? rawUrl, {String? targetChatId}) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final clean = rawUrl.trim();
    try {
      final uri = Uri.parse(clean);
      final cId = (targetChatId != null && targetChatId.isNotEmpty)
          ? targetChatId
          : telegram.effectiveChatId;
      return uri.replace(queryParameters: {
        ...uri.queryParameters,
        if (cId.isNotEmpty) 'chat_id': cId,
        'device_id': deviceId,
        'device_name': deviceName,
        if (telegram.hasBotToken) 'bot_token': telegram.botToken,
      }).toString();
    } catch (_) {
      return clean;
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

    final rawWebAppUrl = (store.get<String>('telegramWebAppUrl') ?? '').trim();
    final fullWebAppUrl = _buildFullWebAppUrl(rawWebAppUrl);
    final List<List<Map<String, dynamic>>> rows = [];

    if (fullWebAppUrl != null && fullWebAppUrl.isNotEmpty) {
      rows.add([
        {
          'text': '📱 فتح لوحة التحكم التفاعلية (Mini App)',
          'web_app': {'url': fullWebAppUrl},
        },
      ]);
    }

    rows.addAll([
      [
        button('📸 لقطة شاشة', 'screenshot'),
        button('📷 كاميرا الويب', 'webcam'),
        button('🎙️ ميكروفون', 'mic'),
      ],
      [
        button('📊 صحة الجهاز', 'health'),
        button('🖥️ مواصفات الجهاز', 'specs'),
        button('🚨 صافرة إنذار', 'alarm'),
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
        button('📋 الحافظة', 'clip'),
        button('📈 السجلات والتحليلات', 'menu_insights'),
        button('🛡️ الأمان والحماية', 'menu_security'),
      ],
      [
        button('⚡ وضع الطوارئ', 'emergency'),
        button('↩️ تراجع عن أمر', 'undo'),
        button('📖 دليل الأوامر', 'menu_help'),
      ],
    ]);

    return {
      'inline_keyboard': rows,
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
          button('📑 كافة الملفات والمواقع المفتوحة', 'open_items'),
        ],
        [
          button('📊 العمليات والمهام (Tasks)', 'tasks'),
          button('📦 البرامج المثبتة', 'installed_apps'),
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
          button('❤️ صحة ومواصفات الجهاز', 'health'),
        ],
        [
          button('📜 طلب سجلات النشاط', 'logs'),
          button('🧹 تنظيف وتسريع الجهاز', 'cleanup'),
        ],
        [
          button('📸 التقاط صورة الشاشة', 'screenshot'),
          button('📷 كاميرا الويب', 'webcam'),
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
          button('⚡ تفعيل كافة الصلاحيات والأذونات فوراً', 'allow_all_permissions'),
        ],
        [
          button('🔓 سماح بتثبيت البرامج (15د)', 'allow_install_15'),
          button('🛡️ قفل ومنع التثبيت فوراً', 'block_install'),
        ],
        [
          button('🛡️ قواعد حماية المسارات', 'path_rules'),
          button('🚫 قائمة الممنوعات', 'blocked_items'),
        ],
        [
          button('🔑 إظهار رمز الربط QR', 'qr'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  Future<void> _handleCustomLogsQuery(
    String query, {
    required String chatId,
    int? replyToMessageId,
  }) async {
    final lower = query.toLowerCase().trim();
    String logType = 'all';
    DateTime? from;
    DateTime? to;

    if (lower.contains('ملف') || lower.contains('file') || lower.contains('مسار') || lower.contains('path')) {
      logType = 'path_opened';
    } else if (lower.contains('برامج') || lower.contains('برنامج') || lower.contains('app') || lower.contains('تطبيق')) {
      logType = 'app_blocked';
    } else if (lower.contains('منع') || lower.contains('حظر') || lower.contains('block')) {
      logType = 'blocked';
    } else if (lower.contains('اوامر') || lower.contains('أوامر') || lower.contains('cmd') || lower.contains('command')) {
      logType = 'commands';
    }

    final now = DateTime.now();
    if (lower.contains('اليوم') || lower.contains('today')) {
      from = DateTime(now.year, now.month, now.day);
    } else if (lower.contains('امس') || lower.contains('أمس') || lower.contains('yesterday')) {
      from = DateTime(now.year, now.month, now.day - 1);
      to = DateTime(now.year, now.month, now.day);
    } else if (lower.contains('ساعة') || lower.contains('1h') || lower.contains('hour')) {
      from = now.subtract(const Duration(hours: 1));
    } else if (lower.contains('اسبوع') || lower.contains('أسبوع') || lower.contains('7d') || lower.contains('week')) {
      from = now.subtract(const Duration(days: 7));
    } else if (lower.contains('شهر') || lower.contains('30d') || lower.contains('month')) {
      from = now.subtract(const Duration(days: 30));
    }

    final dateMatches = RegExp(r'\b\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?\b').allMatches(query).toList();
    if (dateMatches.length >= 2) {
      from = DateTime.tryParse(dateMatches[0].group(0)!);
      to = DateTime.tryParse(dateMatches[1].group(0)!);
    } else if (dateMatches.length == 1) {
      final d = DateTime.tryParse(dateMatches[0].group(0)!);
      if (d != null) {
        from = DateTime(d.year, d.month, d.day);
        to = DateTime(d.year, d.month, d.day, 23, 59, 59);
      }
    }

    final logs = await store.queryLogs(type: logType, from: from, to: to, limit: 30);
    final payloadText = _briefPayload('request_logs', {'logs': logs});
    await telegram.sendMessage(
      payloadText,
      chatId: chatId,
      replyToMessageId: replyToMessageId,
      replyMarkup: _resultInlineButtons('request_logs', {'logs': logs}),
    );
  }

  Future<void> _handleLogFilterCallback(
    String param, {
    required String chatId,
    int? messageId,
  }) async {
    String logType = 'all';
    DateTime? from;
    DateTime? to;

    if (param.startsWith('type:')) {
      logType = param.substring('type:'.length);
    } else if (param.startsWith('range:')) {
      final range = param.substring('range:'.length);
      final now = DateTime.now();
      switch (range) {
        case '1h':
          from = now.subtract(const Duration(hours: 1));
          break;
        case 'today':
          from = DateTime(now.year, now.month, now.day);
          break;
        case 'yesterday':
          from = DateTime(now.year, now.month, now.day - 1);
          to = DateTime(now.year, now.month, now.day);
          break;
        case '7d':
          from = now.subtract(const Duration(days: 7));
          break;
        case '30d':
          from = now.subtract(const Duration(days: 30));
          break;
        default:
          from = null;
      }
    }

    final logs = await store.queryLogs(type: logType, from: from, to: to, limit: 30);
    final payloadText = _briefPayload('request_logs', {'logs': logs});
    await _editOrSendMessage(
      payloadText,
      chatId: chatId,
      messageId: messageId,
      replyMarkup: _resultInlineButtons('request_logs', {'logs': logs}),
    );
  }

  Map<String, dynamic> _logFilterInlineMenu() {
    return {
      'inline_keyboard': [
        [
          {'text': '📁 ملفات ومسارات', 'callback_data': 'log_filter:type:path_opened'},
          {'text': '🖥️ برامج وتطبيقات', 'callback_data': 'log_filter:type:app_blocked'},
        ],
        [
          {'text': '🚫 محاولات ممنوعة', 'callback_data': 'log_filter:type:blocked'},
          {'text': '⚡ أوامر منفذة', 'callback_data': 'log_filter:type:commands'},
        ],
        [
          {'text': '🔌 شبكة وأجهزة', 'callback_data': 'log_filter:type:network'},
          {'text': '📑 جميع السجلات', 'callback_data': 'log_filter:type:all'},
        ],
        [
          {'text': '🕐 آخر ساعة', 'callback_data': 'log_filter:range:1h'},
          {'text': '📅 سجل اليوم', 'callback_data': 'log_filter:range:today'},
        ],
        [
          {'text': '📆 سجل أمس', 'callback_data': 'log_filter:range:yesterday'},
          {'text': '🗓️ آخر 7 أيام', 'callback_data': 'log_filter:range:7d'},
        ],
        [
          {'text': '🔙 القائمة الرئيسية', 'callback_data': 'menu_main'},
        ],
      ],
    };
  }

  Map<String, dynamic> _fileActionInlineMenu(String path) {
    return {
      'inline_keyboard': [
        [
          {'text': '📂 فتح المسار بالكمبيوتر', 'callback_data': 'exec_open:$path'},
          {'text': '📤 إرسال لـ Telegram', 'callback_data': 'get_file:$path'},
        ],
        [
          {'text': '🔒 قفل نهائي (Blocked)', 'callback_data': 'lock_type:blocked:$path'},
          {'text': '🔑 قفل بكلمة مرور', 'callback_data': 'lock_type:password:$path'},
        ],
        [
          {'text': '📱 قفل بإذن الهاتف', 'callback_data': 'lock_type:permissionRequired:$path'},
          {'text': '👁️ قفل قراءة فقط', 'callback_data': 'lock_type:readOnly:$path'},
        ],
        [
          {'text': '⏳ قفل مؤقت (ساعة)', 'callback_data': 'lock_timed:$path:60'},
          {'text': '⏳ مهلات قفل أخرى', 'callback_data': 'lock_timed_menu:$path'},
        ],
        [
          {'text': '☁️ مزامنة OneDrive', 'callback_data': 'sync_onedrive:$path'},
          {'text': '☁️ مزامنة Google Drive', 'callback_data': 'sync_gdrive:$path'},
        ],
        [
          {'text': '🗑️ حذف الملف نهائياً', 'callback_data': 'delete_file:$path'},
          {'text': '🔙 العودة للسجل', 'callback_data': 'logs'},
        ],
      ],
    };
  }

  Map<String, dynamic> _allLockTypesMenu(String path) {
    return {
      'inline_keyboard': [
        [
          {'text': '🔒 قفل ومنع نهائي (Blocked)', 'callback_data': 'lock_type:blocked:$path'},
        ],
        [
          {'text': '🔑 قفل بكلمة سر (Password)', 'callback_data': 'lock_type:password:$path'},
        ],
        [
          {'text': '📱 قفل باشتراط إذن الهاتف (Permission Required)', 'callback_data': 'lock_type:permissionRequired:$path'},
        ],
        [
          {'text': '👁️ قفل للقراءة فقط (Read-Only / No Modify)', 'callback_data': 'lock_type:readOnly:$path'},
        ],
        [
          {'text': '⏳ قفل مؤقت لمهلة زمنية محددة', 'callback_data': 'lock_timed_menu:$path'},
        ],
        [
          {'text': '🔙 إلغاء وعودة', 'callback_data': 'logs'},
        ],
      ],
    };
  }

  Map<String, dynamic> _appActionInlineMenu({required String name, required String pid, String title = ''}) {
    return {
      'inline_keyboard': [
        [
          {'text': '❌ إغلاق فوري (Kill)', 'callback_data': 'kill_proc:$pid:$name'},
          {'text': '⏳ إغلاق بعد 5 دقائق', 'callback_data': 'close_after:$name:5'},
        ],
        [
          {'text': '⏳ إغلاق بعد 15 دقيقة', 'callback_data': 'close_after:$name:15'},
          {'text': '⏳ إغلاق بعد 30 دقيقة', 'callback_data': 'close_after:$name:30'},
        ],
        [
          {'text': '🚫 حظر ومنع نهائي', 'callback_data': 'block_app:$name'},
          {'text': '⏳ حظر مؤقت (ساعة)', 'callback_data': 'block_app_timed:$name:60'},
        ],
        [
          {'text': '🔓 فك حظر وسماح', 'callback_data': 'allow_app:$name'},
          {'text': '📸 لقطة شاشة للنافذة', 'callback_data': 'screenshot'},
        ],
        [
          {'text': '🔙 قائمة التطبيقات', 'callback_data': 'apps'},
          {'text': '🏠 القائمة الرئيسية', 'callback_data': 'menu_main'},
        ],
      ],
    };
  }

  Map<String, dynamic> _siteActionInlineMenu(String domain) {
    return {
      'inline_keyboard': [
        [
          {'text': '🚫 حظر الموقع وتوابعه', 'callback_data': 'block_site:$domain'},
          {'text': '🔓 فك حظر وسماح', 'callback_data': 'allow_site:$domain'},
        ],
        [
          {'text': '🌐 فتح في المتصفح', 'callback_data': 'exec_open_url:$domain'},
          {'text': '🔙 العودة للسجل', 'callback_data': 'logs'},
        ],
      ],
    };
  }

  String _helpText() {
    return '📖 <b>الدليل الشامل للتحكم بالكمبيوتر عبر سحابة Telegram:</b>\n\n'
        '📁 <b>الملفات، التنزيل والرفع السحابي:</b>\n'
        '• أرسل أي رابط ملف أو استخدم <code>/download &lt;رابط&gt;</code> لتنزيله فوراً على الكمبيوتر مع أزرار تفاعلية.\n'
        '• <code>/upload C:\\path\\file.ext</code>: رفع ملف إلى رابط سحابي مباشر.\n'
        '• <code>/upload_to C:\\path\\file.ext &lt;رابط_الرفع&gt;</code>: رفع ملف إلى رابط مخصص أو Webhook.\n'
        '• <code>/get C:\\path\\file.ext</code>: إرسال أي ملف من الكمبيوتر إلى Telegram.\n'
        '• <code>/search تقرير</code>: بحث عن ملفات في الكمبيوتر وتحميلها.\n'
        '• <code>/open C:\\path\\file.ext</code>: فتح ملف على شاشة الكمبيوتر.\n'
        '• <code>/delete C:\\path\\file.ext</code>: حذف ملف.\n'
        '• <code>/browse roots</code>: استعراض أقراص وملفات الكمبيوتر.\n\n'
        '👁️ <b>البرامج، التبويبات والمواقع:</b>\n'
        '• <code>/open_items</code>: تقرير تفصيلي بكافة الملفات، المجلدات والمواقع المفتوحة مع أزرار التحكم.\n'
        '• <code>/apps</code>: عرض البرامج المفتوحة ونوافذ المتصفح.\n'
        '• <code>/tasks</code>: عرض العمليات الأكثر استهلاكاً للذاكرة والمعالج مع خيار الإغلاق.\n'
        '• <code>/close chrome.exe</code>: إغلاق برنامج أو نافذة.\n'
        '• <code>/blockapp game.exe</code>: منع تشغيل برنامج.\n'
        '• <code>/allowapp game.exe</code>: السماح لبرنامج.\n'
        '• <code>/blocksite youtube.com</code>: حظر موقع.\n'
        '• <code>/allowsite youtube.com</code>: السماح لموقع.\n'
        '• <code>/installed</code>: عرض البرامج المثبتة.\n\n'
        '🔒 <b>التحكم، الصحة والطاقة:</b>\n'
        '• <code>status</code>: فحص الاتصال.\n'
        '• <code>screenshot</code>: لقطة شاشة فورية.\n'
        '• <code>webcam</code>: لقطة من كاميرا الويب.\n'
        '• <code>mic 10</code>: تسجيل صوتي من ميكروفون الكمبيوتر.\n'
        '• <code>health</code>: صحة الجهاز (CPU, RAM, Disks).\n'
        '• <code>cleanup</code>: تنظيف الملفات المؤقتة وسلة المحذوفات.\n'
        '• <code>lock</code> | <code>lock 30</code> | <code>unlock</code>\n'
        '• <code>emergency</code>: وضع الطوارئ الشامل.\n'
        '• <code>shutdown</code> | <code>restart</code>\n'
        '• <code>wifi on/off</code> | <code>internet on/off</code> | <code>bt on/off</code>\n'
        '• <code>volume 50</code> | <code>volup</code> | <code>voldown</code> | <code>mute</code>\n'
        '• <code>msg مرحباً</code>: إظهار رسالة منبثقة على شاشة الكمبيوتر.\n'
        '• <code>mode study/work/kids/protection</code>: الأوضاع الذكية.\n'
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
