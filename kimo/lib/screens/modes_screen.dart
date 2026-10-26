import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/custom_smart_mode.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../services/custom_modes_store.dart';
import '../widgets/app_snack.dart';
import 'create_custom_mode_screen.dart';

class ModesScreen extends StatefulWidget {
  const ModesScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  @override
  State<ModesScreen> createState() => _ModesScreenState();
}

class _ModesScreenState extends State<ModesScreen> {
  List<CustomSmartMode> _modes = [];
  CustomSmartMode? _activeMode;
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadModes();
  }

  Future<void> _loadModes() async {
    final list = await CustomModesStore.instance.loadModes();
    final active = await CustomModesStore.instance.getActiveMode();
    if (mounted) {
      setState(() {
        _modes = list;
        _activeMode = active;
        _loading = false;
      });
    }
  }

  Future<void> _activateMode(CustomSmartMode mode) async {
    final repo = context.read<DeviceRepository>();

    // 1. Send Volume commands if specified
    if (mode.forceMute) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.setVolume,
        payload: {'volume': 0, 'mute': true},
      );
    } else if (mode.lockVolume || mode.maxVolume < 100) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.setVolume,
        payload: {'volume': mode.maxVolume, 'mute': false},
      );
    }

    // 2. Send Block Apps
    for (final app in mode.blockedApps) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.blockApplication,
        payload: {'target': app, 'action': 'block'},
      );
      if (mode.killBlockedAppsOnActivate) {
        await repo.sendCommand(
          userId: widget.userId,
          deviceId: widget.device.id,
          type: CommandType.closeApplication,
          payload: {'processName': app},
        );
      }
    }

    // 3. Send Block Sites
    for (final site in mode.blockedSites) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.blockWebsite,
        payload: {'target': site, 'domain': site, 'action': 'block'},
      );
    }

    // 4. Send Network controls if specified
    if (mode.disableInternet) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.internetOffPermanent,
        payload: {'permanent': true},
      );
    }
    if (mode.disableWifi) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.wifiOff,
        payload: {'enabled': false},
      );
    }
    if (mode.disableBluetooth) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.bluetoothOff,
        payload: {'enabled': false},
      );
    }

    // 5. Send Privacy Mode
    if (mode.enablePrivacyMode) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.privacyMode,
        payload: {'enabled': true},
      );
    }

    // 7. Apply Preset state
    await repo.sendCommand(
      userId: widget.userId,
      deviceId: widget.device.id,
      type: CommandType.applyPresetMode,
      payload: {'mode': mode.name, 'duration': mode.durationMinutes},
    );

    await CustomModesStore.instance.setActiveMode(mode.id);
    await _loadModes();

    if (mounted) {
      showAppSnack(context, '⚡ تم تفعيل "${mode.name}" بنجاح وتطبيق كافة قيوده على الكمبيوتر.');
    }
  }

  Future<void> _deactivateMode(CustomSmartMode mode) async {
    final repo = context.read<DeviceRepository>();

    // Unblock sites & apps added by this mode
    for (final site in mode.blockedSites) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.allowWebsite,
        payload: {'target': site, 'domain': site},
      );
    }
    for (final app in mode.blockedApps) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.allowApplication,
        payload: {'target': app},
      );
    }

    // Re-enable network if was disabled
    if (mode.disableInternet) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.internetOn,
        payload: {'enabled': true},
      );
    }
    if (mode.disableWifi) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.wifiOn,
        payload: {'enabled': true},
      );
    }

    if (mode.enablePrivacyMode) {
      await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.privacyMode,
        payload: {'enabled': false},
      );
    }

    await repo.sendCommand(
      userId: widget.userId,
      deviceId: widget.device.id,
      type: CommandType.applyPresetMode,
      payload: {'mode': 'default'},
    );

    await CustomModesStore.instance.setActiveMode(null);
    await _loadModes();

    if (mounted) {
      showAppSnack(context, '🔓 تم إلغاء تفعيل "${mode.name}" واستعادة حالة الكمبيوتر الطبيعية.');
    }
  }

  Future<void> _openCreateMode([CustomSmartMode? mode]) async {
    final created = await Navigator.push<CustomSmartMode>(
      context,
      MaterialPageRoute(builder: (_) => CreateCustomModeScreen(initialMode: mode)),
    );
    if (created != null) {
      await _loadModes();
    }
  }

  Future<void> _deleteMode(CustomSmartMode mode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الوضع الذكي'),
        content: Text('هل أنت متأكد من رغبتك في حذف "${mode.name}" نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mode.isActive) {
        await _deactivateMode(mode);
      }
      await CustomModesStore.instance.deleteMode(mode.id);
      await _loadModes();
      if (mounted) showAppSnack(context, 'تم حذف الوضع الذكي بنجاح.');
    }
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'school':
        return Icons.school_rounded;
      case 'work':
        return Icons.work_rounded;
      case 'child_care':
        return Icons.child_care_rounded;
      case 'games':
        return Icons.sports_esports_rounded;
      case 'volume_off':
        return Icons.volume_off_rounded;
      case 'bedtime':
        return Icons.bedtime_rounded;
      case 'lock':
        return Icons.lock_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'auto_awesome':
        return Icons.auto_awesome_rounded;
      case 'shield':
      default:
        return Icons.shield_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final filtered = _modes.where((m) {
      if (_searchQuery.isEmpty) return true;
      return m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.blockedApps.any((a) => a.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          m.blockedSites.any((s) => s.toLowerCase().contains(_searchQuery.toLowerCase()));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الأوضاع الذكية والمخصصة'),
        actions: [
          IconButton(
            tooltip: 'إنشاء وضع جديد',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _openCreateMode(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
              children: [
                // Active Mode Banner if any
                if (_activeMode != null) ...[
                  _buildActiveBanner(_activeMode!, cs),
                  const SizedBox(height: 14),
                ],

                // Hero Create Custom Mode Button
                _buildCreateHeroButton(cs),

                const SizedBox(height: 14),

                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'بحث في الأوضاع أو التطبيقات والمواقع الممنوعة...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),

                const SizedBox(height: 16),

                // Section Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'قائمة الأوضاع المتاحة (${filtered.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      'اضغط تفعيل للتطبيق الفوري',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Modes List
                ...filtered.map((mode) => _buildModeCard(mode, cs)),
              ],
            ),
    );
  }

  Widget _buildActiveBanner(CustomSmartMode active, ColorScheme cs) {
    final color = Color(int.parse(active.colorHex));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(_iconFromName(active.iconName), color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🟢 الوضع النشط حالياً:', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Text(active.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'كافة القيود والحظر وقواعد الصوت مطبقة على الكمبيوتر.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.2),
              foregroundColor: Colors.red,
            ),
            onPressed: () => _deactivateMode(active),
            child: const Text('إلغاء ✕', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateHeroButton(ColorScheme cs) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openCreateMode(),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary.withValues(alpha: 0.85), cs.tertiary.withValues(alpha: 0.95)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.2),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '➕ إنشاء وتخصيص وضع ذكي جديد',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'حدد قواعد الصوت، حظر البرامج والمواقع، والإنترنت حسب رغبتك',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard(CustomSmartMode mode, ColorScheme cs) {
    final isCurrentActive = mode.isActive;
    final color = Color(int.parse(mode.colorHex));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isCurrentActive ? color : cs.outlineVariant.withValues(alpha: 0.4),
          width: isCurrentActive ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_iconFromName(mode.iconName), color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (mode.description.isNotEmpty)
                        Text(
                          mode.description,
                          style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'edit') _openCreateMode(mode);
                    if (val == 'delete') _deleteMode(mode);
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل الوضع ✏️')),
                    PopupMenuItem(value: 'delete', child: Text('حذف الوضع 🗑️', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Feature Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (mode.forceMute)
                  _featureChip('🔇 كتم الصوت تماماً', Colors.red)
                else if (mode.lockVolume || mode.maxVolume < 100)
                  _featureChip('🔉 حد الصوت: ${mode.maxVolume}%', Colors.blue),

                if (mode.blockedApps.isNotEmpty)
                  _featureChip('🚫 ${mode.blockedApps.length} برامج ممنوعة', Colors.orange),

                if (mode.blockedSites.isNotEmpty)
                  _featureChip('🌐 ${mode.blockedSites.length} مواقع ممنوعة', Colors.amber),

                if (mode.disableInternet)
                  _featureChip('🔌 بدون إنترنت', Colors.purple),

                if (mode.blockInstallations)
                  _featureChip('🛡️ منع التثبيت', Colors.teal),

                if (mode.durationMinutes > 0)
                  _featureChip('⏳ ${mode.durationMinutes} دقيقة', Colors.indigo),
              ],
            ),

            const SizedBox(height: 12),

            // Activate / Deactivate Button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isCurrentActive)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    icon: const Icon(Icons.stop_circle_rounded, size: 18),
                    label: const Text('إلغاء التفعيل الآن ✕'),
                    onPressed: () => _deactivateMode(mode),
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('تفعيل الوضع الآن ⚡'),
                    onPressed: () => _activateMode(mode),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
