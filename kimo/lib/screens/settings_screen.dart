import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_environment.dart';
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

  static const String botUrl = 'https://t.me/tamkontrolkimidev_bot';
  static const String botUsername = 'tamkontrolkimidev_bot';

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
                        'تخصيص التحكم المباشر وتكامل Telegram واختصارات الكمبيوتر',
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

          // 2. Telegram Bot Integration
          _SettingsSection(
            title: 'تكامل Telegram الذكي',
            icon: Icons.send_rounded,
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
                title: const Text('بوت التحكم الرسمي'),
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
              const SizedBox(height: 8),
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
                      'كيف يعمل ربط Telegram؟',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '1. افتح البوت في تيليجرام واضغط Start.\n'
                      '2. يعطيك البوت معرّف Chat ID خاص بك.\n'
                      '3. الصق الـ Chat ID في شاشة تفاصيل الجهاز لربطه بالكمبيوتر فوراً.',
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
            color: const Color(0xFF16A34A),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('حالة Firebase'),
                subtitle: Text(AppEnvironment.useFirebase
                    ? 'متصل بالسحابة (Firebase Production)'
                    : 'وضع التجربة المحلي (Mock / Demo Mode)'),
                trailing: StatusBadge(
                  label: AppEnvironment.useFirebase ? 'Firebase' : 'Demo',
                  color: AppEnvironment.useFirebase
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFF59E0B),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('معرف المستخدم الحالي'),
                subtitle: Text(AppEnvironment.demoUserId),
                trailing: IconButton(
                  tooltip: 'نسخ المعرف',
                  onPressed: () => _copyText(
                    AppEnvironment.demoUserId,
                    'تم نسخ معرف المستخدم.',
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 20),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_outlined),
                title: const Text('إصدار التطبيق'),
                subtitle: const Text('KIOM Mobile v1.5.0 • متوافق مع PC Agent v1.0.0+'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5. Security Notice
          Card(
            color: cs.errorContainer.withValues(alpha: .20),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: cs.error, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'تنبيه أمان: استخدم تطبيق KIOM فقط لإدارة أجهزتك الخاصة أو الأجهزة التي لديك إذن واضح لإدارتها.',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  keys,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
