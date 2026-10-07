import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_formatters.dart';
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
  bool _testing = false;

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
          'تم إرسال Chat ID للكمبيوتر. سيبدأ البوت بالعمل فوراً.',
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
        showAppSnack(context, 'تم فحص الاتصال: الكمبيوتر متصل ويرسل لـ Telegram.');
      } else {
        showAppSnack(context, 'الكمبيوتر استلم الأمر وجاري معالجته.');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, 'فشل إرسال الفحص: $e', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deviceName = widget.device?.name ?? widget.deviceName ?? widget.deviceId;
    final isLinked = widget.device?.isTelegramLinked == true;

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
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [const Color(0xFF0284C7), cs.primary],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0284C7).withValues(alpha: .22),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .20),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.afterPairing
                                ? 'خطوة أخيرة: ربط Telegram'
                                : 'ربط بوت Telegram',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'الجهاز: $deviceName',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'اربط محادثة Telegram لتصلك تنبيهات الكمبيوتر الفورية، وإمكانية إرسال الأوامر والتقاط الشاشة مباشرة من تليجرام.',
                  style: TextStyle(color: Colors.white, height: 1.5, fontSize: 13.5),
                ),
              ],
            ),
          ),
          if (isLinked) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: .30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Telegram مربوط حالياً بهذا الجهاز',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'معرّف المحادثة: ${widget.device?.telegramChatId ?? 'مفعّل'}'
                          '${widget.device?.telegramLinkedAt != null ? ' • منذ ${AppFormatters.dateTime(widget.device!.telegramLinkedAt!)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _StepCard(
            stepNumber: '1',
            title: 'افتح بوت Telegram الرسمي',
            description: 'اضغط على الزر لفتح البوت مباشرة في تطبيق Telegram، ثم اضغط على زر Start.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '@${TelegramSetupScreen.botUsername}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ الرابط',
                        onPressed: _copyLink,
                        icon: const Icon(Icons.copy_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openBot,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('فتح في Telegram'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _copyLink,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('نسخ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StepCard(
            stepNumber: '2',
            title: 'انسخ الـ Chat ID من البوت',
            description: 'عند الضغط على Start أو إرسال أي رسالة للبوت، سيرد عليك فوراً برقم المعرف (Chat ID). انسخه بالكامل.',
          ),
          const SizedBox(height: 12),
          _StepCard(
            stepNumber: '3',
            title: 'الصق المعرف واحفظ الربط',
            description: 'الصق الرقم هنا واضغط "حفظ وربط مع الكمبيوتر" لإرساله للكمبيوتر وتفعيل البوت.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _chatIdController,
                  textDirection: TextDirection.ltr,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  decoration: InputDecoration(
                    labelText: 'Telegram Chat ID',
                    hintText: 'مثال: 123456789 أو -100123456789',
                    prefixIcon: const Icon(Icons.numbers_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'لصق من الحافظة',
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('لصق من الحافظة'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sending ? null : _saveChatId,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bolt_rounded),
                  label: Text(
                    _sending ? 'جاري الربط مع الكمبيوتر...' : '⚡ حفظ وإرسال للكمبيوتر',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
                if (isLinked) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _testing ? null : _sendTestAlert,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('إرسال فحص اتصال تجريبي للكمبيوتر وTelegram'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            color: cs.surfaceContainerHighest.withValues(alpha: .5),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يتم تخزين معرف المحادثة بأمان على الكمبيوتر فقط. بمجرد الربط، يمكنك كتابة status أو screenshot أو emergency أو lock داخل تليجرام للتحكم مباشرة.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.stepNumber,
    required this.title,
    required this.description,
    this.child,
  });

  final String stepNumber;
  final String title;
  final String description;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    stepNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
            if (child != null) ...[
              const SizedBox(height: 14),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}
