import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';

class ModesScreen extends StatelessWidget {
  const ModesScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _sendMode(
    BuildContext context, {
    required String mode,
    required String label,
  }) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: CommandType.applyPresetMode,
          payload: {'mode': mode},
        );
    if (context.mounted) showAppSnack(context, 'تم إرسال $label مباشرة.');
  }

  Future<void> _emergency(BuildContext context) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: CommandType.emergencyMode,
        );
    if (context.mounted) {
      showAppSnack(context, 'تم تفعيل وضع الطوارئ مباشرة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الأوضاع الذكية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ModeCard(
            title: 'وضع الطوارئ',
            subtitle: 'لقطة شاشة + تنبيه Telegram + قفل الكمبيوتر + إيقاف الإنترنت إن كان مسموحاً.',
            icon: Icons.emergency_rounded,
            color: cs.error,
            onTap: () => _emergency(context),
          ),
          _ModeCard(
            title: 'وضع الدراسة',
            subtitle: 'يمنع الشبكات الاجتماعية والتطبيقات المشتتة مثل الألعاب والدردشة.',
            icon: Icons.school_rounded,
            color: cs.primary,
            onTap: () => _sendMode(context, mode: 'study', label: 'وضع الدراسة'),
          ),
          _ModeCard(
            title: 'وضع العمل والتركيز',
            subtitle: 'يرتب البيئة للعمل ويمنع المواقع والتطبيقات الأكثر تشتيتاً.',
            icon: Icons.work_rounded,
            color: cs.tertiary,
            onTap: () => _sendMode(context, mode: 'work', label: 'وضع العمل'),
          ),
          _ModeCard(
            title: 'وضع الأطفال',
            subtitle: 'قيود أقوى على المواقع الاجتماعية والتطبيقات غير المناسبة.',
            icon: Icons.child_care_rounded,
            color: const Color(0xFF16A34A),
            onTap: () => _sendMode(context, mode: 'kids', label: 'وضع الأطفال'),
          ),
          _ModeCard(
            title: 'الحماية القصوى',
            subtitle: 'منع موسع للتطبيقات والمواقع الحساسة لاستخدام الجهاز بأمان.',
            icon: Icons.shield_rounded,
            color: const Color(0xFF7C3AED),
            onTap: () => _sendMode(context, mode: 'protection', label: 'الحماية القصوى'),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
