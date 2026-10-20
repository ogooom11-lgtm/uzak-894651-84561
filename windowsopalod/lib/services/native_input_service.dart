import 'dart:ffi' as ffi;
import 'dart:io';

// Win32 POINT Struct for GetCursorPos
final class POINT extends ffi.Struct {
  @ffi.Int32()
  external int x;

  @ffi.Int32()
  external int y;
}

// Native Win32 function signatures
typedef _SetCursorPosC = ffi.Int32 Function(ffi.Int32 x, ffi.Int32 y);
typedef _SetCursorPosDart = int Function(int x, int y);

typedef _GetCursorPosC = ffi.Int32 Function(ffi.Pointer<POINT> lpPoint);
typedef _GetCursorPosDart = int Function(ffi.Pointer<POINT> lpPoint);

typedef _MouseEventC = ffi.Void Function(
  ffi.Uint32 dwFlags,
  ffi.Uint32 dx,
  ffi.Uint32 dy,
  ffi.Uint32 dwData,
  ffi.IntPtr dwExtraInfo,
);
typedef _MouseEventDart = void Function(
  int dwFlags,
  int dx,
  int dy,
  int dwData,
  int dwExtraInfo,
);

typedef _KeybdEventC = ffi.Void Function(
  ffi.Uint8 bVk,
  ffi.Uint8 bScan,
  ffi.Uint32 dwFlags,
  ffi.IntPtr dwExtraInfo,
);
typedef _KeybdEventDart = void Function(
  int bVk,
  int bScan,
  int dwFlags,
  int dwExtraInfo,
);

class NativeInputService {
  NativeInputService._() {
    _initNativeLibraries();
  }

  static final NativeInputService instance = NativeInputService._();

  bool _initialized = false;
  _SetCursorPosDart? _setCursorPos;
  _GetCursorPosDart? _getCursorPos;
  _MouseEventDart? _mouseEvent;
  _KeybdEventDart? _keybdEvent;

  ffi.Pointer<POINT>? _pointPtr;

  // Mouse Flags Constants
  static const int mouseEventfMove = 0x0001;
  static const int mouseEventfLeftDown = 0x0002;
  static const int mouseEventfLeftUp = 0x0004;
  static const int mouseEventfRightDown = 0x0008;
  static const int mouseEventfRightUp = 0x0010;
  static const int mouseEventfMiddleDown = 0x0020;
  static const int mouseEventfMiddleUp = 0x0040;
  static const int mouseEventfWheel = 0x0800;
  static const int mouseEventfHWheel = 0x1000;
  static const int mouseEventfAbsolute = 0x8000;

  // Keyboard Flags Constants
  static const int keyEventfExtendedKey = 0x0001;
  static const int keyEventfKeyUp = 0x0002;
  static const int keyEventfUnicode = 0x0004;
  static const int keyEventfScancode = 0x0008;

  // Virtual Key Map
  static const Map<String, int> _vkMap = {
    'backspace': 0x08,
    'back': 0x08,
    'tab': 0x09,
    'enter': 0x0D,
    'return': 0x0D,
    'shift': 0x10,
    'shift_left': 0xA0,
    'shift_right': 0xA1,
    'ctrl': 0x11,
    'control': 0x11,
    'ctrl_left': 0xA2,
    'ctrl_right': 0xA3,
    'alt': 0x12,
    'menu': 0x12,
    'alt_left': 0xA4,
    'alt_right': 0xA5,
    'pause': 0x13,
    'caps_lock': 0x14,
    'caps': 0x14,
    'escape': 0x1B,
    'esc': 0x1B,
    'space': 0x20,
    'page_up': 0x21,
    'page_down': 0x22,
    'end': 0x23,
    'home': 0x24,
    'left': 0x25,
    'arrow_left': 0x25,
    'up': 0x26,
    'arrow_up': 0x26,
    'right': 0x27,
    'arrow_right': 0x27,
    'down': 0x28,
    'arrow_down': 0x28,
    'print_screen': 0x2C,
    'prtsc': 0x2C,
    'insert': 0x2D,
    'delete': 0x2E,
    'del': 0x2E,
    'win': 0x5B,
    'windows': 0x5B,
    'lwin': 0x5B,
    'rwin': 0x5C,
    'apps': 0x5D,
    'num0': 0x60,
    'num1': 0x61,
    'num2': 0x62,
    'num3': 0x63,
    'num4': 0x64,
    'num5': 0x65,
    'num6': 0x66,
    'num7': 0x67,
    'num8': 0x68,
    'num9': 0x69,
    'f1': 0x70,
    'f2': 0x71,
    'f3': 0x72,
    'f4': 0x73,
    'f5': 0x74,
    'f6': 0x75,
    'f7': 0x76,
    'f8': 0x77,
    'f9': 0x78,
    'f10': 0x79,
    'f11': 0x7A,
    'f12': 0x7B,
    'num_lock': 0x90,
    'scroll_lock': 0x91,
    'volume_mute': 0xAD,
    'vol_mute': 0xAD,
    'mute': 0xAD,
    'volume_down': 0xAE,
    'vol_down': 0xAE,
    'voldown': 0xAE,
    'volume_up': 0xAF,
    'vol_up': 0xAF,
    'volup': 0xAF,
    'media_next': 0xB0,
    'media_prev': 0xB1,
    'media_stop': 0xB2,
    'media_play_pause': 0xB3,
    'play_pause': 0xB3,
  };

