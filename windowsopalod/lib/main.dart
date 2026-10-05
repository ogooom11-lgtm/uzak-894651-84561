import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'core/agent_app.dart';
import 'services/startup_task_service.dart';
import 'utils/json_file_store.dart';

late final KiomPcAgentApp _agentApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(_writeStartupLog(details.exception, details.stack));
  };

  await runZonedGuarded<Future<void>>(
    () async {
      _agentApp = KiomPcAgentApp();
      await _agentApp.start();

      runApp(const KiomHiddenAgentShell());
    },
    (Object error, StackTrace stack) {
      unawaited(_writeStartupLog(error, stack));
    },
  );
}

Future<void> _writeStartupLog(Object error, StackTrace? stack) async {
  try {
    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
    final dir = Directory('$appData\\KiomPcAgent\\logs');
    await dir.create(recursive: true);

    final file = File('${dir.path}\\startup.log');
    await file.writeAsString(
      '[${DateTime.now().toIso8601String()}]\n'
      'ERROR: $error\n'
      'STACK:\n${stack ?? ''}\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // لا نرمي خطأ جديد هنا حتى لا يغلق التطبيق بسبب فشل كتابة السجل.
  }
}

class KiomHiddenAgentShell extends StatelessWidget {
  const KiomHiddenAgentShell({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: _AgentHomePage(),
      ),
    );
  }
}

class _AgentHomePage extends StatefulWidget {
  const _AgentHomePage();

  @override
  State<_AgentHomePage> createState() => _AgentHomePageState();
}

class _AgentHomePageState extends State<_AgentHomePage> {
  bool _busy = false;
  String _status = 'جاهز';

  Future<void> _writeTrigger(String fileName, String doneMessage) async {
    setState(() {
      _busy = true;
      _status = 'جاري التنفيذ...';
    });
    try {
      final store = await JsonFileStore.open();
      final file = File('${store.dir.path}\\$fileName');
      await file.writeAsString(DateTime.now().toIso8601String(), flush: true);
      setState(() => _status = doneMessage);
    } catch (e) {
      setState(() => _status = 'تعذر التنفيذ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installStartupTask() async {
    setState(() {
      _busy = true;
      _status = 'سيظهر طلب مسؤول من Windows...';
    });
    try {
      final store = await JsonFileStore.open();
      await StartupTaskService(store: store).requestInstallForAllUsers();
      setState(() => _status = 'تم إرسال طلب تثبيت التشغيل مع Windows.');
    } catch (e) {
      setState(() => _status = 'تعذر طلب التشغيل التلقائي: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          const Icon(Icons.desktop_windows_rounded, size: 34),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KIOM PC Agent',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(_status),
                        ],
                      ),
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _writeTrigger(
                                    'show_permissions_now.txt',
                                    'تم طلب فتح الأذونات.',
                                  ),
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          label: const Text('الأذونات'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _busy
                              ? null
                              : () => _writeTrigger(
                                    'show_qr_now.txt',
                                    'تم طلب إظهار رمز الربط.',
                                  ),
                          icon: const Icon(Icons.qr_code_2_outlined),
                          label: const Text('رمز الربط'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _installStartupTask,
                          icon: const Icon(Icons.start_outlined),
                          label: const Text('تشغيل مع Windows'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
