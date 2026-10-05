# KIOM PC Agent - QR Hotkey Patch

انسخ الملفات الموجودة في هذا الباتش فوق مشروع تطبيق الكمبيوتر Flutter Windows.

## الملفات المعدلة

- pubspec.yaml
- lib/core/agent_app.dart
- lib/services/hotkey_pairing_qr_service.dart

## ماذا يضيف؟

- مراقبة الاختصار: Ctrl + Shift + Q + R لمدة 3 ثواني.
- توليد pairing_payload.json جديد.
- تسجيل Token جديد في Firestore داخل pairing_tokens.
- توليد QR صورة داخل:
  %APPDATA%\KiomPcAgent\pairing_qr.png
- إظهار نافذة QR مؤقتة لمدة 5 ثواني فقط ثم إغلاقها تلقائياً.

## بعد النسخ

```powershell
flutter clean
flutter pub get
flutter run -d windows
```

## الاستخدام

بعد تشغيل تطبيق الكمبيوتر، اضغط معاً:

Ctrl + Shift + Q + R

واستمر 3 ثواني. ستظهر نافذة QR مؤقتة، امسحها من تطبيق الهاتف.
