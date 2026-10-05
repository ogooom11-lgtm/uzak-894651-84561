# KIOM QR Hotkey Fix

هذا الباتش يجعل الاختصار يعمل عالمياً عبر GetAsyncKeyState، ويضيف رسائل واضحة في الطرفية.

الاختصارات:
- Ctrl + Shift + Q + R لمدة 3 ثواني
- احتياطي أسهل: Ctrl + Shift + F12 لمدة ثانية واحدة

اختبار بديل بدون لوحة مفاتيح:
```powershell
powershell -ExecutionPolicy Bypass -File tools\show_qr_now.ps1
```

إذا لم يظهر QR، افتح:
%APPDATA%\KiomPcAgent\local_store.json
وابحث عن logs من نوع qr_hotkey_start أو qr_hotkey_hold_detected أو qr_hotkey_error.