  void _initNativeLibraries() {
    if (!Platform.isWindows) return;
    try {
      final user32 = ffi.DynamicLibrary.open('user32.dll');

      _setCursorPos = user32
          .lookupFunction<_SetCursorPosC, _SetCursorPosDart>('SetCursorPos');
      _getCursorPos = user32
          .lookupFunction<_GetCursorPosC, _GetCursorPosDart>('GetCursorPos');
      _mouseEvent = user32
          .lookupFunction<_MouseEventC, _MouseEventDart>('mouse_event');
      _keybdEvent = user32
          .lookupFunction<_KeybdEventC, _KeybdEventDart>('keybd_event');

      _pointPtr = ffi.calloc<POINT>();
      _initialized = true;
    } catch (e) {
      stderr.writeln('NativeInputService: Error loading user32.dll: $e');
    }
  }

  /// Get current mouse cursor position
  (int x, int y) getCursorPosition() {
    if (!_initialized || _getCursorPos == null || _pointPtr == null) {
      return (0, 0);
    }
    try {
      _getCursorPos!(_pointPtr!);
      return (_pointPtr!.ref.x, _pointPtr!.ref.y);
    } catch (_) {
      return (0, 0);
    }
  }

  /// Move mouse cursor relatively with acceleration support
  void moveMouseRelative(double dx, double dy, {double sensitivity = 1.0}) {
    if (!_initialized || _setCursorPos == null) return;
    try {
      final current = getCursorPosition();

      // Apply natural acceleration curve
      final dist = (dx * dx + dy * dy);
      double factor = sensitivity;
      if (dist > 100) {
        factor *= 1.35;
      } else if (dist > 400) {
        factor *= 1.7;
      }

      final moveX = (dx * factor).round();
      final moveY = (dy * factor).round();

      final newX = current.$1 + moveX;
      final newY = current.$2 + moveY;

      _setCursorPos!(newX, newY);
    } catch (e) {
      stderr.writeln('NativeInputService.moveMouseRelative error: $e');
    }
  }

  /// Move mouse cursor to absolute screen coordinates
  void moveMouseAbsolute(int x, int y) {
    if (!_initialized || _setCursorPos == null) return;
    try {
      _setCursorPos!(x, y);
    } catch (_) {}
  }

  /// Perform mouse left click
  void leftClick() {
    if (!_initialized || _mouseEvent == null) return;
    try {
      _mouseEvent!(mouseEventfLeftDown, 0, 0, 0, 0);
      _mouseEvent!(mouseEventfLeftUp, 0, 0, 0, 0);
    } catch (_) {}
  }

  /// Perform mouse double click
  void doubleClick() {
    if (!_initialized || _mouseEvent == null) return;
    try {
      _mouseEvent!(mouseEventfLeftDown, 0, 0, 0, 0);
      _mouseEvent!(mouseEventfLeftUp, 0, 0, 0, 0);
      sleep(const Duration(milliseconds: 50));
      _mouseEvent!(mouseEventfLeftDown, 0, 0, 0, 0);
      _mouseEvent!(mouseEventfLeftUp, 0, 0, 0, 0);
    } catch (_) {}
  }

  /// Perform mouse right click
  void rightClick() {
    if (!_initialized || _mouseEvent == null) return;
    try {
      _mouseEvent!(mouseEventfRightDown, 0, 0, 0, 0);
      _mouseEvent!(mouseEventfRightUp, 0, 0, 0, 0);
    } catch (_) {}
  }

