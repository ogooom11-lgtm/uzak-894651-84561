# KIOM PC Agent - Flutter Windows

هذه نسخة أولى من تطبيق الكمبيوتر الخاص بمشروع KIOM، مكتوبة بفلتر وتعمل على Windows في الخلفية بدون نافذة ظاهرة.

## ماذا تفعل النسخة الحالية؟

- تولّد Device ID تلقائياً.
- تسجل الكمبيوتر في Firestore داخل `devices/{deviceId}`.
- تنشئ Token ربط وتكتبه في ملف محلي.
- تحدث التطبيقات المفتوحة في Firestore داخل `open_apps/{deviceId}/items`.
- تقرأ أوامر الهاتف من `commands/{deviceId}/items`.
- ترد في `responses/{deviceId}/items`.
- تحفظ السجلات والقواعد محلياً داخل `%APPDATA%\KiomPcAgent`.
- تعرض رسائل منع عند محاولة فتح مسار محمي من File Explorer.
- تعرض مربع كلمة مرور لمسار نوعه `password`.
- تغلق نافذة Explorer للمسار المحمي عند الرفض أو المنع.

## ملاحظة مهمة عن حماية المسارات

هذه النسخة تحمي فتح المجلدات عبر Windows File Explorer بالمراقبة والإغلاق والرسائل. الحماية العميقة ضد كل البرامج، ومنع النسخ والحذف والتعديل على مستوى النظام، تحتاج تشغيل التطبيق بصلاحية Administrator وربط Windows APIs المناسبة مباشرة.

## طريقة الإنشاء

افتح PowerShell:

```powershell
flutter create --platforms=windows kiom_pc_agent
cd kiom_pc_agent
```

انسخ ملفات هذه الحزمة فوق ملفات المشروع الناتج.

ثم:

```powershell
copy config\firebase_config.example.json config\firebase_config.json
```

افتح:

```text
config/firebase_config.json
```

وضع:

```json
{
  "projectId": "اسم مشروع Firebase",
  "apiKey": "Web API Key من Firebase"
}
```

يمكنك الحصول على Web API Key من:

```text
Firebase Console > Project settings > General > Web API Key
```

## إخفاء نافذة Flutter

من داخل مجلد المشروع:

```powershell
powershell -ExecutionPolicy Bypass -File tools\apply_hidden_window_patch.ps1
```

هذا يعدل:

```text
windows/runner/win32_window.cpp
```

ويجعل النافذة مخفية.

## تشغيل تجريبي

```powershell
flutter pub get
flutter run -d windows
```

رغم أن النافذة ستكون مخفية بعد patch، سيبقى التطبيق يعمل بالخلفية.

## بناء نسخة Windows

```powershell
flutter build windows
```

ملف التشغيل سيكون غالباً هنا:

```text
build\windows\x64\runner\Release\kiom_pc_agent.exe
```

## تشغيل التطبيق مع بداية Windows

بعد البناء:

```powershell
powershell -ExecutionPolicy Bypass -File tools\install_startup.ps1
```

لإزالته من بداية التشغيل:

```powershell
powershell -ExecutionPolicy Bypass -File tools\uninstall_startup.ps1
```

## ملف الربط اليدوي

بعد تشغيل التطبيق، سيظهر ملف الربط هنا:

```text
%APPDATA%\KiomPcAgent\pairing_payload.json
```

افتح الملف وانسخ النص JSON وضعه في شاشة الربط اليدوي في تطبيق الهاتف.

## مسارات Firestore المستخدمة

```text
devices/{deviceId}
open_apps/{deviceId}/items/{processId}
commands/{deviceId}/items/{commandId}
responses/{deviceId}/items/{responseId}
pairing_tokens/{token}
permission_requests/{deviceId}/items/{requestId}
```

## أوامر مدعومة حالياً

```text
check_connection
close_application
close_application_after_delay
lock_screen
request_logs
add_path_rule
update_path_rule
remove_path_rule
```

## مثال أمر إضافة مسار ممنوع

في Firestore أضف داخل:

```text
commands/{deviceId}/items/{commandId}
```

الحقول:

```text
type: add_path_rule
status: pending
createdBy: local_demo_user
payload: map
```

داخل payload:

```text
id: rule_private_folder
path: D:\Private
lockType: blocked
blockOpen: true
```

عند فتح `D:\Private` من Explorer، ستظهر رسالة:

```text
ممنوع فتح هذا المجلد أو المسار
```

ثم تغلق نافذة Explorer.

## مثال مسار بكلمة مرور

payload:

```text
id: rule_secret_password
path: D:\Secret
lockType: password
password: 123456
blockOpen: true
```

سيحفظ التطبيق كلمة المرور Hash محلياً، وعند فتح المسار تظهر نافذة تطلب كلمة المرور. عند إدخالها بشكل صحيح يسمح مؤقتاً حسب:

```json
"defaultPasswordAllowMinutes": 10
```

## ملاحظات أمان

لا تستخدم هذا التطبيق إلا على أجهزتك أو أجهزة لديك إذن واضح بإدارتها. لا تجعل قواعد Firestore مفتوحة في النسخة النهائية. بعد نجاح التجربة، يجب ربط الأوامر بمستخدم مصرح به وقواعد Firebase آمنة.
