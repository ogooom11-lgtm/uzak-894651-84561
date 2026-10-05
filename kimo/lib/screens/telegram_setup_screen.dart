import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';

class TelegramSetupScreen extends StatefulWidget {
  const TelegramSetupScreen({
    super.key,
    required this.userId,
    required this.deviceId,
    this.deviceName,
    this.device,
    this.afterPairing = false,
  });

  static const botUrl = 'https://t.me/tamkontrolkimidev_bot';
  static const botUsername = 'tamkontrolkimidev_bot';

  final String userId;
  final String deviceId;
  final String? deviceName;
  final PcDevice? device;
  final bool afterPairing;

  @override
  State<TelegramSetupScreen> createState() => _TelegramSetupScreenState();
}

class _TelegramSetupScreenState extends State<TelegramSetupScreen> {
  final _chatIdController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _openBot() async {
    final uri = Uri.parse(TelegramSetupScreen.botUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      await Clipboard.setData(
        const ClipboardData(text: TelegramSetupScreen.botUrl),
      );
      showAppSnack(context, 'لم أستطع فتح الرابط، تم نسخه للحافظة.');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: TelegramSetupScreen.botUrl));
    if (mounted) showAppSnack(context, 'تم نسخ رابط البوت.');
  }

  Future<void> _saveChatId() async {
    final chatId = _chatIdController.text.trim();
    if (chatId.isEmpty) {
      showAppSnack(context, 'اكتب Chat ID أولاً.', error: true);
      return;
    }
    if (!RegExp(r'^-?\d{4,}$').hasMatch(chatId)) {
      showAppSnack(
        context,
        'Chat ID يجب أن يكون أرقاماً فقط، وقد يبدأ بإشارة - للمجموعات.',
        error: true,
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final repo = context.read<DeviceRepository>();
      final commandId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.deviceId,
        type: CommandType.configureTelegramChat,
        payload: {
          'chatId': chatId,
          'botUrl': TelegramSetupScreen.botUrl,
          'botUsername': TelegramSetupScreen.botUsername,
        },
      );
      final response = await repo.waitForCommandResponse(
        deviceId: widget.deviceId,
        commandId: commandId,
        timeout: const Duration(seconds: 12),
      );
      if (!mounted) return;
      if (response == null) {
        showAppSnack(
          context,
          'تم إرسال Chat ID للكمبيوتر. سيبدأ Telegram عند استلام الأمر.',
        );
      } else if (response.success) {
        showAppSnack(
          context,
          response.message.isEmpty ? 'تم ربط Telegram.' : response.message,
        );
      } else {
        showAppSnack(context, response.message, error: true);
        return;
      }
      if (widget.afterPairing && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showAppSnack(context, 'تعذر إرسال Chat ID: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deviceName = widget.device?.name ?? widget.deviceName ?? widget.deviceId;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.afterPairing ? 'ربط Telegram' : 'إعداد Telegram'),
        actions: [
          if (widget.afterPairing)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تخطي الآن'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.send_rounded, color: Colors.white, size: 42),
                const SizedBox(height: 12),
                Text(
                  widget.afterPairing
                      ? 'آخر خطوة: اربط Telegram'
                      : 'ربط محادثة Telegram',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'الجهاز: $deviceName\nأرسل Chat ID للكمبيوتر حتى يرسل التنبيهات ويتلقى الأوامر من نفس المحادثة.',
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '1. افتح بوت Telegram',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    TelegramSetupScreen.botUrl,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _openBot,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('فتح الرابط'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _copyLink,
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('نسخ الرابط'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '2. اكتب Chat ID هنا',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'بعد فتح البوت اضغط Start، وخذ Chat ID الذي يظهر لك ثم اكتبه هنا. بعدها الهاتف سيرسله للكمبيوتر مباشرة.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _chatIdController,
                    textDirection: TextDirection.ltr,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Telegram Chat ID',
                      hintText: 'مثال: 123456789 أو -1001234567890',
                      prefixIcon: Icon(Icons.numbers_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _sending ? null : _saveChatId,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_rounded),
                    label: Text(_sending ? 'جاري الإرسال...' : 'حفظ وإرسال للكمبيوتر'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ملاحظة: يجب أن يكون الكمبيوتر متصلاً وأن يكون Bot Token مضبوطاً في إعدادات الوكيل. الهاتف يرسل Chat ID فقط للكمبيوتر.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
