import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pc_device.dart';
import '../services/lan_device_client.dart';
import '../services/lan_discovery_service.dart';
import '../widgets/app_snack.dart';
import 'live_screen_screen.dart';

class RemoteInputScreen extends StatefulWidget {
  const RemoteInputScreen({
    super.key,
    required this.device,
    this.initialIp,
    this.initialPort = 42424,
  });

  final PcDevice device;
  final String? initialIp;
  final int initialPort;

  @override
  State<RemoteInputScreen> createState() => _RemoteInputScreenState();
}

class _RemoteInputScreenState extends State<RemoteInputScreen> {
  LanDeviceClient? _client;
  StreamSubscription? _stateSub;
  StreamSubscription? _latencySub;
  StreamSubscription? _discoverySub;

  LanConnectionState _connectionState = LanConnectionState.disconnected;
  int _latencyMs = 0;
  double _sensitivity = 1.3;
  bool _isDragLocked = false;
  bool _showFnKeys = false;

  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  Offset? _lastPanPos;
  DateTime? _lastTapTime;
  int _tapCount = 0;

  String? _effectiveIp;
  int _effectivePort = 42424;

  @override
  void initState() {
    super.initState();
    _effectiveIp = widget.initialIp ?? widget.device.lanIp;
    _effectivePort = widget.initialPort;

    _initLanConnection();
    _listenToDiscovery();
  }

  void _initLanConnection() {
    // If no IP yet, check discovery service
    if (_effectiveIp == null || _effectiveIp!.isEmpty) {
      final info = LanDiscoveryService.instance.getDevice(widget.device.id);
      if (info != null) {
        _effectiveIp = info.ip;
        _effectivePort = info.httpPort;
      }
    }

    if (_effectiveIp != null && _effectiveIp!.isNotEmpty) {
      _connectClient(_effectiveIp!, _effectivePort);
    }
  }

  void _listenToDiscovery() {
    _discoverySub = LanDiscoveryService.instance.stream.listen((devices) {
      if (_client == null || _connectionState != LanConnectionState.connected) {
        final info = devices[widget.device.id];
        if (info != null && info.ip != _effectiveIp) {
          setState(() {
            _effectiveIp = info.ip;
            _effectivePort = info.httpPort;
          });
          _connectClient(info.ip, info.httpPort);
        }
      }
    });
  }

