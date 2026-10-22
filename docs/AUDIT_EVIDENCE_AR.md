# سجل أدلة التدقيق — AshenKingdoms

## هوية المراجعة

- المستودع: [areagleegy/AshenKingdoms](https://github.com/areagleegy/AshenKingdoms)
- الفرع الأساسي الذي تمت قراءته: `main`
- commit الأساس الخاص بطلب السحب #69 وقت المراجعة: `d1a727a0e3a2fc177136e1ed89f0e14e1992039c`
- فرع الإصلاح: `hardening/save-system-v1`
- commit إصلاح الحفظ الذي اجتاز Validate CI: `864665fcf743c39c3502a8e409b2a65bcf3e4c7b`
- سجل CI لذلك commit: [Validate Godot Project](https://github.com/areagleegy/AshenKingdoms/actions/runs/39785406188)
- طلب السحب: [#69](https://github.com/areagleegy/AshenKingdoms/pull/69)

كل نتيجة أدناه موسومة بنوع الدليل. قراءة المصدر تثبت ما ينفذه الكود الظاهر، لكنها لا تثبت وحدها إعادة إنتاج أثر تشغيلي، ولا تجعل نتيجة commit واحد دليلاً على commits أخرى.

## الأدلة المباشرة من `main`

| الموضوع | مسار الملف وBlob SHA | دليل مقروء مباشرة | ما يمكن استنتاجه وما لا يمكن |
|---|---|---|---|
| الحفظ المحلي | [`scripts/core/save_system.gd`](https://github.com/areagleegy/AshenKingdoms/blob/main/scripts/core/save_system.gd) — `fa1bb0fd6b5b80e09cb0c732a201a1edc8b31044` | `save_game` يفتح `user://savegame.json` باستخدام `FileAccess.WRITE` ويكتب JSON مباشرة. `load_game` يعيد `{}` عند فشل تحليل JSON. | مخاطرة تصميمية بفقد أو عدم تمييز بيانات الحفظ؛ لم يُجر اختبار انقطاع كتابة على هذه النسخة الأساسية. |
| تحقق CI | [`.github/workflows/validate.yml`](https://github.com/areagleegy/AshenKingdoms/blob/main/.github/workflows/validate.yml) — `b6fa26227ab6e403b78e4fe8b465af1456d2206f` | يستخدم الحدث `pull_request`، لا `pull_request_target`; يحدد `permissions: contents: read`; وتُمرّر متغيرات سرية لخطوة تشخيص AI في هذا الإصدار. | يوجد خطر من إتاحة أسرار التشخيص لشيفرة PR داخل سياقات المستودع الموثوقة؛ لا يصح تعميم الخطر على PR القادمة من Fork التي لا تتلقى الأسرار عادةً في حدث `pull_request`. |
| البناء | [`.github/workflows/build.yml`](https://github.com/areagleegy/AshenKingdoms/blob/main/.github/workflows/build.yml) — `346e195d025fa51116bf74d598edfb920fd18946` | مهام منفصلة لتصدير Web وAndroid، بصلاحيات `contents: read`; مراجع Actions محددة بعلامات إصدار مثل `@v4`. | التثبيت بأرقام SHA كاملة ليس مطبقاً في هذا الملف؛ هذا تحسين أمني مقترح، لا دليل على أن إجراءً بعينه ضار. |
| تثبيت المحتوى | [`scripts/content/content_package_installer.gd`](https://github.com/areagleegy/AshenKingdoms/blob/main/scripts/content/content_package_installer.gd) — `4c76ad7f3a64a027aab9ec8bdd4f2fe14c3af82d` | يفحص حجم ZIP وبصمته، ويساوي محتويات الأرشيف بسجل الملفات، ويتحقق من المسارات والأحجام والبصمات الفردية، ثم يستخرج إلى staging ويرقّي المجلد بالتسمية. | ضوابط تحقق موجودة بالفعل. ما يزال مطلوباً اختبار فشل الكتابة، تبدل الملف بين التحقق والاستخراج، واستهلاك الذاكرة؛ الجدول في خطة الاختبار معايير قبول، وليس ادعاءً بأن كل سيناريو اختُبر. |
| إدارة الجلسة | [`scripts/core/network_manager.gd`](https://github.com/areagleegy/AshenKingdoms/blob/main/scripts/core/network_manager.gd) — `fa7b2f73b9007ffceac1a8cf9f9046c01952eb9b` | يدير إنشاء جلسات ENet وإشارات الاتصال والانقطاع والمهلات. | ليس وحده مصدر إثبات أن منطق القتال موثوق؛ لذلك فُحصت ملفات الحركة والقتال منفصلة. |
| إدخال اللاعب الشبكي | [`scripts/networking/network_avatar.gd`](https://github.com/areagleegy/AshenKingdoms/blob/main/scripts/networking/network_avatar.gd) — `7da0a7a4cb22ce0de36c4f7dba80eab17e7a9ecc` | RPC إدخال اللاعب يتحقق من أن المرسل يطابق مالك الكيان وأن التنفيذ على الخادم. نسخة `main` التي قُرئت لا تحتوي على فحص صريح للقيم غير المحدودة أو حوض رموز لمعدل الإدخال في هذا المسار. | فجوة تحقق إدخال محددة بالكود. لا يعني ذلك أن العميل يحدد الصحة أو الضرر مباشرة؛ توجد دوال ضرر وخبرة محمية بفحص `multiplayer.is_server()`. |
| أعداء الشبكة | [`scripts/networking/network_enemy.gd`](https://github.com/areagleegy/AshenKingdoms/blob/main/scripts/networking/network_enemy.gd) — `7156cd52be4f730530803e10955d0999eeacd5a9` | دوال الضرر وتحديث حياة العدو تقيد التغيير بالخادم. | دليل على حراسة دوال محددة؛ لا يثبت خلو كل RPC في المشروع من المشكلات. |
| هيكل الخادم | [`scripts/core/server.gd`](https://github.com/areagleegy/AshenKingdoms/blob/main/scripts/core/server.gd) — `600a7c3c595a02b77a74da7326939e291ad5e78e` | يصف نفسه صراحةً بأنه placeholder، ولا ينفذ إدارة جلسة أو تكرار كيانات. | لا ينبغي تقديم هذا الملف منفرداً كخادم إنتاجي مكتمل. توجد إدارة جلسات منفصلة عبر `NetworkManager`. |

## فحص إعدادات الحماية

- استجابة `GET /repos/areagleegy/AshenKingdoms/rulesets` أعادت `[]` وقت الفحص.
- استجابة `GET /repos/areagleegy/AshenKingdoms/rulesets?includes_parents=true` أعادت `[]` وقت الفحص.
- طلب `GET /repos/areagleegy/AshenKingdoms/branches/main/protection` أعاد `403 Resource not accessible by integration`.

**النتيجة:** لم تظهر Rulesets في استجابتي القائمة المتاحتين، لكن صلاحية قراءة Branch Protection رفضتها واجهة GitHub الموصولة. لذلك لا يبرر هذا الدليل الجزم بأن الحماية التقليدية مفعلة أو غير مفعلة، ولا يثبت صلاحيات التجاوز أو Required Status Checks. يجب على مالك المستودع التحقق من صفحة Settings باستخدام صلاحية مناسبة، ثم فحص القواعد المطلوبة وصلاحيات bypass وسياق الفحص الإلزامي.

## التغييرات المثبتة في فرع الإصلاح

في `hardening/save-system-v1` أضيفت تغييرات منفصلة عن `main`:

- `tools/test_ci_security.py`: اختبار آلي يمنع تمرير بيانات اعتماد التشخيص الخارجي إلى Workflow التحقق.
- `.github/workflows/validate.yml`: خطوة التشخيص المحلي تضبط `ASHEN_AI_DIAGNOSE=false` ولا تستقبل `ASHEN_AI_API_KEY` أو `ASHEN_AI_ENDPOINT`.
- `scripts/core/save_system.gd`: ملف مؤقت، التحقق من النص المكتوب، تدوير احتياطي من ملف أساسي صالح فقط، استعادة من staged/backup، وحالة تحميل تفصيلية مع إبقاء `load_game() -> Dictionary` للتوافق.
- `tests/save_system_security_test.gd`: تغطية لاستعادة backup، وعدم استبدال backup صالح بحفظ أساسي تالف، والتمييز بين `not_found` و`invalid`.
- `docs/SAVE_HARDENING_AR.md`: بروتوكول الحفظ وحدود الضمان الموثقة.

سجل CI المشار إليه ناجح للـ commit المحدد أعلاه. كل commit لاحق يحتاج التحقق من نتيجة CI الخاصة به؛ لا تستخدم نجاح run سابق كدليل لنسخة أحدث.

## حدود معروفة وخطوات لاحقة

1. لم تُقرأ إعدادات Branch Protection بسبب رفض الصلاحية؛ يلزم فحصها من واجهة المالك قبل إعلان أن دمج `main` مقيد فعلياً.
2. لا يدعي Patch الحفظ مخططاً دلالياً شاملاً للصحة والخبرة والجرد والمهمات؛ هذه البيانات تحتاج عقداً موثقاً بعد حصر جميع المستدعين.
3. ملف الحفظ يستخدم staged rename ونسخة احتياطية؛ هذا ليس ضماناً لاستبدال ذري أو دوام بعد انقطاع الطاقة على كل منصة.
4. التحقق من حزمة ZIP يفحص الأرشيف قبل فتحه ثانيةً للاستخراج؛ اختبار تغير الأرشيف بين التحقق والاستخراج، وفحص أخطاء الكتابة أثناء الاستخراج، ما زالا مطلوبين قبل التفعيل الإنتاجي.
5. يجب أن تشمل المراجعة الأمنية الشبكة جميع RPC ومنطق الصحة والضرر والخبرة وإدارة دورة حياة الكيانات، لا `network_manager.gd` وحده.
6. جميع مراجع Actions في الملفين المذكورين يجب أن تخضع لعملية مراجعة وتثبيت SHA كاملة قبل اعتماد سياسة توريد برمجيات مشددة.
