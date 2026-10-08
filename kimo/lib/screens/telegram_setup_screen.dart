import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_formatters.dart';
import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../repositories/telegram_device_repository.dart';
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
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    if (widget.device?.telegramChatId != null &&
        widget.device!.telegramChatId!.isNotEmpty) {
      _chatIdController.text = widget.device!.telegramChatId!;
    }
  }

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
      showAppSnack(context, 'لم أستطع فتح التطبيق مباشرة، تم نسخ الرابط للحافظة.');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: TelegramSetupScreen.botUrl));
    if (mounted) showAppSnack(context, 'تم نسخ رابط البوت.');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) {
      if (mounted) showAppSnack(context, 'الحافظة فارغة.', error: true);
      return;
    }

    final match = RegExp(r'-?\d{4,}').firstMatch(text);
    if (match != null) {
      final id = match.group(0)!;
      setState(() => _chatIdController.text = id);
      if (mounted) showAppSnack(context, 'تم لصق Chat ID: $id');
    } else {
      setState(() => _chatIdController.text = text);
      if (mounted) showAppSnack(context, 'تم لصق النص من الحافظة.');
    }
  }

  Future<void> _saveChatId() async {
    final chatId = _chatIdController.text.trim();
    if (chatId.isEmpty) {
      showAppSnack(context, 'اكتب Chat ID أو اضغط لصق من الحافظة أولاً.', error: true);
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
      if (repo is TelegramDeviceRepository) {
        await repo.updateConfig(chat: chatId);
      }
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
          'تم إرسال Chat ID للكمبيوتر. سيبدأ البوت بالعمل فوراً كقاعدة بيانات.',
        );
      } else if (response.success) {
        showAppSnack(
          context,
          response.message.isEmpty ? 'تم ربط Telegram بنجاح!' : response.message,
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

  Future<void> _sendTestAlert() async {
    setState(() => _testing = true);
    try {
      final repo = context.read<DeviceRepository>();
      final commandId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.deviceId,
        type: CommandType.checkConnection,
      );
      final response = await repo.waitForCommandResponse(
        deviceId: widget.deviceId,
        commandId: commandId,
        timeout: const Duration(seconds: 10),
      );
      if (!mounted) return;
      if (response != null && response.success) {
        showAppSnack(context, 'تم التحقق من الاتصال بنجاح!');
      } else {
        showAppSnack(context, 'تم إرسال اختبار الاتصال للبوت.');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, 'فشل إرسال اختبار الاتصال: $e', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLinked = widget.device?.isTelegramLinked ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ربط بوت Telegram'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0088CC), Color(0xFF005580)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0088CC).withValues(alpha: .30),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'قاعدة بيانات وسحابة Telegram',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isLinked
                            ? '✅ الجهاز متصل بسحابة Telegram كقاعدة بيانات'
                            : 'اربط البوت للتحكم واستقبال الأوامر والملفات السحابية',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Steps
          _buildStepCard(
            step: '1',
            title: 'افتح بوت Telegram الرسمي',
            description: 'اضغط على الزر أدناه لفتح البوت والضغط على Start (بدء).',
            action: ElevatedButton.icon(
              onPressed: _openBot,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('فتح البوت في Telegram'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0088CC),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          _buildStepCard(
            step: '2',
            title: 'انسخ معرّف المحادثة (Chat ID)',
            description:
                'بعد الضغط على Start، سيرسل لك البوت رسالة ترحيبية تحتوي على Chat ID الخاص بك. انسخه.',
            action: OutlinedButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('نسخ رابط البوت'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          _buildStepCard(
            step: '3',
            title: 'الصق Chat ID واضغط تفعيل',
            description: 'الصق المعرف في الحقل أدناه ليتم ربطه بالكمبيوتر وسحابة التطبيق فوراً.',
            action: Column(
              children: [
                TextField(
                  controller: _chatIdController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Chat ID',
                    hintText: 'مثال: 123456789',
                    prefixIcon: const Icon(Icons.tag_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded),
                      tooltip: 'لصق من الحافظة',
                      onPressed: _pasteFromClipboard,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _saveChatId,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_done_rounded),
                    label: Text(
                      _sending
                          ? 'جاري الربط والحفظ...'
                          : (isLinked ? 'تحديث وتثبيت السحابة' : 'ربط البوت كقاعدة بيانات'),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Test section if already linked
          if (isLinked) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.green.withValues(alpha: .3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'الجهاز مربوط بنجاح',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'معرّف Chat ID: ${widget.device!.telegramChatId}',
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  ),
                  if (widget.device?.telegramLinkedAt != null)
                    Text(
                      'تاريخ الربط: ${_formatDate(widget.device!.telegramLinkedAt!)}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _sendTestAlert,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.notifications_active_outlined, size: 18),
                      label: const Text('إرسال اختبار اتصال بالكمبيوتر'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required String step,
    required String title,
    required String description,
    required Widget action,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.surfaceContainerHighest.withValues(alpha: .8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF0088CC).withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0088CC),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.onSurface.withValues(alpha: .75),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          action,
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