  /// Perform mouse middle click
  void middleClick() {
    if (!_initialized || _mouseEvent == null) return;
    try {
      _mouseEvent!(mouseEventfMiddleDown, 0, 0, 0, 0);
      _mouseEvent!(mouseEventfMiddleUp, 0, 0, 0, 0);
    } catch (_) {}
  }

  /// Press mouse button down (for dragging)
  void mouseDown(String button) {
    if (!_initialized || _mouseEvent == null) return;
    try {
      switch (button.toLowerCase()) {
        case 'right':
          _mouseEvent!(mouseEventfRightDown, 0, 0, 0, 0);
          break;
        case 'middle':
          _mouseEvent!(mouseEventfMiddleDown, 0, 0, 0, 0);
          break;
        case 'left':
        default:
          _mouseEvent!(mouseEventfLeftDown, 0, 0, 0, 0);
          break;
      }
    } catch (_) {}
  }

  /// Release mouse button up
  void mouseUp(String button) {
    if (!_initialized || _mouseEvent == null) return;
    try {
      switch (button.toLowerCase()) {
        case 'right':
          _mouseEvent!(mouseEventfRightUp, 0, 0, 0, 0);
          break;
        case 'middle':
          _mouseEvent!(mouseEventfMiddleUp, 0, 0, 0, 0);
          break;
        case 'left':
        default:
          _mouseEvent!(mouseEventfLeftUp, 0, 0, 0, 0);
          break;
      }
    } catch (_) {}
  }

  /// Scroll mouse wheel (vertical or horizontal)
  void scrollWheel(int dy, {int dx = 0}) {
    if (!_initialized || _mouseEvent == null) return;
    try {
      if (dy != 0) {
        // Standard wheel notch is 120
        final wheelAmount = dy * 120;
        _mouseEvent!(mouseEventfWheel, 0, 0, wheelAmount, 0);
      }
      if (dx != 0) {
        final hWheelAmount = dx * 120;
        _mouseEvent!(mouseEventfHWheel, 0, 0, hWheelAmount, 0);
      }
    } catch (_) {}
  }

  /// Press a specific keyboard key
  void pressKey(String key) {
    if (!_initialized || _keybdEvent == null) return;
    final lower = key.toLowerCase().trim();
    int? vk = _vkMap[lower];

    if (vk == null) {
      if (lower.length == 1) {
        final code = lower.toUpperCase().codeUnitAt(0);
        if ((code >= 0x41 && code <= 0x5A) || (code >= 0x30 && code <= 0x39)) {
          vk = code;
        }
      }
    }

    if (vk != null) {
      _keybdEvent!(vk, 0, 0, 0);
      _keybdEvent!(vk, 0, keyEventfKeyUp, 0);
    } else {
      // Type as unicode character
      typeText(key);
    }
  }

  /// Press keyboard shortcut combination (e.g. ['ctrl', 'c'], ['alt', 'tab'], ['win', 'd'])
  void pressKeyCombo(List<String> keys) {
    if (!_initialized || _keybdEvent == null || keys.isEmpty) return;
    final vks = <int>[];
    for (final k in keys) {
      final lower = k.toLowerCase().trim();
      int? vk = _vkMap[lower];
      if (vk == null && lower.length == 1) {
        final code = lower.toUpperCase().codeUnitAt(0);
        if ((code >= 0x41 && code <= 0x5A) || (code >= 0x30 && code <= 0x39)) {
          vk = code;
        }
      }
      if (vk != null) vks.add(vk);
    }

    // Press all keys down
    for (final vk in vks) {
      _keybdEvent!(vk, 0, 0, 0);
    }

    sleep(const Duration(milliseconds: 30));

    // Release all keys up in reverse order
    for (final vk in vks.reversed) {
      _keybdEvent!(vk, 0, keyEventfKeyUp, 0);
    }
  }

  /// Type text into active window supporting any language (Arabic, English, Symbols, Emojis)
  void typeText(String text) {
    if (!_initialized || _keybdEvent == null || text.isEmpty) return;
    for (final rune in text.runes) {
      // Use KEYEVENTF_UNICODE
      _keybdEvent!(0, rune, keyEventfUnicode, 0);
      _keybdEvent!(0, rune, keyEventfUnicode | keyEventfKeyUp, 0);
    }
  }
}
