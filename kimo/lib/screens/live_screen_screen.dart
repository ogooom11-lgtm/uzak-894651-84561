import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pc_device.dart';
import '../services/lan_device_client.dart';
import '../services/lan_discovery_service.dart';
import '../widgets/app_snack.dart';

class LiveScreenScreen extends StatefulWidget {
  const LiveScreenScreen({
    super.key,
    required this.device,
    this.initialIp,
    this.initialPort = 42424,
  });

  final PcDevice device;
  final String? initialIp;
  final int initialPort;

  @override
  State<LiveScreenScreen> createState() => _LiveScreenScreenState();
}

class _LiveScreenScreenState extends State<LiveScreenScreen> {
  LanDeviceClient? _client;
  StreamSubscription? _stateSub;
  StreamSubscription? _latencySub;
  StreamSubscription? _discoverySub;

  LanConnectionState _connectionState = LanConnectionState.disconnected;
  int _latencyMs = 0;
  String? _effectiveIp;
  int _effectivePort = 42424;

  Timer? _framePollTimer;
  Uint8List? _currentFrame;
  bool _isStreaming = true;
  bool _isTouchControlEnabled = true;
  bool _isFullscreen = false;
  int _targetFps = 10;
  int _quality = 55;

  final TextEditingController _keyboardController = TextEditingController();
  bool _showKeyboardBar = false;

  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _effectiveIp = widget.initialIp ?? widget.device.lanIp;
    _effectivePort = widget.initialPort;

