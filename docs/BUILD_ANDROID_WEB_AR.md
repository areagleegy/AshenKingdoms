# دليل البناء الآلي إلى Android وWeb

> نطاق الإصدار المستهدف والقيود الفعلية موثقان في [نطاق الإصدار](RELEASE_SCOPE_AR.md) و[حالة التنفيذ](PROJECT_STATUS_AR.md). نجاح التصدير ينتج Artifact قابلًا للتنزيل، لكنه لا يعني أن النسخة موقعة للإنتاج أو اجتازت اختبار جهاز/متصفح. تصدير Web الحالي يدعم اللعب الفردي فقط؛ اللعب الجماعي في المتصفح غير مدعوم بعد.

## إصدارات الأدوات

يثبت البناء التجريبي Godot 4.6 stable وقوالب التصدير المطابقة. متطلبات Android الموثقة لـ Godot 4.6 هي:

- OpenJDK 17.
- Android SDK Platform 35 للبناء التجريبي.
- Android SDK Build-Tools 35.0.1.
- يتضمن Workflow إصدار Google Play منصة SDK رقم 36 الإضافية ويضبط `targetSdkVersion=36`، لأن إرسال تطبيقات أو تحديثات جديدة إلى Google Play يتطلب API 36 أو أعلى منذ 31 أغسطس 2026 ([سياسة Google الرسمية](https://support.google.com/googleplay/android-developer/answer/11926878)).
- Android SDK Platform-Tools 35.0.0 أو أحدث.
- Android SDK Command-line Tools latest.
- NDK 28.1.13356709.
- CMake 3.10.2.4988404.

مهمة Web لا تثبت Android SDK.

## كيف يعمل Actions؟

- validate.yml: يعمل عند الدفع إلى main وعند فتح أو تحديث Pull Request، ويشغّل التحقق والاختبارات الآلية في وضع headless.
- build.yml (`Build Game Platforms`): يعمل عند الدفع إلى main، وعند فتح أو تحديث Pull Request، ويمكن تشغيله يدويًا من تبويب Actions.
- android-release.yml (`Android Release AAB`): Workflow مستقل، يدوي فقط ومن فرع `main`؛ ينتج AAB موقّعًا بعد توفر الأسرار في بيئة `android-release`.
- يرفع build.yml مخرجاته كـ Artifacts مؤقتة لمدة 7 أيام؛ نجاح التصدير لا يثبت سلامة التشغيل على جهاز حقيقي.
- Web: يثبت Godot والقوالب ثم ينتج build/web/index.html والملفات التابعة.
- Android: يثبت JDK وAndroid SDK ثم ينتج APK تجريبيًا لمعمارية arm64-v8a.
- ترفع الملفات باستخدام actions/upload-artifact مع احتفاظ 7 أيام لتقليل التخزين.

## تشغيل البناء يدويًا

1. افتح المستودع في GitHub ثم Actions.
2. اختر Build Game Platforms.
3. اضغط Run workflow.
4. افتح تشغيل Workflow بعد اكتماله.
5. نزّل Artifact باسم ashen-kingdoms-web أو ashen-kingdoms-android-debug.

## اختبار Android

ثبّت APK على هاتف Android. قد تحتاج السماح بالتثبيت من المتصفح أو مدير الملفات. هذه نسخة اختبار، وليست توقيع إصدار إنتاجي.

## إصدار Google Play موقّع

ملف APK الاعتيادي مخصص للاختبار. لإنشاء AAB موقّع:

1. تأكد من أن فرع `main` يحتوي على إعدادات الإصدار المطلوبة.
2. أنشئ أو استخدم مفتاح الإصدار الصحيح، واحفظ ملفه خارج المستودع.
3. في GitHub، افتح `Settings → Environments` وأنشئ البيئة `android-release`. أضف أسرار `ANDROID_KEYSTORE_BASE64` و`ANDROID_KEYSTORE_PASSWORD` و`ANDROID_KEYSTORE_ALIAS` إليها، واضبط قواعد مراجعة/اعتماد للبيئة إن كانت مناسبة.
4. من `Actions` اختر `Android Release AAB`، وشغّله من `main` فقط مع `version_code` متزايد و`version_name`.
5. راجع سجل توقيع AAB ونزّل artifact `ashen-kingdoms-android-play-release`. الحزمة موقّعة، لكن يلزم اختبارها وتحديثها في مسار المتجر الفعلي قبل إعلان النشر.

لا تضع ملف keystore أو كلمة مروره في المستودع أو artifacts. يتطلب Google Play حاليًا Android API 36 أو أعلى للتطبيقات/التحديثات الجديدة منذ 31 أغسطس 2026؛ Workflow يتحقق من هذا المستوى قبل التصدير ([المصدر الرسمي](https://support.google.com/googleplay/android-developer/answer/11926878)).

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
