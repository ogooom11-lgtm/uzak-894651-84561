import 'dart:ffi' as ffi;
import 'dart:io';

// Native Win32 function signatures for process priority
typedef _GetCurrentProcessC = ffi.IntPtr Function();
typedef _GetCurrentProcessDart = int Function();

typedef _SetPriorityClassC = ffi.Int32 Function(ffi.IntPtr hProcess, ffi.Uint32 dwPriorityClass);
typedef _SetPriorityClassDart = int Function(int hProcess, int dwPriorityClass);

typedef _GetCurrentThreadC = ffi.IntPtr Function();
typedef _GetCurrentThreadDart = int Function();

typedef _SetThreadPriorityC = ffi.Int32 Function(ffi.IntPtr hThread, ffi.Int32 nPriority);
typedef _SetThreadPriorityDart = int Function(int hThread, int nPriority);

class ProcessPriorityService {
  ProcessPriorityService._();

  static final ProcessPriorityService instance = ProcessPriorityService._();

  // Priority Class Constants
  static const int normalPriorityClass = 0x00000020;
  static const int aboveNormalPriorityClass = 0x00008000;
  static const int highPriorityClass = 0x00000080;
  static const int realtimePriorityClass = 0x00000100;

  // Thread Priority Constants
  static const int threadPriorityHighest = 2;
  static const int threadPriorityTimeCritical = 15;

  bool _elevated = false;

  /// Elevate current agent process to High Priority Class in Windows Scheduler
  Future<bool> elevateToHighPriority() async {
    if (!Platform.isWindows) return false;
    try {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');

      final getCurrentProcess = kernel32
          .lookupFunction<_GetCurrentProcessC, _GetCurrentProcessDart>('GetCurrentProcess');
      final setPriorityClass = kernel32
          .lookupFunction<_SetPriorityClassC, _SetPriorityClassDart>('SetPriorityClass');
      final getCurrentThread = kernel32
          .lookupFunction<_GetCurrentThreadC, _GetCurrentThreadDart>('GetCurrentThread');
      final setThreadPriority = kernel32
          .lookupFunction<_SetThreadPriorityC, _SetThreadPriorityDart>('SetThreadPriority');

      final hProcess = getCurrentProcess();
      // Try High Priority Class first
      final success = setPriorityClass(hProcess, highPriorityClass);

      final hThread = getCurrentThread();
      setThreadPriority(hThread, threadPriorityHighest);

      _elevated = success != 0;
      return _elevated;
    } catch (e) {
      // Fallback via PowerShell
      return _elevateViaPowerShell();
    }
  }

  Future<bool> _elevateViaPowerShell() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High',
        ],
        runInShell: false,
      );
      _elevated = result.exitCode == 0;
      return _elevated;
    } catch (_) {
      return false;
    }
  }

  bool get isElevated => _elevated;
}
