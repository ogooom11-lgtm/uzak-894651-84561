# KIOM PC Agent - CMD Fallback Self Setup Patch

هذا الباتش يجعل التطبيق يحاول تثبيت نفسه تلقائياً حتى لو PowerShell ممنوع.

## التركيب

انسخ الملفات فوق مشروع تطبيق الكمبيوتر، ثم شغّل:

```powershell
powershell -ExecutionPolicy Bypass -File tools\apply_cmd_fallback_self_setup_patch.ps1
flutter clean
flutter pub get
flutter run -d windows
```

عند تشغيل التطبيق إذا لم يجد مهمة `KIOM PC Agent` سيحاول فتح CMD كمسؤول عبر `wscript.exe`.
سيظهر طلب UAC من Windows مرة واحدة، وبعد الموافقة يثبت التطبيق في:

```text
C:\Program Files\KIOM\PC Agent
```

وينشئ Scheduled Task بصلاحية:

```text
Run with highest privileges
```

## تعطيل المحاولة أثناء التطوير

```powershell
$env:KIOM_DISABLE_SELF_SETUP='1'
flutter run -d windows
```

## سجل الأخطاء

```text
%APPDATA%\KiomPcAgent\self_setup.log
```

ملاحظة: هذا لا يتجاوز حماية Windows. إذا كان الجهاز يمنع CMD و WScript وسياسات المسؤول، يجب فك القيود من حساب Administrator.