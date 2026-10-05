باتش KIOM First Run Auto Admin Setup

الفكرة:
- عند أول تشغيل للتطبيق من مشروع Flutter، يفحص هل مهمة KIOM PC Agent موجودة.
- إذا غير موجودة، يفتح CMD كمسؤول عبر نافذة UAC.
- أنت تضغط Yes مرة واحدة فقط.
- بعدها يبني التطبيق، ينسخه إلى Program Files، ينشئ Scheduled Task، ويجعله يعمل مع Windows كمسؤول بدون سؤال كل مرة.

التركيب:
1) انسخ الملف:
   lib/services/first_run_auto_installer_service.dart
   إلى نفس المسار في مشروع الكمبيوتر.

2) افتح lib/main.dart وأضف الاستيراد:
   import 'services/first_run_auto_installer_service.dart';

3) في بداية main() قبل تشغيل Agent أضف:
   await FirstRunAutoInstallerService().ensureInstalledOrLaunchSetup();

مثال:
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirstRunAutoInstallerService().ensureInstalledOrLaunchSetup();
  await KiomPcAgentApp().start();
}

إذا كان main عندك لا يستخدم WidgetsFlutterBinding، فقط أضف السطر قبل start:
await FirstRunAutoInstallerService().ensureInstalledOrLaunchSetup();

تعطيل أثناء التطوير:
set KIOM_DISABLE_SELF_SETUP=1
flutter run -d windows

السجل:
%APPDATA%\KiomPcAgent\self_setup.log
