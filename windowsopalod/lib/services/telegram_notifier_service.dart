import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/agent_config.dart';
import '../utils/json_file_store.dart';

class TelegramNotifierService {
  TelegramNotifierService({
    required this.config,
    required this.store,
    http.Client? client,
  }) : client = client ?? http.Client();

  final AgentConfig config;
  final JsonFileStore store;
  final http.Client client;

  static const Duration _httpTimeout = Duration(seconds: 15);

  bool get isConfigured =>
      config.telegramBotToken.trim().isNotEmpty &&
      config.telegramChatId.trim().isNotEmpty;

  Future<bool> sendMessage(
    String message, {
    String? chatId,
    int? replyToMessageId,
    Map<String, dynamic>? replyMarkup,
  }) async {
    if (config.telegramBotToken.trim().isEmpty) return false;
    final targetChatId = (chatId ?? config.telegramChatId).trim();
    if (targetChatId.isEmpty) return false;
    try {
      final response = await client
          .post(
            Uri.parse(_api('sendMessage')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': targetChatId,
              'text': message,
              'disable_web_page_preview': true,
              if (replyToMessageId != null)
                'reply_to_message_id': replyToMessageId,
              if (replyMarkup != null) 'reply_markup': replyMarkup,
            }),
          )
          .timeout(_httpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
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

  Future<List<Map<String, dynamic>>> getUpdates({int? offset}) async {
    if (config.telegramBotToken.trim().isEmpty) return const [];
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
    if (config.telegramBotToken.trim().isEmpty) return false;
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
  }) async {
    if (config.telegramBotToken.trim().isEmpty || callbackQueryId.isEmpty) {
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
    String caption = '',
  }) async {
    if (!isConfigured) return false;
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse(_api('sendPhoto')))
            ..fields['chat_id'] = config.telegramChatId
            ..fields['caption'] = caption
            ..files.add(await http.MultipartFile.fromPath('photo', filePath));

      final response = await request.send().timeout(_httpTimeout);
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

  String _api(String method) =>
      'https://api.telegram.org/bot${config.telegramBotToken}/$method';
}
