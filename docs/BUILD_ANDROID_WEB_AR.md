# دليل البناء الآلي إلى Android وWeb

## إصدارات الأدوات

يثبت CI Godot 4.6 stable وقوالب التصدير المطابقة. متطلبات Android الموثقة لـ Godot 4.6 هي:

- OpenJDK 17.
- Android SDK Platform 35.
- Android SDK Build-Tools 35.0.1.
- Android SDK Platform-Tools 35.0.0 أو أحدث.
- Android SDK Command-line Tools latest.
- NDK 28.1.13356709.
- CMake 3.10.2.4988404.

مهمة Web لا تثبت Android SDK.

## كيف يعمل Actions؟

- validate.yml: يعمل عند الدفع إلى main وعند Pull Request، ويتحقق من الملفات ويستورد المشروع في وضع headless.
- build.yml: يعمل تلقائيًا عند الدفع إلى main أو يدويًا من تبويب Actions.
- Web: يثبت Godot والقوالب ثم ينتج build/web/index.html والملفات التابعة.
- Android: يثبت JDK وAndroid SDK ثم ينتج APK تجريبيًا لمعمارية arm64-v8a.
- ترفع الملفات باستخدام actions/upload-artifact مع احتفاظ 7 أيام لتقليل التخزين.

## تشغيل البناء يدويًا

1. افتح المستودع في GitHub ثم Actions.
2. اختر Build Android and Web.
3. اضغط Run workflow.
4. افتح تشغيل Workflow بعد اكتماله.
5. نزّل Artifact باسم ashen-kingdoms-web أو ashen-kingdoms-android-debug.

## اختبار Android

ثبّت APK على هاتف Android. قد تحتاج السماح بالتثبيت من المتصفح أو مدير الملفات. هذه نسخة اختبار، وليست توقيع إصدار إنتاجي.

قبل النشر التجاري:
- أنشئ مفتاح توقيع خارج المستودع.
- خزنه في GitHub Actions Secrets.
- أضف مسار إصدار مستقل يقرأ الأسرار عند النشر فقط.
- لا ترفع ملف keystore أو كلمة مروره إلى المستودع.
- قد يتطلب Google Play ملف AAB بدل APK.

## اختبار Web

فك ضغط Artifact وانشر الملفات عبر HTTP/HTTPS. لا تفتح index.html مباشرة من مدير الملفات؛ فقد تحتاج JavaScript وWebAssembly إلى خادم HTTP.

للنشر عبر GitHub Pages:
1. افتح Settings ثم Pages.
2. اختر GitHub Actions كمصدر النشر.
3. أضف Workflow نشر Pages بعد نجاح البناء.
4. اختبر الرابط على الهاتف والمتصفح المستهدف.

يستخدم Web preset تعطيل دعم threads افتراضيًا لتبسيط الاستضافة الثابتة. أعد تقييم الإعداد إذا أضيفت ميزات تحتاج threads.

## أخطاء شائعة

- Missing export template: طابق إصدار Godot والقوالب مع 4.6 stable.
- Export preset not found: يجب أن يكون اسم Preset هو Android أو Web حرفيًا.
- Android SDK path missing: راجع إعدادات المسارات في editor_settings-4.tres التي يولدها CI.
- Android export failure: راجع سجلات JDK وSDK وNDK وتراخيص SDK في Actions.
- Web صفحة فارغة: راجع سجل المتصفح وتأكد من نشر جميع الملفات عبر HTTPS، لا index.html وحده.

مشغلات GitHub Actions القياسية مجانية للمستودعات العامة وفق السياسة المنشورة، لكن ذلك لا يعني أن استضافة خادم لعب حي تعمل على مدار الساعة مجانية.
