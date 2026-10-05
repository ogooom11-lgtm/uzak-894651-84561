سبب عدم إقلاع التطبيق بعد التثبيت غالباً كان من نقطتين:

1) lib/config/firebase_options.dart كان يحتوي REPLACE_ME بينما AppEnvironment.useFirebase = true.
   هذا يجعل Firebase.initializeApp يفشل مباشرة عند بداية التطبيق.

2) AndroidManifest الرئيسي android/app/src/main/AndroidManifest.xml لم يكن يحتوي إذن الإنترنت.
   Android Studio في debug يستخدم android/app/src/debug/AndroidManifest.xml وفيه INTERNET،
   لكن نسخة release المثبتة على الموبايل تستخدم main فقط.

طريقة التركيب:
- انسخ الملفات الموجودة في هذا التصحيح فوق ملفات مشروعك بنفس المسارات.
- بعدها شغّل:

flutter clean
flutter pub get
flutter build apk --release --no-shrink

الملف الناتج:
build/app/outputs/flutter-apk/app-release.apk

إذا كان التطبيق مثبتاً سابقاً، احذفه من الموبايل ثم ثبّت النسخة الجديدة.
