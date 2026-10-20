import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class ScreenStreamService {
  ScreenStreamService._();

  static final ScreenStreamService instance = ScreenStreamService._();

  int _screenWidth = 1920;
  int _screenHeight = 1080;

  int get screenWidth => _screenWidth;
  int get screenHeight => _screenHeight;

  /// Fast Screen Frame Capture returning compressed JPEG bytes
  Future<Uint8List?> captureFrame({
    int quality = 60,
    int maxWidth = 1280,
    int maxHeight = 720,
  }) async {
    if (!Platform.isWindows) return null;

    try {
      final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$origW = \$screen.Bounds.Width
\$origH = \$screen.Bounds.Height

\$bmp = New-Object System.Drawing.Bitmap(\$origW, \$origH)
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen(\$screen.Bounds.Location, [System.Drawing.Point]::Empty, \$screen.Bounds.Size)

# Scale if needed for higher FPS over Wi-Fi
\$targetW = [math]::Min(\$origW, $maxWidth)
\$targetH = [math]::Round(\$origH * (\$targetW / \$origW))

\$resized = New-Object System.Drawing.Bitmap(\$targetW, \$targetH)
\$g2 = [System.Drawing.Graphics]::FromImage(\$resized)
\$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::Bilinear
\$g2.DrawImage(\$bmp, 0, 0, \$targetW, \$targetH)

\$encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { \$_.MimeType -eq 'image/jpeg' }
\$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
\$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$quality)

\$ms = New-Object System.IO.MemoryStream
\$resized.Save(\$ms, \$encoder, \$encParams)
\$bytes = \$ms.ToArray()

\$g.Dispose()
\$bmp.Dispose()
\$g2.Dispose()
\$resized.Dispose()
\$ms.Dispose()

[System.Console]::OpenStandardOutput().Write(\$bytes, 0, \$bytes.Length)
''';

      final process = await Process.start(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );

      final chunks = <List<int>>[];
      await for (final chunk in process.stdout) {
        chunks.add(chunk);
      }
      final exitCode = await process.exitCode;

      if (exitCode == 0 && chunks.isNotEmpty) {
        final totalLen = chunks.fold<int>(0, (sum, c) => sum + c.length);
        final result = Uint8List(totalLen);
        var offset = 0;
        for (final c in chunks) {
          result.setRange(offset, offset + c.length, c);
          offset += c.length;
        }
        return result;
      }
    } catch (_) {}
    return null;
  }

  /// Get current screen resolution (Width, Height)
  Future<(int width, int height)> getScreenResolution() async {
    if (!Platform.isWindows) return (1920, 1080);
    try {
      final res = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '[System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width.ToString() + "x" + [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height.ToString()',
        ],
        runInShell: false,
      );
      if (res.exitCode == 0) {
        final text = res.stdout.toString().trim();
        final parts = text.split('x');
        if (parts.length == 2) {
          _screenWidth = int.tryParse(parts[0]) ?? 1920;
          _screenHeight = int.tryParse(parts[1]) ?? 1080;
          return (_screenWidth, _screenHeight);
        }
      }
    } catch (_) {}
    return (_screenWidth, _screenHeight);
  }
}