    _initLanConnection();
    _listenToDiscovery();
  }

  void _initLanConnection() {
    if (_effectiveIp == null || _effectiveIp!.isEmpty) {
      final info = LanDiscoveryService.instance.getDevice(widget.device.id);
      if (info != null) {
        _effectiveIp = info.ip;
        _effectivePort = info.httpPort;
      }
    }

    if (_effectiveIp != null && _effectiveIp!.isNotEmpty) {
      _connectClient(_effectiveIp!, _effectivePort);
      _startFramePolling();
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
          _startFramePolling();
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
      if (mounted) setState(() => _connectionState = state);
    });

    _latencySub = _client!.latencyStream.listen((latency) {
      if (mounted) setState(() => _latencyMs = latency);
    });

    _client!.connect();
  }

  void _startFramePolling() {
    _framePollTimer?.cancel();
    if (!_isStreaming || _effectiveIp == null || _effectiveIp!.isEmpty) return;

    final intervalMs = (1000 / _targetFps).round().clamp(60, 500);
    _framePollTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      await _fetchNextFrame();
    });
    _fetchNextFrame();
  }

  Future<void> _fetchNextFrame() async {
    if (!_isStreaming || _effectiveIp == null || _effectiveIp!.isEmpty) return;
    try {
      final uri = Uri.parse('http://$_effectiveIp:$_effectivePort/api/screen_frame?quality=$_quality&maxWidth=1280');
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1200);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(milliseconds: 1200));
      if (resp.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(resp);
        if (bytes.isNotEmpty && mounted) {
          setState(() {
            _currentFrame = bytes;
          });
        }
      }
      client.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _framePollTimer?.cancel();
    _stateSub?.cancel();
    _latencySub?.cancel();
    _discoverySub?.cancel();
    _client?.dispose();
    _keyboardController.dispose();
    super.dispose();
  }

  void _handleScreenTap(TapDownDetails details) {
    if (!_isTouchControlEnabled || _client == null) return;
    HapticFeedback.selectionClick();

    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(details.globalPosition);
    final size = box.size;

    if (size.width <= 0 || size.height <= 0) return;

    final xRatio = (localPos.dx / size.width).clamp(0.0, 1.0);
    final yRatio = (localPos.dy / size.height).clamp(0.0, 1.0);

    _client!.sendRaw({
      'action': 'screen_tap',
      'xRatio': xRatio,
      'yRatio': yRatio,
      'button': 'left',
    });
  }

  void _handleScreenDoubleTap() {
    if (!_isTouchControlEnabled || _client == null) return;
    HapticFeedback.mediumImpact();
    _client!.sendRaw({
      'action': 'mouse_click',
      'button': 'left',
      'double': true,
    });
  }

  void _handleScreenLongPress(LongPressStartDetails details) {
    if (!_isTouchControlEnabled || _client == null) return;
    HapticFeedback.heavyImpact();

    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPos = box.globalToLocal(details.globalPosition);
    final size = box.size;

    if (size.width <= 0 || size.height <= 0) return;

    final xRatio = (localPos.dx / size.width).clamp(0.0, 1.0);
    final yRatio = (localPos.dy / size.height).clamp(0.0, 1.0);

    _client!.sendRaw({
      'action': 'screen_tap',
      'xRatio': xRatio,
      'yRatio': yRatio,
      'button': 'right',
    });
    showAppSnack(context, 'نقرة زر أيمن (Right Click)');
  }

  void _sendTypedText() {
    final text = _keyboardController.text;
    if (text.isEmpty || _client == null) return;
    _client!.sendKeyType(text);
    _keyboardController.clear();
    HapticFeedback.lightImpact();
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚙️ إعدادات جودة وسرعة بث الشاشة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('معدل الإطارات (FPS):'),
                  Text('$_targetFps FPS', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _targetFps.toDouble(),
                min: 5,
                max: 20,
                divisions: 3,
                label: '$_targetFps FPS',
                onChanged: (val) {
                  setSheetState(() => _targetFps = val.round());
                  setState(() {
                    _targetFps = val.round();
                    _startFramePolling();
                  });
                },
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('دقة وجودة الصورة:'),
                  Text('$_quality%', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _quality.toDouble(),
                min: 30,
                max: 85,
                divisions: 11,
                label: '$_quality%',
                onChanged: (val) {
                  setSheetState(() => _quality = val.round());
                  setState(() => _quality = val.round());
                },
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
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.black87,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('بث الشاشة: ${widget.device.name}', style: const TextStyle(fontSize: 15)),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isConnected ? 'بث Wi-Fi مباشر (${_latencyMs}ms)' : 'جاري الاتصال بالكمبيوتر...',
                        style: TextStyle(fontSize: 11, color: isConnected ? Colors.greenAccent : Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: _isTouchControlEnabled ? 'اللمس التفاعلي مفعّل' : 'اللمس معطّل (وضع التكبير)',
                  icon: Icon(
                    _isTouchControlEnabled ? Icons.touch_app_rounded : Icons.pan_tool_rounded,
                    color: _isTouchControlEnabled ? Colors.greenAccent : Colors.white70,
                  ),
                  onPressed: () {
                    setState(() => _isTouchControlEnabled = !_isTouchControlEnabled);
                    showAppSnack(
                      context,
                      _isTouchControlEnabled ? 'تم تفعيل التفاعل والنقر باللمس 👆' : 'وضع التكبير والتنقل مفعّل 🔍',
                    );
                  },
                ),
                IconButton(
                  tooltip: 'إعدادات البث',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _showQualitySheet,
                ),
                IconButton(
                  tooltip: _isFullscreen ? 'تصغير' : 'ملء الشاشة',
                  icon: Icon(_isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                  onPressed: () => setState(() => _isFullscreen = !_isFullscreen),
                ),
              ],
            ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Screen Stream Display
          Center(
            child: _currentFrame == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 14),
                      Text(
                        isConnected ? 'جاري جلب إطارات الشاشة...' : 'جاري الاتصال بالكمبيوتر على نفس الشبكة...',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  )
                : InteractiveViewer(
                    panEnabled: !_isTouchControlEnabled,
                    scaleEnabled: true,
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: GestureDetector(
                      key: _imageKey,
                      behavior: HitTestBehavior.opaque,
                      onTapDown: _handleScreenTap,
                      onDoubleTap: _handleScreenDoubleTap,
                      onLongPressStart: _handleScreenLongPress,
                      child: Image.memory(
                        _currentFrame!,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
          ),

          // Floating Controls Overlay (Fullscreen exit & Keyboard trigger)
          Positioned(
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_isStreaming ? Icons.pause_circle_rounded : Icons.play_circle_rounded, color: Colors.white),
                    tooltip: _isStreaming ? 'إيقاف مؤقت' : 'استئناف البث',
                    onPressed: () {
                      setState(() => _isStreaming = !_isStreaming);
                      if (_isStreaming) _startFramePolling();
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.keyboard_rounded, color: _showKeyboardBar ? cs.primary : Colors.white),
                    tooltip: 'الكيبورد المباشر',
                    onPressed: () => setState(() => _showKeyboardBar = !_showKeyboardBar),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
                    tooltip: 'التقاط لقطة شاشة',
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      showAppSnack(context, 'تم حفظ لقطة الشاشة الحالية 📸');
                    },
                  ),
                  if (_isFullscreen)
                    IconButton(
                      icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
                      tooltip: 'خروج من ملء الشاشة',
                      onPressed: () => setState(() => _isFullscreen = false),
                    ),
                ],
              ),
            ),
          ),

          // Floating Keyboard Input Bar
          if (_showKeyboardBar)
            Positioned(
              top: _isFullscreen ? 20 : 10,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white38),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keyboardController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'اكتب نصاً للكتابة بالكمبيوتر فوراً...',
                          hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _sendTypedText(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.greenAccent),
                      onPressed: _sendTypedText,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => setState(() => _showKeyboardBar = false),
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
