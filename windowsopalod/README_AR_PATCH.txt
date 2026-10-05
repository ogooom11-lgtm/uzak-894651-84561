ملفات التعديل الجاهزة:

1) انسخ الملفات إلى نفس المسارات داخل مشروع windowsopalod.
2) لا تستبدل config/firebase_config.json الحقيقي إذا فيه مفاتيحك، فقط أضف هذه القيم داخله:
   "enableStartupRegistrationFromCode": true,
   "enableDangerousPowerCommands": true,
   "enableWifiBluetoothCommands": true
3) شغل:
   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
4) للتثبيت الكامل شغل PowerShell كمسؤول ثم:
   powershell -ExecutionPolicy Bypass -File build\windows\x64\runner\Release\scripts\install_agent_full.ps1
5) لتثبيت التشغيل التلقائي بصلاحية عالية:
   شغّل KIOM PC Agent ثم استخدم زر "تشغيل مع Windows" لتثبيت Scheduled Task بصلاحية Administrator.
6) أوامر الاختبار من الهاتف/Firestore:
   check_connection
   wifi_off
   wifi_on
   bluetooth_off
   bluetooth_on

ملاحظة: Bluetooth هنا يتحكم بخدمة Bluetooth في ويندوز، وقد لا يطفئ زر الراديو في كل الأجهزة.
