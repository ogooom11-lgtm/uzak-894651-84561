import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/agent_config.dart';
import '../utils/json_file_store.dart';

class TelegramNotifierService {
  TelegramNotifierService({
    required this.config,
    required this.store,
    String? botToken,
    String? chatId,
    http.Client? client,
  })  : _customBotToken = botToken,
        _customChatId = chatId,
        client = client ?? http.Client();

  final AgentConfig config;
  final JsonFileStore store;
  final String? _customBotToken;
  final String? _customChatId;
  final http.Client client;

  static const Duration _httpTimeout = Duration(seconds: 20);

  String get botToken {
    if (_customBotToken != null && _customBotToken!.trim().isNotEmpty) {
      return _customBotToken!.trim();
    }
    return config.telegramBotToken.trim();
  }

  String get effectiveChatId {
    if (_customChatId != null && _customChatId!.trim().isNotEmpty) {
      return _customChatId!.trim();
    }
    final override = (store.get<String>('telegramChatIdOverride') ?? '').trim();
    return override.isNotEmpty ? override : config.telegramChatId.trim();
  }

  bool get hasBotToken => botToken.isNotEmpty;

  bool get isConfigured => hasBotToken && effectiveChatId.isNotEmpty;

  Future<bool> sendMessage(
    String message, {
    String? chatId,
    int? replyToMessageId,
    Map<String, dynamic>? replyMarkup,
    String parseMode = 'HTML',
  }) async {
    if (!hasBotToken) return false;
    final targetChatId = (chatId ?? effectiveChatId).trim();
    if (targetChatId.isEmpty) return false;
    try {
      final response = await client
          .post(
            Uri.parse(_api('sendMessage')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': targetChatId,
              'text': message,
              if (parseMode.isNotEmpty) 'parse_mode': parseMode,
              'disable_web_page_preview': true,
              if (replyToMessageId != null)
                'reply_to_message_id': replyToMessageId,
              if (replyMarkup != null) 'reply_markup': replyMarkup,
            }),
          )
          .timeout(_httpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Fallback without parse_mode if HTML parsing failed
        if (parseMode.isNotEmpty) {
          return sendMessage(
            message,
            chatId: targetChatId,
            replyToMessageId: replyToMessageId,
            replyMarkup: replyMarkup,
            parseMode: '',
          );
        }
        await store.appendLog('telegram_send_error',
            'Telegram sendMessage failed: ${response.statusCode}', {
          'body': response.body,
        });
        return false;
      }
      return true;
    } catch (e) {
      await store.appendLog('telegram_send_exception', e.toString());
      return false;
    }
  }

  Future<bool> editMessageText({
    required String text,
    String? chatId,
    int? messageId,
    Map<String, dynamic>? replyMarkup,
    String parseMode = 'HTML',
  }) async {
    if (!hasBotToken || messageId == null) return false;
    final targetChatId = (chatId ?? effectiveChatId).trim();
    if (targetChatId.isEmpty) return false;
    try {
      final response = await client
          .post(
            Uri.parse(_api('editMessageText')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': targetChatId,
              'message_id': messageId,
              'text': text,
              if (parseMode.isNotEmpty) 'parse_mode': parseMode,
              'disable_web_page_preview': true,
              if (replyMarkup != null) 'reply_markup': replyMarkup,
            }),
          )
          .timeout(_httpTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      await store.appendLog('telegram_edit_message_exception', e.toString());
      return false;
    }
  }

  Future<bool> removeReplyKeyboard({String? chatId, String message = ''}) async {
    if (!hasBotToken) return false;
    final targetChatId = (chatId ?? effectiveChatId).trim();
    if (targetChatId.isEmpty) return false;
    try {
      final response = await client
          .post(
            Uri.parse(_api('sendMessage')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': targetChatId,
              'text': message.isNotEmpty ? message : '⚡ تم تفعيل واجهة التحكم التفاعلية',
              'reply_markup': {'remove_keyboard': true},
            }),
          )
          .timeout(_httpTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getUpdates({int? offset}) async {
    if (!hasBotToken) return const [];
    try {
      final response = await client
          .get(
            Uri.parse(_api('getUpdates')).replace(queryParameters: {
              if (offset != null) 'offset': offset.toString(),
              'timeout': '0',
              'allowed_updates': jsonEncode(['message', 'callback_query']),
            }),
          )
          .timeout(_httpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await store.appendLog('telegram_updates_error',
            'Telegram getUpdates failed: ${response.statusCode}', {
          'body': response.body,
        });
        return const [];
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'];
      if (result is! List) return const [];
      return result
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (e) {
      await store.appendLog('telegram_updates_exception', e.toString());
      return const [];
    }
  }

  Future<bool> deleteWebhook({bool dropPendingUpdates = false}) async {
    if (!hasBotToken) return false;
    try {
      final response = await client
          .post(
            Uri.parse(_api('deleteWebhook')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'drop_pending_updates': dropPendingUpdates,
            }),
          )
          .timeout(_httpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await store.appendLog('telegram_delete_webhook_error',
            'Telegram deleteWebhook failed: ${response.statusCode}', {
          'body': response.body,
        });
        return false;
      }
      return true;
    } catch (e) {
      await store.appendLog('telegram_delete_webhook_exception', e.toString());
      return false;
    }
  }

  Future<bool> answerCallbackQuery(
    String callbackQueryId, {
    String text = '',
    bool showAlert = false,
  }) async {
    if (!hasBotToken || callbackQueryId.isEmpty) {
      return false;
    }
    try {
      final response = await client
          .post(
            Uri.parse(_api('answerCallbackQuery')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'callback_query_id': callbackQueryId,
              if (text.isNotEmpty) 'text': text,
              if (showAlert) 'show_alert': true,
            }),
          )
          .timeout(_httpTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      await store.appendLog('telegram_callback_answer_exception', e.toString());
      return false;
    }
  }

  Future<bool> sendPhoto({
    required String filePath,
    String? chatId,
    String caption = '',
    int? replyToMessageId,
  }) async {
    if (!hasBotToken) return false;
    final targetChatId = (chatId ?? effectiveChatId).trim();
    if (targetChatId.isEmpty) return false;
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final request =
          http.MultipartRequest('POST', Uri.parse(_api('sendPhoto')))
            ..fields['chat_id'] = targetChatId
            ..fields['caption'] = caption;
      if (replyToMessageId != null) {
        request.fields['reply_to_message_id'] = replyToMessageId.toString();
      }
      request.files.add(await http.MultipartFile.fromPath('photo', filePath));

      final response = await request.send().timeout(const Duration(seconds: 40));
      final body = await response.stream.bytesToString().timeout(_httpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await store.appendLog('telegram_photo_error',
            'Telegram sendPhoto failed: ${response.statusCode}', {
          'body': body,
        });
        return false;
      }
      return true;
    } catch (e) {
      await store.appendLog('telegram_photo_exception', e.toString());
      return false;
    }
  }

  Future<bool> sendDocument({
    required String filePath,
    String? chatId,
    String caption = '',
    int? replyToMessageId,
  }) async {
    if (!hasBotToken) return false;
    final targetChatId = (chatId ?? effectiveChatId).trim();
    if (targetChatId.isEmpty) return false;
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final request =
          http.MultipartRequest('POST', Uri.parse(_api('sendDocument')))
            ..fields['chat_id'] = targetChatId
            ..fields['caption'] = caption;
      if (replyToMessageId != null) {
        request.fields['reply_to_message_id'] = replyToMessageId.toString();
      }
      request.files.add(await http.MultipartFile.fromPath('document', filePath));

      final response = await request.send().timeout(const Duration(seconds: 60));
      final body = await response.stream.bytesToString().timeout(_httpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await store.appendLog('telegram_document_error',
            'Telegram sendDocument failed: ${response.statusCode}', {
          'body': body,
        });
        return false;
      }
      return true;
    } catch (e) {
      await store.appendLog('telegram_document_exception', e.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>?> getFileInfo(String fileId) async {
    if (!hasBotToken || fileId.isEmpty) return null;
    try {
      final response = await client
          .get(Uri.parse(_api('getFile')).replace(queryParameters: {'file_id': fileId}))
          .timeout(_httpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['ok'] == true && decoded['result'] is Map) {
        return (decoded['result'] as Map).cast<String, dynamic>();
      }
      return null;
    } catch (e) {
      await store.appendLog('telegram_get_file_exception', e.toString());
      return null;
    }
  }

  Future<String?> downloadTelegramFile({
    required String fileId,
    required String destinationFolder,
    String? preferredFileName,
  }) async {
    if (!hasBotToken) return null;
    try {
      final fileInfo = await getFileInfo(fileId);
      if (fileInfo == null) return null;
      final remoteFilePath = (fileInfo['file_path'] ?? '').toString();
      if (remoteFilePath.isEmpty) return null;

      final downloadUrl =
          'https://api.telegram.org/file/bot$botToken/$remoteFilePath';
      final response = await client
          .get(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final dir = Directory(destinationFolder);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      String fileName = preferredFileName ?? '';
      if (fileName.isEmpty) {
        fileName = remoteFilePath.split('/').last;
      }
      if (fileName.isEmpty) {
        fileName = 'telegram_file_${DateTime.now().millisecondsSinceEpoch}';
      }

      final targetFile = File('${dir.path}${Platform.pathSeparator}$fileName');
      await targetFile.writeAsBytes(response.bodyBytes);
      return targetFile.path;
    } catch (e) {
      await store.appendLog('telegram_download_exception', e.toString());
      return null;
    }
  }

  String _api(String method) =>
      'https://api.telegram.org/bot$botToken/$method';
}
