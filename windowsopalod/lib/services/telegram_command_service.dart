import 'dart:async';
import 'dart:convert';
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

  Timer? _timer;
  bool _polling = false;

  void start() {
    if (!telegram.isConfigured) {
      unawaited(store.appendLog('telegram_command_start_skipped',
          'لم يبدأ مستقبل أوامر Telegram لأن bot token أو chat id غير مضبوط'));
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
    if (chatId.isEmpty || chatId != telegram.config.telegramChatId.trim()) {
      return;
    }

    final text = (message['text'] ?? '').toString().trim();
    if (text.isEmpty) return;
    final messageId = (message['message_id'] as num?)?.toInt();

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

  Future<void> _handleCallbackQuery(Map<String, dynamic> callback) async {
    final id = (callback['id'] ?? '').toString();
    final data = (callback['data'] ?? '').toString();
    final message = (callback['message'] as Map?)?.cast<String, dynamic>();
    final chat = (message?['chat'] as Map?)?.cast<String, dynamic>();
    final chatId = (chat?['id'] ?? '').toString();
    final messageId = (message?['message_id'] as num?)?.toInt();
    if (chatId.isEmpty || chatId != telegram.config.telegramChatId.trim()) return;

    await telegram.answerCallbackQuery(id, text: 'تم الاستلام');
    if (data == 'menu') {
      await telegram.sendMessage(
        _helpText(),
        chatId: chatId,
        replyToMessageId: messageId,
        replyMarkup: _inlineMainMenu(),
      );
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
    final selectedDevice =
        (store.get<String>('telegramSelectedDeviceId') ?? '').toString().trim();
    if (selectedDevice.isEmpty) {
      await telegram.sendMessage(
        'اختر الجهاز أولاً:\n/devices\nثم:\n/use $deviceId',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _inlineMainMenu(),
      );
      return;
    }
    if (selectedDevice.isNotEmpty && selectedDevice != deviceId) return;

    final parsed = _parseCommand(text);
    if (parsed == null) {
      await telegram.sendMessage(
        _helpText(),
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _inlineMainMenu(),
      );
      return;
    }

    await telegram.sendMessage(
      'تم الاستلام: ${parsed.type}\nالجهاز: $deviceName',
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
      replyMarkup: _inlineMainMenu(),
    );
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
        lower == 'مساعدة') {
      await telegram.sendMessage(
        _helpText(),
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _inlineMainMenu(),
      );
      return true;
    }

    if (lower == '/devices' || lower == 'devices' || lower == 'الأجهزة') {
      await telegram.sendMessage(
        'الجهاز المتاح:\n$deviceName\nID: $deviceId\n\nاختره بالأمر:\n/use $deviceId',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _mainKeyboard(),
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
          'تم اختيار الجهاز:\n$deviceName\nID: $deviceId',
          chatId: chatId,
          replyToMessageId: replyToMessageId,
          replyMarkup: _mainKeyboard(),
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
            ? 'الجهاز الحالي: $deviceName\nID: $deviceId'
            : 'هذا الكمبيوتر غير مختار حالياً. المختار: $selected',
        chatId: chatId,
        replyToMessageId: replyToMessageId,
        replyMarkup: _mainKeyboard(),
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
    if (lower == 'shutdown' || lower == 'اطفاء') {
      return const _ParsedTelegramCommand('shutdown_pc');
    }
    if (lower == 'restart' || lower == 'اعادة تشغيل') {
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
    if ((first == 'bluetooth' || first == 'bt') &&
        rest.toLowerCase().startsWith('receive')) {
      final savePath = rest.substring('receive'.length).trim();
      return _ParsedTelegramCommand('open_bluetooth_receive',
          savePath.isEmpty ? const {} : {'savePath': savePath});
    }
    if ((first == 'bluetooth' || first == 'bt') &&
        rest.toLowerCase().startsWith('send ')) {
      final path = rest.substring('send '.length).trim();
      return _ParsedTelegramCommand('send_bluetooth_file', {'path': path});
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
    if (first == 'close' || first == 'اغلق') {
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
    if (lower.startsWith('browse ')) {
      final path = normalized.substring('browse '.length).trim();
      return _ParsedTelegramCommand('browse_path', {'path': path});
    }
    if (lower.startsWith('search ')) {
      final query = normalized.substring('search '.length).trim();
      return _ParsedTelegramCommand('search_files', {'query': query, 'rootPath': 'home'});
    }
    if (lower.startsWith('بحث ')) {
      final query = normalized.substring('بحث '.length).trim();
      return _ParsedTelegramCommand('search_files', {'query': query, 'rootPath': 'home'});
    }
    if (lower.startsWith('open ')) {
      final path = normalized.substring('open '.length).trim();
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

    // أزرار Telegram قد تحتوي رموزاً أو شرطة طويلة؛ نجعل القراءة متسامحة.
    normalized = normalized.replaceFirst(
      RegExp(r'^[^A-Za-z0-9\u0600-\u06FF/]+'),
      '',
    );
    return normalized.trim();
  }

  String _formatResult(String type, CommandExecutionResult result) {
    final prefix = result.success ? 'تمت العملية' : 'فشلت العملية';
    final payload = _briefPayload(type, result.payload);
    return _truncate(
      '$prefix\n'
      'الأمر: $type\n'
      'النتيجة: ${result.message}'
      '${payload.isEmpty ? '' : '\n\n$payload'}',
    );
  }

  String _briefPayload(String type, Map<String, dynamic> payload) {
    if (payload.isEmpty) return '';
    if (type == 'browse_path' || type == 'search_files') {
      final items = (payload['items'] as List?) ?? const [];
      final lines = items.take(20).map((item) {
        if (item is! Map) return item.toString();
        return '- ${item['name'] ?? item['path'] ?? item}';
      }).join('\n');
      return lines.isEmpty ? '' : 'العناصر:\n$lines';
    }
    if (type == 'request_logs') {
      final logs = (payload['logs'] as List?) ?? const [];
      return logs.take(10).map((item) {
        if (item is! Map) return item.toString();
        return '- ${item['createdAt']}: ${item['type']} - ${item['message']}';
      }).join('\n');
    }
    if (type == 'list_bluetooth_devices') {
      final devices = (payload['devices'] as List?) ?? const [];
      return devices.take(20).map((item) {
        if (item is! Map) return item.toString();
        return '- ${item['FriendlyName'] ?? item['friendlyName'] ?? item['name'] ?? 'Bluetooth'} (${item['Status'] ?? item['status'] ?? 'unknown'})';
      }).join('\n');
    }
    return jsonEncode(payload);
  }

  String _truncate(String text) {
    if (text.length <= 3500) return text;
    return '${text.substring(0, 3500)}\n...';
  }

  String _helpText() {
    return 'KIOM Telegram\n'
        'الأجهزة: /devices\n'
        'اختيار جهاز: /use $deviceId\n'
        'إظهار لوحة الأوامر: /commands\n'
        'أوامر سريعة:\n'
        'status, screenshot, health, emergency, logs\n'
        'mode study, mode work, mode kids, mode protection\n'
        'privacy on, privacy off\n'
        'lock, lock 30, unlock\n'
        'shutdown, restart, logout\n'
        'volume 0/25/50/75/100, volup, voldown, mute, unmute\n'
        'wifi on/off, internet off/on\n'
        'bluetooth on/off, bluetooth devices\n'
        'bluetooth receive C:\\\\Users\\\\Public\\\\Downloads\n'
        'bluetooth send C:\\\\path\\\\file.txt\n'
        'message مرحبا من الهاتف\n'
        'close chrome.exe, block app chrome, allow app chrome\n'
        'block site youtube.com, allow site youtube.com\n'
        'browse roots, search report, open C:\\\\path\n'
        'qr, permissions, stop commands';
  }

  String _textFromCallbackData(String data) {
    switch (data) {
      case 'status':
      case 'screenshot':
      case 'health':
      case 'emergency':
      case 'logs':
        return data;
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
      default:
        return data;
    }
  }

  Map<String, dynamic> _inlineMainMenu() {
    Map<String, String> button(String text, String data) => {
          'text': text,
          'callback_data': data,
        };

    return {
      'inline_keyboard': [
        [
          button('الحالة', 'status'),
          button('لقطة', 'screenshot'),
          button('الصحة', 'health'),
        ],
        [
          button('طوارئ', 'emergency'),
          button('قفل', 'lock'),
          button('فتح القفل', 'unlock'),
        ],
        [button('دراسة', 'mode_study'), button('عمل', 'mode_work')],
        [button('أطفال', 'mode_kids'), button('حماية قصوى', 'mode_protection')],
        [button('خصوصية تشغيل', 'privacy_on'), button('خصوصية إيقاف', 'privacy_off')],
        [button('السجلات', 'logs'), button('مساعدة', 'menu')],
      ],
    };
  }

  Map<String, dynamic> _mainKeyboard() {
    Map<String, String> button(String text) => {'text': text};

    return {
      'keyboard': [
        [button('/devices'), button('/use $deviceId'), button('/who')],
        [button('status'), button('screenshot'), button('health')],
        [button('emergency'), button('mode study'), button('mode work')],
        [button('mode kids'), button('mode protection'), button('logs')],
        [button('privacy on'), button('privacy off')],
        [button('lock'), button('lock 30'), button('unlock')],
        [button('volume 25'), button('volume 50'), button('mute')],
        [button('volup'), button('voldown'), button('unmute')],
        [button('wifi on'), button('wifi off')],
        [button('internet on'), button('internet off')],
        [button('bluetooth on'), button('bluetooth off'), button('bluetooth devices')],
        [button('qr'), button('permissions'), button('help')],
        [button('close chrome.exe'), button('message مرحبا من الهاتف')],
        [button('block site youtube.com'), button('allow site youtube.com')],
        [button('browse roots'), button('search report'), button(r'browse C:\Users')],
        [button('stop commands')],
      ],
      'resize_keyboard': true,
      'is_persistent': true,
      'input_field_placeholder': 'اختر أمر جاهز أو اكتب أمر مخصص...',
    };
  }
}

class _ParsedTelegramCommand {
  const _ParsedTelegramCommand(
    this.type, [
    this.payload = const <String, dynamic>{},
  ]);

  final String type;
  final Map<String, dynamic> payload;
}
