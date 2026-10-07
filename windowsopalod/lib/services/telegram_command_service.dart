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
    this.interval = const Duration(seconds: 2),
  });

  final String deviceId;
  final String deviceName;
  final JsonFileStore store;
  final TelegramNotifierService telegram;
  final CommandExecutorService executor;
  final Duration interval;

  final Map<String, _PendingConfirmation> _pendingConfirmations = {};
  Timer? _timer;
  bool _polling = false;

  void start() {
    if (!telegram.hasBotToken) {
      unawaited(store.appendLog('telegram_command_start_skipped',
          'لم يبدأ مستقبل أوامر Telegram لأن bot token غير مضبوط'));
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _poll());
    unawaited(store.appendLog(
      'telegram_command_start',
      'بدأ مستقبل أوامر Telegram',
      {'deviceId': deviceId},
    ));
    unawaited(telegram.deleteWebhook(dropPendingUpdates: false));
    _poll();
  }

  void stop() => _timer?.cancel();

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

    final message = (update['message'] as Map?)?.cast<String, dynamic>();
    if (message == null) return;

    final chat = (message['chat'] as Map?)?.cast<String, dynamic>();
    final chatId = (chat?['id'] ?? '').toString();
    if (chatId.isEmpty) return;

    final messageId = (message['message_id'] as num?)?.toInt();
    final allowedChatId = telegram.effectiveChatId;

    if (allowedChatId.isEmpty) {
      await telegram.sendMessage(
        '👋 مرحباً! معرف المحادثة (Chat ID) الخاص بك هو:\n<code>$chatId</code>\n\n'
        'انسخه وضعه في تطبيق الهاتف (KIMO) لربط البوت بهذا الكمبيوتر فوراً.',
        chatId: chatId,
        replyToMessageId: messageId,
      );
      return;
    }

    if (chatId != allowedChatId) {
      return;
    }

    // 1. Check if user sent a file (Document, Photo, Video, Audio)
    final hasFile = message.containsKey('document') ||
        message.containsKey('photo') ||
        message.containsKey('video') ||
        message.containsKey('audio') ||
        message.containsKey('voice');

    if (hasFile) {
      await _handleIncomingFile(message, chatId: chatId, messageId: messageId);
      return;
    }

    final text = (message['text'] ?? '').toString().trim();
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

    // Determine target save folder
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
      '⏳ جاري تنزيل وحفظ الملف على الكمبيوتر...\n'
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
    final allowedChatId = telegram.effectiveChatId;

    if (chatId.isEmpty || allowedChatId.isEmpty || chatId != allowedChatId) {
      return;
    }

    // 1. Confirmation callbacks: confirm_yes:<token> or confirm_no:<token>
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

    // 2. Navigation menus
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
        '📁 <b>إدارة الملفات بالكمبيوتر:</b>\n'
        'اختر مجلداً لعرض محتوياته أو إرسال ملف، أو اكتب أمر مثل:\n'
        '• <code>/get C:\\Users\\...\\file.pdf</code> لإرسال ملف لتليجرام\n'
        '• <code>/search تقرير</code> للبحث عن ملفات\n'
        '• أو أرسل أي ملف للمحادثة وسيتم حفظه في الكمبيوتر فوراً!',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _filesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_modes') {
      await telegram.sendMessage(
        '🎛️ <b>الأوضاع الجاهزة السريعة:</b>\nاختر الوضع المطلوب لتطبيقه فوراً على الكمبيوتر:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _modesInlineMenu(),
      );
      return;
    }
    if (data == 'menu_network') {
      await telegram.sendMessage(
        '🌐 <b>التحكم بالشبكة والصوت:</b>\nتحكم بالاتصال ومستوى الصوت والبلوتوث:',
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _networkInlineMenu(),
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

    // Check if the command is dangerous and needs user confirmation
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
      '⏳ <b>تم استلام الأمر:</b> ${parsed.type}\n🖥️ <b>الجهاز:</b> $deviceName',
      chatId: chatId,
      replyToMessageId: replyToMessageId,
    );

    final result = await executor.executeTelegramCommand(
      type: parsed.type,
      payload: parsed.payload,
    );

    await telegram.sendMessage(
      _formatResult(parsed.type, result),
      chatId: chatId,
      replyToMessageId: replyToMessageId,
      replyMarkup: _dashboardInlineMenu(),
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
        lower == 'app') {
      // Remove any old dark reply keyboard permanently
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
        lower.startsWith('send ') && !lower.startsWith('send bt')) {
      final path = rest.isNotEmpty
          ? rest
          : (lower.startsWith('send ') ? normalized.substring(5).trim() : '');
      if (path.isNotEmpty) {
        return _ParsedTelegramCommand('send_file_to_telegram', {'path': path});
      }
    }

    if (lower == 'status' ||
        lower == 'متصل' ||
        lower == 'فحص' ||
        lower == 'الحالة') {
      return const _ParsedTelegramCommand('check_connection');
    }
    if (lower == 'screenshot' ||
        lower == 'screen' ||
        lower == 'لقطة' ||
        lower == 'صورة الشاشة') {
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
    if (first == 'lock' || first == 'قفل') {
      final minutes = int.tryParse(rest);
      return _ParsedTelegramCommand(
        minutes == null ? 'lock_screen' : 'lock_for_duration',
        minutes == null ? const {} : {'minutes': minutes},
      );
    }
    if (lower == 'unlock' || lower == 'فتح' || lower == 'clear lock') {
      return const _ParsedTelegramCommand('clear_timed_lock');
    }
    if (lower == 'shutdown' || lower == 'اطفاء' || lower == 'إغلاق') {
      return const _ParsedTelegramCommand('shutdown_pc');
    }
    if (lower == 'restart' || lower == 'اعادة تشغيل' || lower == 'إعادة تشغيل') {
      return const _ParsedTelegramCommand('restart_pc');
    }
    if (lower == 'logout' || lower == 'تسجيل خروج') {
      return const _ParsedTelegramCommand('logout_user');
    }
    if (first == 'volume' || first == 'vol' || first == 'صوت') {
      final volume = int.tryParse(rest);
      if (volume != null) {
        return _ParsedTelegramCommand('set_volume', {'volume': volume});
      }
    }
    if (lower == 'volup' || lower == 'volume up' || lower == 'رفع الصوت') {
      return const _ParsedTelegramCommand('volume_up');
    }
    if (lower == 'voldown' || lower == 'volume down' || lower == 'خفض الصوت') {
      return const _ParsedTelegramCommand('volume_down');
    }
    if (lower == 'mute' || lower == 'كتم') {
      return const _ParsedTelegramCommand('mute_volume');
    }
    if (lower == 'unmute' || lower == 'الغاء كتم') {
      return const _ParsedTelegramCommand('unmute_volume');
    }
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
        lower == 'إيقاف الانترنت نهائياً') {
      return const _ParsedTelegramCommand('internet_off_permanent');
    }
    if (lower == 'internet on' ||
        lower == 'net on' ||
        lower == 'تشغيل الانترنت' ||
        lower == 'تشغيل الإنترنت') {
      return const _ParsedTelegramCommand('internet_on');
    }
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
    if (first == 'close' || first == 'اغلق' || first == 'إغلاق_تطبيق') {
      return _ParsedTelegramCommand('close_application', {'target': rest});
    }
    if (lower.startsWith('block app ')) {
      final target = normalized.substring('block app '.length).trim();
      return _ParsedTelegramCommand('block_application', {'target': target});
    }
    if (lower.startsWith('allow app ')) {
      final target = normalized.substring('allow app '.length).trim();
      return _ParsedTelegramCommand('allow_application', {'target': target});
    }
    if (lower.startsWith('block site ')) {
      final target = normalized.substring('block site '.length).trim();
      return _ParsedTelegramCommand('block_website', {'domain': target});
    }
    if (lower.startsWith('allow site ')) {
      final target = normalized.substring('allow site '.length).trim();
      return _ParsedTelegramCommand('allow_website', {'domain': target});
    }
    if (lower.startsWith('browse ') || lower.startsWith('تصفح ')) {
      final path = lower.startsWith('browse ')
          ? normalized.substring('browse '.length).trim()
          : normalized.substring('تصفح '.length).trim();
      return _ParsedTelegramCommand('browse_path', {'path': path});
    }
    if (lower.startsWith('search ') || lower.startsWith('بحث ')) {
      final query = lower.startsWith('search ')
          ? normalized.substring('search '.length).trim()
          : normalized.substring('بحث '.length).trim();
      return _ParsedTelegramCommand('search_files', {'query': query, 'rootPath': 'home'});
    }
    if (lower.startsWith('open ') || lower.startsWith('افتح ')) {
      final path = lower.startsWith('open ')
          ? normalized.substring('open '.length).trim()
          : normalized.substring('افتح '.length).trim();
      return _ParsedTelegramCommand('open_path', {'path': path});
    }
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
    if (lower == 'stop commands' || lower == 'ايقاف الاوامر') {
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
    if (type == 'browse_path' || type == 'search_files') {
      final items = (payload['items'] as List?) ?? const [];
      final lines = items.take(15).map((item) {
        if (item is! Map) return item.toString();
        final name = (item['name'] ?? '').toString();
        final path = (item['path'] ?? '').toString();
        final isDir = item['type'] == 'directory' || item['type'] == 'drive';
        final icon = isDir ? '📁' : '📄';
        return '$icon $name\n   <code>/get $path</code>';
      }).join('\n');
      return lines;
    }
    return '';
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
      case 'unlock':
        return 'unlock';
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
      case 'vol_up':
        return 'volup';
      case 'vol_down':
        return 'voldown';
      case 'vol_mute':
        return 'mute';
      case 'vol_unmute':
        return 'unmute';
      case 'bt_on':
        return 'bluetooth on';
      case 'bt_off':
        return 'bluetooth off';
      case 'browse_downloads':
        return 'browse ${_getKnownFolder('Downloads')}';
      case 'browse_desktop':
        return 'browse ${_getKnownFolder('Desktop')}';
      case 'browse_documents':
        return 'browse ${_getKnownFolder('Documents')}';
      case 'browse_roots':
        return 'browse roots';
      default:
        return data;
    }
  }

  String _dashboardText() {
    return '⚡ <b>لوحة تحكم KIOM التفاعلية بالكمبيوتر:</b>\n'
        '🖥️ <b>الجهاز:</b> $deviceName ($deviceId)\n\n'
        'اختر أحد الإجراءات السريعة أدناه أو أرسل أي ملف ليتم حفظه بالكمبيوتر فوراً:';
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
          button('⚡ طوارئ', 'emergency'),
        ],
        [
          button('📁 إدارة الملفات', 'menu_files'),
          button('🔒 قفل الشاشة', 'lock'),
          button('🛡️ وضع الخصوصية', 'privacy_on'),
        ],
        [
          button('🎛️ الأوضاع الجاهزة', 'menu_modes'),
          button('🌐 الشبكة والصوت', 'menu_network'),
        ],
        [
          button('↩️ تراجع عن أمر', 'undo'),
          button('📜 السجلات', 'logs'),
          button('ℹ️ مساعدة', 'menu_help'),
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
          button('📥 التنزيلات (Downloads)', 'browse_downloads'),
          button('🖥️ سطح المكتب', 'browse_desktop'),
        ],
        [
          button('📁 المستندات', 'browse_documents'),
          button('💾 الأقراص C / D', 'browse_roots'),
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
          button('💼 وضع العمل', 'mode_work'),
        ],
        [
          button('👶 وضع الأطفال', 'mode_kids'),
          button('🛡️ الحماية القصوى', 'mode_protection'),
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
          button('🔊 رفع الصوت', 'vol_up'),
          button('🔉 خفض الصوت', 'vol_down'),
          button('🔇 كتم', 'vol_mute'),
        ],
        [
          button('🔵 تشغيل BT', 'bt_on'),
          button('⚫ إيقاف BT', 'bt_off'),
        ],
        [
          button('🔙 العودة للوحة الرئيسية', 'menu_main'),
        ],
      ],
    };
  }

  String _helpText() {
    return '📖 <b>دليل أوامر بوت KIOM:</b>\n\n'
        '<b>الملفات وتبادل البيانات:</b>\n'
        '• أرسل أي ملف للمحادثة وسيتم حفظه في <code>Downloads</code> بالكمبيوتر تلقائياً.\n'
        '• <code>/get C:\\path\\file.ext</code>: إرسال ملف من الكمبيوتر إلى Telegram.\n'
        '• <code>/search تقرير</code>: بحث عن ملفات في الكمبيوتر وتحميلها.\n'
        '• <code>/browse roots</code>: استعراض أقراص وملفات الكمبيوتر.\n\n'
        '<b>التحكم والأمان:</b>\n'
        '• <code>status</code> أو <code>فحص</code>: فحص الاتصال.\n'
        '• <code>screenshot</code>: طلب لقطة شاشة عالية الدقة.\n'
        '• <code>health</code>: عرض حالة المعالج والذاكرة والبطارية.\n'
        '• <code>lock</code>: قفل شاشة الكمبيوتر (مع تأكيد قبل التنفيذ).\n'
        '• <code>emergency</code>: تفعيل وضع الطوارئ الشامل.\n'
        '• <code>shutdown</code>: إغلاق الكمبيوتر (مع زر تأكيد).\n'
        '• <code>restart</code>: إعادة التشغيل (مع زر تأكيد).\n'
        '• <code>privacy on</code> / <code>privacy off</code>: وضع الخصوصية.\n'
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