  void _connectClient(String ip, int port) {
    _stateSub?.cancel();
    _latencySub?.cancel();
    _client?.dispose();

    _client = LanDeviceClient(host: ip, port: port);

    _stateSub = _client!.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
        });
      }
    });

    _latencySub = _client!.latencyStream.listen((latency) {
      if (mounted) {
        setState(() {
          _latencyMs = latency;
        });
      }
    });

    _client!.connect();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _latencySub?.cancel();
    _discoverySub?.cancel();
    _client?.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  void _sendHaptic() {
    HapticFeedback.selectionClick();
  }

  // Mouse gestures
  void _onPanStart(DragStartDetails details) {
    _lastPanPos = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_lastPanPos == null || _client == null) return;
    final dx = details.localPosition.dx - _lastPanPos!.dx;
    final dy = details.localPosition.dy - _lastPanPos!.dy;
    _lastPanPos = details.localPosition;

    _client!.sendMouseMove(dx, dy, sensitivity: _sensitivity);
  }

  void _onPanEnd(DragEndDetails details) {
    _lastPanPos = null;
  }

  void _onTap() {
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 280) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }
    _lastTapTime = now;

    _sendHaptic();
    if (_tapCount == 2) {
      _client?.sendMouseClick('left', isDouble: true);
      _tapCount = 0;
    } else {
      Future.delayed(const Duration(milliseconds: 290), () {
        if (_tapCount == 1) {
          _client?.sendMouseClick('left');
          _tapCount = 0;
        }
      });
    }
  }

  void _onLongPress() {
    _sendHaptic();
    _client?.sendMouseClick('right');
  }

  void _toggleDragLock() {
    _sendHaptic();
    setState(() {
      _isDragLocked = !_isDragLocked;
    });
    if (_isDragLocked) {
      _client?.sendMouseDown('left');
      showAppSnack(context, 'تم تفعيل تثبيت السحب (Drag Lock)');
    } else {
      _client?.sendMouseUp('left');
      showAppSnack(context, 'تم تحرير السحب');
    }
  }

  void _sendTypedText() {
    final text = _textController.text;
    if (text.isEmpty || _client == null) return;
    _client!.sendKeyType(text);
    _textController.clear();
    _sendHaptic();
  }

  Future<void> _showManualIpDialog() async {
    final controller = TextEditingController(text: _effectiveIp ?? '');
    final portController = TextEditingController(text: _effectivePort.toString());

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الاتصال المباشر بالـ IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل عنوان IP المحلي الخاص بالكمبيوتر المتصل بنفس شبكة الـ Wi-Fi:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'عنوان IP (مثال: 192.168.1.15)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi_rounded),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: 'المنفذ (Port)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('اتصال مباشر'),
          ),
        ],
      ),
    );

    if (res == true && controller.text.trim().isNotEmpty) {
      final ip = controller.text.trim();
      final port = int.tryParse(portController.text.trim()) ?? 42424;
      setState(() {
        _effectiveIp = ip;
        _effectivePort = port;
      });
      _connectClient(ip, port);
    }
  }

  void _showSensitivitySheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🎛️ حساسية وسرعة مؤشر الماوس',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    '${(_sensitivity * 100).round()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: _sensitivity,
                min: 0.4,
                max: 3.0,
                divisions: 26,
                label: '${(_sensitivity * 100).round()}%',
                onChanged: (val) {
                  setSheetState(() => _sensitivity = val);
                  setState(() => _sensitivity = val);
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      setSheetState(() => _sensitivity = 0.8);
                      setState(() => _sensitivity = 0.8);
                    },
                    child: const Text('دقيق (بطيء)'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      setSheetState(() => _sensitivity = 1.3);
                      setState(() => _sensitivity = 1.3);
                    },
                    child: const Text('افتراضي'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      setSheetState(() => _sensitivity = 2.2);
                      setState(() => _sensitivity = 2.2);
                    },
                    child: const Text('سريع'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isConnected = _connectionState == LanConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.device.name, style: const TextStyle(fontSize: 16)),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? Colors.greenAccent
                        : (_connectionState == LanConnectionState.connecting
                            ? Colors.amberAccent
                            : Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isConnected
                      ? 'اتصال Wi-Fi مباشر (${_latencyMs}ms)'
                      : (_connectionState == LanConnectionState.connecting
                          ? 'جاري الاتصال بالكمبيوتر...'
                          : 'غير متصل (Wi-Fi)'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isConnected ? Colors.greenAccent : Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'بث الشاشة المباشر',
            icon: const Icon(Icons.tv_rounded, color: Colors.greenAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LiveScreenScreen(device: widget.device),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'حساسية الماوس',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showSensitivitySheet,
          ),
          IconButton(
            tooltip: 'إعداد الـ IP',
            icon: const Icon(Icons.settings_ethernet_rounded),
            onPressed: _showManualIpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Text Input Bar
          _buildTextInputBar(cs),

          // Trackpad Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // Main Touchpad Area
                  Expanded(
                    child: _buildTouchpadCanvas(cs, isConnected),
                  ),
                  const SizedBox(width: 8),
                  // Vertical Scroll Wheel
                  _buildScrollWheel(cs),
                ],
              ),
            ),
          ),

          // Mouse Buttons (Left, Middle, Right, Drag Lock)
          _buildMouseButtonsBar(cs),

          // Special Keys & Shortcuts Row
          _buildSpecialKeysBar(cs),

          // Quick Windows Shortcuts
          _buildShortcutsBar(cs),
        ],
      ),
    );
  }

  Widget _buildTextInputBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _textFocusNode,
              decoration: InputDecoration(
                hintText: 'اكتب نصاً للكتابة بالكمبيوتر فوراً...',
                hintStyle: const TextStyle(fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                  onPressed: () {
                    _sendHaptic();
                    _client?.sendKeyPress('backspace');
                  },
                ),
              ),
              onSubmitted: (_) => _sendTypedText(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            icon: const Icon(Icons.send_rounded, size: 18),
            onPressed: _sendTypedText,
            tooltip: 'إرسال النص',
          ),
        ],
      ),
    );
  }

  Widget _buildTouchpadCanvas(ColorScheme cs, bool isConnected) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDragLocked ? cs.error : cs.outlineVariant.withValues(alpha: 0.5),
          width: _isDragLocked ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onTap: _onTap,
          onLongPress: _onLongPress,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Subtle grid or background lines
              Opacity(
                opacity: 0.08,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TrackpadGridPainter(cs.onSurface),
                ),
              ),
              if (!isConnected)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 40, color: cs.error.withValues(alpha: 0.7)),
                    const SizedBox(height: 8),
                    const Text(
                      'جاري البحث عن الكمبيوتر في نفس الشبكة...',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _showManualIpDialog,
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: const Text('إدخال IP يدوياً', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isDragLocked ? Icons.pan_tool_rounded : Icons.touch_app_rounded,
                      size: 32,
                      color: _isDragLocked ? cs.error : cs.primary.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isDragLocked ? '🔒 وضع تثبيت السحب مفعّل' : 'لوحة اللمس (Trackpad)',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isDragLocked ? cs.error : cs.onSurfaceVariant.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollWheel(ColorScheme cs) {
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          final dy = details.primaryDelta ?? 0;
          if (dy.abs() > 2) {
            _client?.sendMouseScroll(dy > 0 ? -1 : 1);
            _sendHaptic();
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              onPressed: () {
                _sendHaptic();
                _client?.sendMouseScroll(2);
              },
            ),
            RotatedBox(
              quarterTurns: 3,
              child: Text(
                'عجلة التمرير',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              onPressed: () {
                _sendHaptic();
                _client?.sendMouseScroll(-2);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMouseButtonsBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Left Click
          Expanded(
            flex: 3,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                _sendHaptic();
                _client?.sendMouseClick('left');
              },
              child: const Text('أيسر (Left)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 6),
          // Middle Click
          Expanded(
            flex: 2,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                _sendHaptic();
                _client?.sendMouseClick('middle');
              },
              child: const Text('أوسط', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          // Drag Lock
          IconButton.filledTonal(
            tooltip: 'تثبيت السحب',
            style: IconButton.styleFrom(
              backgroundColor: _isDragLocked ? cs.errorContainer : null,
              foregroundColor: _isDragLocked ? cs.onErrorContainer : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.all(12),
            ),
            icon: Icon(_isDragLocked ? Icons.lock_rounded : Icons.lock_open_rounded),
            onPressed: _toggleDragLock,
          ),
          const SizedBox(width: 6),
          // Right Click
          Expanded(
            flex: 3,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                _sendHaptic();
                _client?.sendMouseClick('right');
              },
              child: const Text('أيمن (Right)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialKeysBar(ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _keyBtn('Esc', 'escape', cs),
          _keyBtn('Tab', 'tab', cs),
          _keyBtn('⊞ Win', 'win', cs),
          _keyBtn('Ctrl', 'ctrl', cs),
          _keyBtn('Alt', 'alt', cs),
          _keyBtn('Shift', 'shift', cs),
          _keyBtn('Del', 'delete', cs),
          _keyBtn('Enter ↵', 'enter', cs, isPrimary: true),
          _keyBtn('Space', 'space', cs),
          _keyBtn('←', 'left', cs),
          _keyBtn('↑', 'up', cs),
          _keyBtn('↓', 'down', cs),
          _keyBtn('→', 'right', cs),
          IconButton(
            tooltip: 'أزرار F1-F12',
            icon: Icon(_showFnKeys ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            onPressed: () {
              setState(() => _showFnKeys = !_showFnKeys);
            },
          ),
        ],
      ),
    );
  }

  Widget _keyBtn(String label, String key, ColorScheme cs, {bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(40, 36),
          backgroundColor: isPrimary ? cs.primaryContainer : cs.surface,
          foregroundColor: isPrimary ? cs.onPrimaryContainer : cs.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          _sendHaptic();
          _client?.sendKeyPress(key);
        },
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildShortcutsBar(ColorScheme cs) {
    return Column(
      children: [
        if (_showFnKeys)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: List.generate(12, (index) {
                final f = 'f${index + 1}';
                return _keyBtn('F${index + 1}', f, cs);
              }),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _comboChip('📋 نسخ', ['ctrl', 'c'], cs),
              _comboChip('📑 لصق', ['ctrl', 'v'], cs),
              _comboChip('↩️ تراجع', ['ctrl', 'z'], cs),
              _comboChip('💾 حفظ', ['ctrl', 's'], cs),
              _comboChip('🔲 تحديد الكل', ['ctrl', 'a'], cs),
              _comboChip('🔄 تبديل النوافذ', ['alt', 'tab'], cs),
              _comboChip('🖥️ سطح المكتب', ['win', 'd'], cs),
              _comboChip('🔒 قفل الشاشة', ['win', 'l'], cs),
              _comboChip('❌ إغلاق النافذة', ['alt', 'f4'], cs),
              _comboChip('📊 مدير المهام', ['ctrl', 'shift', 'escape'], cs),
              _keyChip('🔇 كتم الصوت', 'volume_mute', cs),
              _keyChip('🔊 رفع الصوت', 'volume_up', cs),
              _keyChip('🔉 خفض الصوت', 'volume_down', cs),
              _keyChip('⏯️ تشغيل/إيقاف', 'media_play_pause', cs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _comboChip(String label, List<String> keys, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onPressed: () {
          _sendHaptic();
          _client?.sendKeyCombo(keys);
        },
      ),
    );
  }

  Widget _keyChip(String label, String key, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onPressed: () {
          _sendHaptic();
          _client?.sendKeyPress(key);
        },
      ),
    );
  }
}

class _TrackpadGridPainter extends CustomPainter {
  _TrackpadGridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
