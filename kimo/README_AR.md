# تطبيق الهاتف - لوحة تحكم أجهزة Windows عبر Flutter

هذه الحزمة هي نسخة أولى جاهزة لتطبيق الهاتف فقط. التطبيق مبني كـ Dashboard عربية RTL لإدارة أجهزة Windows المرتبطة عبر Firebase.

> ملاحظة أمان: استخدم هذا النظام فقط مع الأجهزة التي تملكها أو لديك تصريح واضح لإدارتها.

## ماذا يوجد داخل الحزمة؟

- `lib/main.dart` نقطة تشغيل التطبيق.
- `lib/config/app_environment.dart` لتفعيل أو تعطيل Firebase.
- `lib/config/firebase_options.dart` ملف مؤقت يتم استبداله من FlutterFire.
- `lib/models` نماذج البيانات: الأجهزة، التطبيقات المفتوحة، قواعد المسارات، الطلبات، اللقطات، السجلات.
- `lib/repositories` طبقة الاتصال: وضع تجريبي Mock + وضع Firebase.
- `lib/screens` كل صفحات التطبيق.
- `lib/widgets` عناصر واجهة مشتركة.
- `firebase.rules` قواعد Firestore أولية.
- `firebase.storage.rules` قواعد Storage أولية للصور.

## الصفحات المنفذة

- تسجيل دخول تجريبي.
- الأجهزة المرتبطة.
- تفاصيل الجهاز.
- التطبيقات المفتوحة وإغلاق التطبيق الآن أو بعد مدة.
- حماية المسارات وإضافة/حذف القواعد.
- طلبات الإذن.
- طلبات تثبيت البرامج.
- إدارة WiFi.
- إدارة Bluetooth.
- إدارة الصوت.
- إدارة الطاقة.
- لقطات الشاشة.
- السجلات.
- ربط جهاز عبر QR.
- الإعدادات.

## التشغيل بدون Firebase أولاً

النسخة تعمل مباشرة بوضع Demo Mode لأن `useFirebase = false` داخل:

```dart
lib/config/app_environment.dart
```

الأوامر لن تتحكم بجهاز حقيقي في هذا الوضع، لكنها تظهر طريقة عمل التطبيق والواجهة وتدفق الأوامر.

## طريقة إنشاء مشروع Flutter وتشغيل هذه الملفات

إذا لم يكن لديك مشروع Flutter جاهز:

```bash
flutter create win_remote_mobile
```

ثم انسخ ملفات هذه الحزمة فوق المشروع الذي تم إنشاؤه، خصوصاً:

```bash
lib/
pubspec.yaml
analysis_options.yaml
firebase.rules
firebase.storage.rules
```

بعدها شغّل:

```bash
flutter pub get
flutter run
```

## ربط Firebase لاحقاً

1. أنشئ مشروع Firebase جديد.
2. فعّل:
   - Authentication
   - Cloud Firestore
   - Firebase Storage
3. من مجلد المشروع شغّل:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

4. استبدل ملف:

```bash
lib/config/firebase_options.dart
```

بالملف الذي يولده FlutterFire.

5. غيّر هذا السطر:

```dart
static const bool useFirebase = false;
```

إلى:

```dart
static const bool useFirebase = true;
```

6. ارفع قواعد Firestore وStorage من الملفين المرفقين بعد مراجعتها وتشديدها للإنتاج.

## بنية Firestore المستخدمة في التطبيق

```text
devices/{deviceId}
commands/{deviceId}/items/{commandId}
responses/{deviceId}/items/{responseId}
open_apps/{deviceId}/items/{processId}
permission_requests/{deviceId}/items/{requestId}
install_requests/{deviceId}/items/{requestId}
screenshots/{deviceId}/items/{screenshotId}
requested_logs/{deviceId}/items/{logId}
path_rules/{deviceId}/items/{ruleId}
pairing_tokens/{token}
users/{userId}/devices/{deviceId}
```

## أين تعدّل لاحقاً؟

- إعدادات Firebase: `lib/config/firebase_options.dart`
- تفعيل Firebase: `lib/config/app_environment.dart`
- أسماء Collections: `lib/services/firebase_paths.dart`
- شكل الأوامر المرسلة للكمبيوتر: `lib/core/command_type.dart`
- منطق Firestore: `lib/repositories/firebase_device_repository.dart`
- بيانات العرض التجريبي: `lib/repositories/mock_device_repository.dart`
- تصميم الواجهة: ملفات `lib/screens` و `lib/widgets`

## الخطوة التالية بعد تطبيق الهاتف

الخطوة التالية هي بناء تطبيق Windows Agent، ويجب أن يقرأ نفس البنية من Firestore:

- يستمع إلى `commands/{deviceId}/items`.
- يحدّث `open_apps/{deviceId}/items`.
- يرسل طلبات الإذن إلى `permission_requests/{deviceId}/items`.
- يرسل طلبات التثبيت إلى `install_requests/{deviceId}/items`.
- يرفع لقطات الشاشة إلى Storage ويكتب رابطها في `screenshots/{deviceId}/items`.
- يرسل السجلات المطلوبة إلى `requested_logs/{deviceId}/items`.
- يحفظ القواعد والسجلات محلياً في Windows باستخدام SQLite.
