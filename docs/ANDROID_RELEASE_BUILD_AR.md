# بناء حزمة Android App Bundle موقّعة لـ Google Play

## المخرجات

يُنتج Workflow `Build Game Platforms` ملف APK تجريبيًا للتثبيت المباشر. أما Workflow `Android Release AAB` المنفصل فينتج ملف `.aab` موقّعًا عبر Gradle بمفتاح الإصدار الذي يديره مالك المشروع. اعتبارًا من 31 أغسطس 2026، تتطلب Google Play أن تستهدف التطبيقات والتحديثات الجديدة Android 16 (API 36) أو أعلى. [سياسة Google Play الرسمية](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-US-u-mu-fahren).

اسم Artifact الناتج هو `ashen-kingdoms-android-play-release`. يحتفظ GitHub Actions به لمدة 7 أيام. لا يرفع المسار التطبيق تلقائيًا إلى Play Console ولا ينشر إصدارًا للمستخدمين.

## إعداد حماية أسرار التوقيع

**لا تضف ملف keystore أو كلمة مروره إلى المستودع أو ملفات الإعدادات.** يحتوي `export_presets.cfg` على حقول توقيع فارغة؛ يعبّئها الـ runner مؤقتًا أثناء تشغيل الإصدار.

1. افتح `Settings → Environments` في GitHub وأنشئ Environment بالاسم الدقيق `android-release`.
2. قيّد فروع النشر المسموحة إلى `main` فقط، واضبط Required reviewers بحيث يحتاج تشغيل الإصدار إلى موافقة شخص مخوّل. يرفض Workflow التشغيل من فرع غير `main`؛ إعداد Environment هو طبقة الحماية الإضافية.
3. أنشئ مفتاح الإصدار على جهاز موثوق، أو استخدم مفتاح الرفع المسجّل بالفعل في Play Console إذا كان التطبيق مسجلًا من قبل. لا تُنشئ مفتاحًا جديدًا لإصدار قائم دون خطة تدوير/استعادة معتمدة.
4. أضف الأسرار التالية إلى Environment `android-release`، لا إلى ملف داخل المستودع:

| اسم السر | المحتوى |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | ملف keystore كاملًا بعد ترميزه بـ Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة مرور ملف keystore |
| `ANDROID_KEYSTORE_ALIAS` | اسم المفتاح/alias داخله |

مثال إنشاء مفتاح **لأول إصدار فقط** على Linux؛ احتفظ بنسخة احتياطية مشفّرة وخارجية منه:

```bash
keytool -genkeypair -v \
  -keystore ashenkingdoms-release.keystore \
  -alias ashenkingdoms \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w 0 ashenkingdoms-release.keystore
```

على macOS يمكن إنتاج القيمة المشفّرة باستخدام:

```bash
base64 < ashenkingdoms-release.keystore | tr -d '\n'
```

انسخ خرج Base64 إلى السر `ANDROID_KEYSTORE_BASE64` ولا تنشره في Issue أو سجل CI أو محادثة عامة. لا ترفع الملف الأصلي نفسه. إذا كان التطبيق موجودًا بالفعل في Play Console، استخدم بيانات مفتاح الرفع المعتمدة لذلك التطبيق.

## إنشاء الإصدار

1. افتح تبويب **Actions** في GitHub.
2. اختر Workflow **Android Release AAB** واضغط **Run workflow** من فرع `main`.
3. أدخل `version_code` موجبًا وفريدًا وأعلى من آخر رمز رفعته إلى Play Console، وأدخل `version_name` مثل `0.1.0`.
4. وافق على تشغيل Environment `android-release` إذا طُلبت مراجعة.
5. بعد نجاح البناء والتحقق من التوقيع، نزّل Artifact `ashen-kingdoms-android-play-release`.

يفشل المسار إذا كانت الأسرار ناقصة، أو كان رقم الإصدار غير صالح، أو لم يجد إعدادات Preset المتوقعة، أو لم يؤكد `jarsigner` أن الحزمة موقّعة. رقم الإصدار لا يُزاد تلقائيًا؛ أدخل رقمًا جديدًا لكل رفع لاحق.

## حدود هذه الخطوة

- المهمة تبني AAB وتتحقق من توقيعه؛ لكنها لا تختبر اللعبة على هاتف فعلي ولا تثبت قبول Play Console.
- لا يحدث رفع أو نشر تلقائي إلى Google Play. راجع سياسات المتجر وتصنيف المحتوى ومتطلبات Android الحالية قبل الإرسال.
- لا تُشارك ملف keystore أو الأسرار في Artifacts. يحتوي Artifact على AAB فقط وتنتهي صلاحيته بعد 7 أيام.
- إذا لم يُضبط Environment والأسرار، يستمر بناء APK التجريبي المعتاد، ولا ينتج ملف AAB موقّع.
