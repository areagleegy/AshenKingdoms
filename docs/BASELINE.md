# سجل خط الأساس التنفيذي — AshenKingdoms (المرحلة 1)

> **التاريخ:** 2026-10-20 (UTC)
> **المعرف:** AK-P0-001
> **المنصة الأولى:** Android (APK تجريبي ARM64)
> **الفريق:** مطوّر واحد
> **مرجع الفحص:** [main @ `d1a727a0e3a2fc177136e1ed89f0e14e1992039c`](https://github.com/areagleegy/AshenKingdoms/commit/d1a727a0e3a2fc177136e1ed89f0e14e1992039c)
> **الحالة:** خط أساس موثق؛ قبول Android على جهاز فعلي لم يُنفذ بعد.

## 1. النطاق وحدود الادعاء

هذه المرحلة جردٌ ساكن للمشروع وملفات البناء والاختبارات وسجل CI قبل تعديل منطق اللعبة. لا تتضمن تغييرات في أسلوب اللعب أو الشبكة أو الحفظ. وجود اختبار في YAML لا يثبت نجاحه؛ أدلة CI أدناه مرتبطة بالتزام محدد.

## 2. إعداد المشروع ومسار الدخول

| البند | نتيجة الفحص | الدليل |
|---|---|---|
| محرك المشروع المعلن | Godot 4.6 / GL Compatibility | [`project.godot`](../project.godot) |
| مشهد البدء | `res://scenes/ui/MainMenu.tscn` | [`project.godot`](../project.godot) |
| مشهد القائمة | `MainMenu` من نوع `Control`، يحمّل `scripts/ui/main_menu.gd` | [`MainMenu.tscn`](../scenes/ui/MainMenu.tscn) |
| تصدير Android | preset اسمه حرفيًا `Android`؛ ملف CI هو APK تجريبي | [`export_presets.cfg`](../export_presets.cfg)، [workflow البناء](../.github/workflows/build.yml) |
| إعداد أدوات CI | سكربت الإعداد يثبت Godot 4.6 stable | [`setup-godot-cli.sh`](../tools/setup-godot-cli.sh) |
| دعم اللمس | مشاهد/سكربتات لمس موجودة في المستودع وتتحقق CI من ملفاتها | [`TouchControls.tscn`](../scenes/ui/TouchControls.tscn)، [خطة الاختبار](TEST_PLAN.md) |

## 3. سير CI الفعلي على خط الأساس

الالتزام المرجعي `d1a727a0e3a2fc177136e1ed89f0e14e1992039c` هو رأس `main` الذي جرى فحصه. يعرض GitHub Actions التشغيلين التاليين على **الالتزام نفسه**:

| سير العمل | التشغيل | الحالة | ما تثبته النتيجة |
|---|---|---|---|
| Validate Godot Project | [#261 / 39490195007](https://github.com/areagleegy/AshenKingdoms/actions/runs/39490195007) | **Success** | انتهت وظيفة `validate` بنجاح؛ يشمل التعريف استيراد Godot وتحميل السكربتات/المشاهد واختبارات اللعب والانحدار والشبكة والمحتوى وفحوص Python والوثائق. |
| Build Android and Web | [#179 / 39490194778](https://github.com/areagleegy/AshenKingdoms/actions/runs/39490194778) | **Success** | نجحت وظيفتا `Export Android APK` و`Export Web`؛ رفع Artifacts معرف في سير العمل. |

- تعريفات التشغيل: [`.github/workflows/validate.yml`](../.github/workflows/validate.yml) و[`.github/workflows/build.yml`](../.github/workflows/build.yml).
- البناء يجهز Godot 4.6 stable، وJDK 17، وحزم Android SDK/NDK المعلنة في workflow. مخرجات البناء Artifacts مؤقتة (احتفاظ سبعة أيام).
- هذه نتائج CI على `d1a727a0e3a2fc177136e1ed89f0e14e1992039c` فقط. يجب مراجعة التشغيلين اللذين سيُنشآن لرأس هذا الفرع قبل الدمج.

## 4. بصمات ملفات خط الأساس

قيم Git blob SHA أدناه تطابق الملفات التي فُحصت على المرجع المحدد، وليست بصمات ملفات APK.

| المسار | Git blob SHA |
|---|---|
| `project.godot` | `456251c0f4143c6e797a885a278fd14ef7b5c70f` |
| `export_presets.cfg` | `639309148ec75d31e10950380ab1b36af81c31ce` |
| `.github/workflows/validate.yml` | `b6fa26227ab6e403b78e4fe8b465af1456d2206f` |
| `.github/workflows/build.yml` | `346e195d025fa51116bf74d598edfb920fd18946` |
| `scripts/core/save_system.gd` | `fa1bb0fd6b5b80e09cb0c732a201a1edc8b31044` |
| `scenes/ui/MainMenu.tscn` | `c331754608b4f2205f2a87300956b621bd365a86` |
| `docs/PROJECT_STATUS_AR.md` | `d759a7defd93a253a9e02faa6e0ff68ed05da632` |

## 5. تغطية التحقق الحالية

- `validate.yml` يُفعّل على الدفع إلى `main`، وعلى Pull Request، ويمكن تشغيله يدويًا. يتضمن فحص الملفات والروابط، استيراد المشروع headless، تحميل موارد Godot، اختبارات اللعب والانحدار واللاعب والشبكة وENet loopback وحزم المحتوى، وفحوص Python والأصول.
- `build.yml` يُفعّل على الدفع إلى `main`، وعلى Pull Request، ويمكن تشغيله يدويًا. يصدر Android debug APK وWeb، ويتحقق من وجود المخرجات ويرفعها كـ Artifacts.
- الاختبار اليدوي لمشهد البداية على Android، والتحقق من اللمس والكاميرا والإيقاف/الاستئناف، **غير مثبت** في سجلات CI.
- لم أشغّل Godot محليًا أو على هاتف ضمن هذا التنفيذ؛ نجاح CI ليس بديلًا عن ذلك.

## 6. ملاحظات أولية ومهام تالية

| الأولوية | الملاحظة | الدليل/التحقق التالي | الحالة |
|---|---|---|---|
| P0 | لا يوجد دليل قبول على هاتف Android حقيقي | تثبيت APK الناتج عن رأس PR الحالي وتسجيل طراز الجهاز وإصدار Android ونتيجة الحلقة الأساسية | غير متحقق |
| P0 | يلزم فحص CI على رأس الفرع بعد هذا التغيير | مراجعة نتيجتي Validate وBuild المرتبطتين بـ SHA الجديد | بانتظار التشغيل |
| P1 | كتابة الحفظ الحالية مباشرة إلى `user://savegame.json` ولا يظهر في الملف مسار كتابة مؤقت/استبدال آمن | اختبارات فشل الكتابة/الانقطاع والاستعادة في المرحلة المخصصة للحفظ | ملاحظة ساكنة؛ لم تُثبت حالة تلف فعلية |
| P1 | اختبار loopback لا يثبت اتصالًا من هاتف إلى هاتف أو جاهزية شبكة عامة | إبقاء الاختبار الشبكي الفعلي ضمن بوابات لاحقة وعدم توسيع النطاق في المرحلة 1 | غير متحقق |

## 7. تعريف اكتمال المرحلة الأولى

- [x] تثبيت commit مرجعي واضح.
- [x] مراجعة إعداد Godot ومشهد الدخول وAndroid preset.
- [x] مراجعة تعريفات Validate وBuild.
- [x] توثيق أحدث نتيجتي CI المتاحتين على المرجع مع روابط التشغيل.
- [ ] إعادة تشغيل CI على رأس هذا الفرع وتسجيل SHA والنتيجة.
- [ ] قبول يدوي على جهاز Android فعلي؛ هذا شرط لاحق ولا يمكن استنتاجه من التصدير.

**قرار المرحلة:** يمكن الانتقال إلى تنفيذ تغييرات صغيرة على فرع منفصل بعد ظهور CI أخضر على رأسه. لا يُدمج هذا الفرع في `main` تلقائيًا، ولا تعتبر المرحلة مكتملة من ناحية قبول الجهاز حتى توثيق اختبار Android الفعلي.
