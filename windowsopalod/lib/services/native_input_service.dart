import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkg_ffi;

// Win32 POINT Struct for GetCursorPos
final class POINT extends ffi.Struct {
  @ffi.Int32()
  external int x;

  @ffi.Int32()
  external int y;
}

typedef _GetCursorPosC = ffi.Int32 Function(ffi.Pointer<POINT> lpPoint);
typedef _GetCursorPosDart = int Function(ffi.Pointer<POINT> lpPoint);

typedef _SetCursorPosC = ffi.Int32 Function(ffi.Int32 x, ffi.Int32 y);
typedef _SetCursorPosDart = int Function(int x, int y);

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
    _init();
  }

  static final NativeInputService instance = NativeInputService._();

  // Mouse event flags
  static const int MOUSEEVENTF_MOVE = 0x0001;
  static const int MOUSEEVENTF_LEFTDOWN = 0x0002;
  static const int MOUSEEVENTF_LEFTUP = 0x0004;
  static const int MOUSEEVENTF_RIGHTDOWN = 0x0008;
  static const int MOUSEEVENTF_RIGHTUP = 0x0010;
  static const int MOUSEEVENTF_MIDDLEDOWN = 0x0020;
  static const int MOUSEEVENTF_MIDDLEUP = 0x0040;
  static const int MOUSEEVENTF_WHEEL = 0x0800;
  static const int MOUSEEVENTF_ABSOLUTE = 0x8000;

  // Keyboard flags
  static const int KEYEVENTF_EXTENDEDKEY = 0x0001;
  static const int KEYEVENTF_KEYUP = 0x0002;

  // Virtual key codes
  static const int VK_BACK = 0x08;
  static const int VK_TAB = 0x09;
  static const int VK_RETURN = 0x0D;
  static const int VK_SHIFT = 0x10;
  static const int VK_CONTROL = 0x11;
  static const int VK_MENU = 0x12; // Alt
  static const int VK_PAUSE = 0x13;
  static const int VK_CAPITAL = 0x14; // Caps Lock
  static const int VK_ESCAPE = 0x1B;
  static const int VK_SPACE = 0x20;
  static const int VK_PRIOR = 0x21; // Page Up
  static const int VK_NEXT = 0x22; // Page Down
  static const int VK_END = 0x23;
  static const int VK_HOME = 0x24;
  static const int VK_LEFT = 0x25;
  static const int VK_UP = 0x26;
  static const int VK_RIGHT = 0x27;
  static const int VK_DOWN = 0x28;
  static const int VK_SNAPSHOT = 0x2C; // Print Screen
  static const int VK_INSERT = 0x2D;
  static const int VK_DELETE = 0x2E;
  static const int VK_LWIN = 0x5B; // Windows key
  static const int VK_RWIN = 0x5C;
  static const int VK_VOLUME_MUTE = 0xAD;
  static const int VK_VOLUME_DOWN = 0xAE;
  static const int VK_VOLUME_UP = 0xAF;
  static const int VK_MEDIA_NEXT_TRACK = 0xB0;
  static const int VK_MEDIA_PREV_TRACK = 0xB1;
  static const int VK_MEDIA_STOP = 0xB2;
  static const int VK_MEDIA_PLAY_PAUSE = 0xB3;

  // F1 to F12
  static const int VK_F1 = 0x70;
  static const int VK_F2 = 0x71;
  static const int VK_F3 = 0x72;
  static const int VK_F4 = 0x73;
  static const int VK_F5 = 0x74;
  static const int VK_F6 = 0x75;
  static const int VK_F7 = 0x76;
  static const int VK_F8 = 0x77;
  static const int VK_F9 = 0x78;
  static const int VK_F10 = 0x79;
  static const int VK_F11 = 0x7A;
  static const int VK_F12 = 0x7B;

  _GetCursorPosDart? _getCursorPos;
  _SetCursorPosDart? _setCursorPos;
  _MouseEventDart? _mouseEvent;
  _KeybdEventDart? _keybdEvent;

  ffi.Pointer<POINT>? _pointPtr;
  bool _initialized = false;

  void _init() {
    if (!Platform.isWindows) return;
    try {
      final user32 = ffi.DynamicLibrary.open('user32.dll');
      _getCursorPos = user32
          .lookupFunction<_GetCursorPosC, _GetCursorPosDart>('GetCursorPos');
      _setCursorPos = user32
          .lookupFunction<_SetCursorPosC, _SetCursorPosDart>('SetCursorPos');
      _mouseEvent = user32
          .lookupFunction<_MouseEventC, _MouseEventDart>('mouse_event');
      _keybdEvent = user32
          .lookupFunction<_KeybdEventC, _KeybdEventDart>('keybd_event');

      _pointPtr = pkg_ffi.calloc<POINT>();
      _initialized = true;
    } catch (e) {
      stderr.writeln('NativeInputService: Error loading user32.dll: $e');
    }
  }

  /// Get current cursor coordinates
  ({int x, int y}) getCursorPos() {
    if (!_initialized || _getCursorPos == null || _pointPtr == null) {
      return (x: 0, y: 0);
    }
    _getCursorPos!(_pointPtr!);
    return (x: _pointPtr!.ref.x, y: _pointPtr!.ref.y);
  }

  /// Move cursor relative to current position
  void moveCursorRelative(double dx, double dy) {
    if (!_initialized || _mouseEvent == null) return;
    _mouseEvent!(
      MOUSEEVENTF_MOVE,
      dx.round(),
      dy.round(),
      0,
      0,
    );
  }

  /// Move cursor to absolute screen coordinates (0 to screen width/height)
  void moveCursorAbsolute(int x, int y) {
    if (!_initialized || _setCursorPos == null) return;
    _setCursorPos!(x, y);
  }

  /// Left mouse click (press and release)
  void leftClick() {
    if (!_initialized || _mouseEvent == null) return;
    _mouseEvent!(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
    _mouseEvent!(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
  }

  /// Left mouse double click
  void doubleClick() {
    leftClick();
    sleep(const Duration(milliseconds: 50));
    leftClick();
  }

  /// Right mouse click
  void rightClick() {
    if (!_initialized || _mouseEvent == null) return;
    _mouseEvent!(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0);
    _mouseEvent!(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0);
  }

  /// Middle mouse click
  void middleClick() {
    if (!_initialized || _mouseEvent == null) return;
    _mouseEvent!(MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, 0);
    _mouseEvent!(MOUSEEVENTF_MIDDLEUP, 0, 0, 0, 0);
  }

  /// Mouse left button down (for drag start)
  void leftDown() {
    if (!_initialized || _mouseEvent == null) return;
    _mouseEvent!(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
  }

  /// Mouse left button up (for drag release)
  void leftUp() {
    if (!_initialized || _mouseEvent == null) return;
    _mouseEvent!(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
  }

  /// Scroll mouse wheel (positive for up, negative for down)
  void scrollWheel(int amount) {
    if (!_initialized || _mouseEvent == null) return;
    _mouseEvent!(MOUSEEVENTF_WHEEL, 0, 0, amount * 120, 0);
  }

  /// Send key down event
  void keyDown(int virtualKey) {
    if (!_initialized || _keybdEvent == null) return;
    _keybdEvent!(virtualKey, 0, 0, 0);
  }

  /// Send key up event
  void keyUp(int virtualKey) {
    if (!_initialized || _keybdEvent == null) return;
    _keybdEvent!(virtualKey, 0, KEYEVENTF_KEYUP, 0);
  }

  /// Send key press (press and release)
  void keyPress(int virtualKey) {
    keyDown(virtualKey);
    keyUp(virtualKey);
  }

  /// Type text string by mapping characters to key strokes
  void typeText(String text) {
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final code = char.codeUnitAt(0);

      if (char == '\n') {
        keyPress(VK_RETURN);
      } else if (char == '\t') {
        keyPress(VK_TAB);
      } else if (char == ' ') {
        keyPress(VK_SPACE);
      } else if (code >= 65 && code <= 90) {
        // Uppercase A-Z -> Shift + key
        keyDown(VK_SHIFT);
        keyPress(code);
        keyUp(VK_SHIFT);
      } else if (code >= 97 && code <= 122) {
        // Lowercase a-z -> virtual key is uppercase code
        keyPress(code - 32);
      } else if (code >= 48 && code <= 57) {
        // Digits 0-9
        keyPress(code);
      } else {
        // Special characters or Unicode via clipboard paste or virtual keys
        _typeSpecialChar(char);
      }
    }
  }

  void _typeSpecialChar(String char) {
    switch (char) {
      case '.':
        keyPress(0xBE);
        break;
      case ',':
        keyPress(0xBC);
        break;
      case '-':
        keyPress(0xBD);
        break;
      case '/':
        keyPress(0xBF);
        break;
      case ';':
        keyPress(0xBA);
        break;
      case '=':
        keyPress(0xBB);
        break;
      case '[':
        keyPress(0xDB);
        break;
      case ']':
        keyPress(0xDD);
        break;
      case '\\':
        keyPress(0xDC);
        break;
      case '\'':
        keyPress(0xDE);
        break;
      case '`':
        keyPress(0xC0);
        break;
      case ':':
        keyDown(VK_SHIFT);
        keyPress(0xBA);
        keyUp(VK_SHIFT);
        break;
      case '+':
        keyDown(VK_SHIFT);
        keyPress(0xBB);
        keyUp(VK_SHIFT);
        break;
      case '<':
        keyDown(VK_SHIFT);
        keyPress(0xBC);
        keyUp(VK_SHIFT);
        break;
      case '_':
        keyDown(VK_SHIFT);
        keyPress(0xBD);
        keyUp(VK_SHIFT);
        break;
      case '>':
        keyDown(VK_SHIFT);
        keyPress(0xBF);
        keyUp(VK_SHIFT);
        break;
      case '?':
        keyDown(VK_SHIFT);
        keyPress(0xBF);
        keyUp(VK_SHIFT);
        break;
      case '!':
        keyDown(VK_SHIFT);
        keyPress(0x31);
        keyUp(VK_SHIFT);
        break;
      case '@':
        keyDown(VK_SHIFT);
        keyPress(0x32);
        keyUp(VK_SHIFT);
        break;
      case '#':
        keyDown(VK_SHIFT);
        keyPress(0x33);
        keyUp(VK_SHIFT);
        break;
      case '$':
        keyDown(VK_SHIFT);
        keyPress(0x34);
        keyUp(VK_SHIFT);
        break;
      case '%':
        keyDown(VK_SHIFT);
        keyPress(0x35);
        keyUp(VK_SHIFT);
        break;
      case '^':
        keyDown(VK_SHIFT);
        keyPress(0x36);
        keyUp(VK_SHIFT);
        break;
      case '&':
        keyDown(VK_SHIFT);
        keyPress(0x37);
        keyUp(VK_SHIFT);
        break;
      case '*':
        keyDown(VK_SHIFT);
        keyPress(0x38);
        keyUp(VK_SHIFT);
        break;
      case '(':
        keyDown(VK_SHIFT);
        keyPress(0x39);
        keyUp(VK_SHIFT);
        break;
      case ')':
        keyDown(VK_SHIFT);
        keyPress(0x30);
        keyUp(VK_SHIFT);
        break;
      default:
        // For Arabic and unicode characters, send key press if mapped or fallback
        break;
    }
  }

  /// Key combination (e.g. Ctrl+C, Alt+F4, Win+D, Ctrl+Shift+Esc)
  void keyCombination(List<int> keys) {
    for (final key in keys) {
      keyDown(key);
    }
    for (final key in keys.reversed) {
      keyUp(key);
    }
  }

  void dispose() {
    if (_pointPtr != null) {
      pkg_ffi.calloc.free(_pointPtr!);
      _pointPtr = null;
    }
  }
}
