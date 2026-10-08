import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_environment.dart';
import '../repositories/device_repository.dart';
import '../repositories/telegram_device_repository.dart';
import '../widgets/app_snack.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _directMode = true;
  bool _hapticFeedback = true;
  int _timeoutSeconds = 10;
  String _themePreference = 'system';
  late final TextEditingController _botTokenController;
  late final TextEditingController _chatIdController;
  bool _isSavingTelegramConfig = false;

  static const String botUrl = 'https://t.me/tamkontrolkimidev_bot';
  static const String botUsername = 'tamkontrolkimidev_bot';

  @override
  void initState() {
    super.initState();
    _botTokenController =
        TextEditingController(text: AppEnvironment.defaultTelegramBotToken);
    _chatIdController =
        TextEditingController(text: AppEnvironment.defaultTelegramChatId);
    _loadSavedCloudConfig();
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCloudConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('telegram_cloud_bot_token');
    final savedChat = prefs.getString('telegram_cloud_chat_id');
    if (savedToken != null && savedToken.trim().isNotEmpty) {
      _botTokenController.text = savedToken.trim();
    }
    if (savedChat != null && savedChat.trim().isNotEmpty) {
      _chatIdController.text = savedChat.trim();
    }
  }

  Future<void> _saveTelegramCloudConfig() async {
    final token = _botTokenController.text.trim();
    final chat = _chatIdController.text.trim();
    if (token.isEmpty) {
      showAppSnack(context, 'يرجى إدخال Bot Token الخاص بقاعدة البيانات.', error: true);
      return;
    }
    setState(() => _isSavingTelegramConfig = true);
    try {
      final repo = context.read<DeviceRepository>();
      if (repo is TelegramDeviceRepository) {
        await repo.updateConfig(token: token, chat: chat);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('telegram_cloud_bot_token', token);
      await prefs.setString('telegram_cloud_chat_id', chat);
      if (mounted) {
        showAppSnack(context, '✅ تم حفظ وضبط سحابة Telegram كقاعدة بيانات بنجاح!');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, 'فشل حفظ الإعدادات: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSavingTelegramConfig = false);
    }
  }

  Future<void> _openBot() async {
    final uri = Uri.parse(botUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      await Clipboard.setData(const ClipboardData(text: botUrl));
      showAppSnack(context, 'تم نسخ رابط بوت Telegram.');
    }
  }

  Future<void> _copyText(String text, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppSnack(context, successMessage);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات والتوافق'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [cs.primary, cs.tertiary],
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: .20),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .20),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إعدادات KIOM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'تخصيص سحابة Telegram وقاعدة البيانات والتحكم المباشر',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 1. Control & Direct Execution Settings
          _SettingsSection(
            title: 'التحكم المباشر والأوامر',
            icon: Icons.touch_app_rounded,
            color: cs.primary,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _directMode,
                onChanged: (val) {
                  setState(() => _directMode = val);
                  showAppSnack(
                    context,
                    val
                        ? 'تم تفعيل وضع الضغط المباشر (تنفيذ فوري بدون نوافذ تأكيد).'
                        : 'تم تعطيل وضع الضغط المباشر.',
                  );
                },
                title: const Text('وضع الضغط المباشر (بدون تأكيد)'),
                subtitle: const Text(
                  'تنفيذ أوامر القفل، الحذف، الإغلاق فوراً وبأقصى سرعة استجابة بضغطة واحدة.',
                ),
              ),
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _hapticFeedback,
                onChanged: (val) => setState(() => _hapticFeedback = val),
                title: const Text('الاهتزاز التفاعلي عند إرسال الأوامر'),
                subtitle: const Text('اهتزاز خفيف بالهاتف عند الضغط على أي إجراء.'),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('مهلة انتظار استجابة الكمبيوتر'),
                subtitle: Text('$_timeoutSeconds ثوانٍ قبل اعتبار الأمر معلقاً'),
                trailing: DropdownButton<int>(
                  value: _timeoutSeconds,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5 ثوانٍ')),
                    DropdownMenuItem(value: 10, child: Text('10 ثوانٍ')),
                    DropdownMenuItem(value: 15, child: Text('15 ثانية')),
                    DropdownMenuItem(value: 30, child: Text('30 ثانية')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _timeoutSeconds = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Telegram Bot Integration & Cloud Database
          _SettingsSection(
            title: 'قاعدة بيانات Telegram السحابية (Cloud Database)',
            icon: Icons.cloud_sync_rounded,
            color: const Color(0xFF0284C7),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.smart_toy_rounded, color: Color(0xFF0284C7)),
                ),
                title: const Text('بوت السحابة والتحكم'),
                subtitle: const Text('@$botUsername'),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'فتح البوت',
                      onPressed: _openBot,
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                    IconButton(
                      tooltip: 'نسخ الرابط',
                      onPressed: () => _copyText(botUrl, 'تم نسخ رابط بوت Telegram.'),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _botTokenController,
                decoration: InputDecoration(
                  labelText: 'Telegram Bot Token (قاعدة البيانات)',
                  hintText: '8151486801:AAF...',
                  prefixIcon: const Icon(Icons.key_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: .3),
                ),
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _chatIdController,
                decoration: InputDecoration(
                  labelText: 'Telegram Chat ID (معرف المحادثة)',
                  hintText: '123456789',
                  prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: .3),
                ),
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSavingTelegramConfig ? null : _saveTelegramCloudConfig,
                  icon: _isSavingTelegramConfig
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ وضبط سحابة Telegram كقاعدة بيانات'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'كيف تعمل قاعدة بيانات Telegram؟',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• يعمل البوت كخادم سحابي مجاني وفوري لنقل الأوامر والملفات والحالة بين الهاتف والكمبيوتر.\n'
                      '• لا حاجة لـ Firebase إطلاقاً؛ كل ما تحتاجه هو إنشاء بوت عبر BotFather أو استخدام البوت الافتراضي ولصق Chat ID الخاص بك.',
                      style: TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. PC Shortcuts & Hotkeys Guide
          _SettingsSection(
            title: 'اختصارات لوحة المفاتيح بالكمبيوتر (Agent Hotkeys)',
            icon: Icons.keyboard_rounded,
            color: const Color(0xFF7C3AED),
            children: [
              const Text(
                'يمكنك تشغيل هذه النوافذ من الكمبيوتر مباشرة بالضغط والاستمرار 3 ثوانٍ:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 10),
              _HotkeyTile(
                keys: 'Ctrl + Shift + Q + R',
                title: 'إظهار رمز QR للربط',
                description: 'يفتح نافذة QR code لمسحه من كاميرا الهاتف.',
              ),
              const SizedBox(height: 8),
              _HotkeyTile(
                keys: 'Ctrl + Shift + S + T',
                title: 'شاشة مركز الأذونات',
                description: 'إدارة أذونات WiFi والبلوتوث والتقاط الشاشة.',
              ),
              const SizedBox(height: 8),
              _HotkeyTile(
                keys: 'Ctrl + Shift + H + T',
                title: 'مركز السجلات المحلي',
                description: 'عرض السجلات المحلية ومسحها برمز الحماية 1494922.',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.folder_special_rounded, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ملفات التشغيل السريع في الكمبيوتر:\n'
                        r'%APPDATA%\KiomPcAgent\show_qr_now.txt'
                        '\n'
                        r'%APPDATA%\KiomPcAgent\show_permissions_now.txt',
                        style: TextStyle(fontSize: 11.5, height: 1.4),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4. System & Cloud Status
          _SettingsSection(
            title: 'البيئة وحالة السحابة',
            icon: Icons.cloud_done_rounded,
            color: const Color(0xFF10B981),
            children: [
              _InfoRow(title: 'نوع السحابة', value: 'Telegram Cloud Database (مباشر)'),
              const Divider(),
              _InfoRow(title: 'إصدار عميل الهاتف', value: '1.2.0'),
              const Divider(),
              _InfoRow(title: 'إصدار عميل الكمبيوتر', value: '0.1.0'),
              const Divider(),
              _InfoRow(title: 'المستخدم المحلي', value: AppEnvironment.demoUserId),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _HotkeyTile extends StatelessWidget {
  const _HotkeyTile({
    required this.keys,
    required this.title,
    required this.description,
  });

  final String keys;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  keys,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Color(0xFF7C3AED),
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(color: cs.onSurface.withValues(alpha: .7), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
