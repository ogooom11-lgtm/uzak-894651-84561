KIOM PC Agent - Ignore stale commands patch

انسخ مجلد lib فوق مشروع تطبيق الكمبيوتر.

التعديل الجديد:
- أي أمر pending عمره أكثر من 5 دقائق يتم تجاهله.
- يتم تحديث مستند الأمر إلى status=ignored و agentState=ignored.
- يتم إنشاء رسالة في responses/{deviceId}/items تقول إن الأمر تم تجاهله.
- يطبع في Terminal سطر COMMAND_IGNORED.

بعد النسخ:
flutter clean
flutter pub get
flutter run -d windows

ملاحظة:
يعتمد حساب العمر على createdAt داخل الأمر، وإذا لم يكن موجوداً يستخدم createTime الخاص بوثيقة Firestore.
