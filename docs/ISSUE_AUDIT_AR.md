# تدقيق Issues وPull Requests — ممالك الرماد

> تاريخ اللقطة: 2026-10-20 (UTC). هذا سجل مراجعة مبني على بيانات GitHub والوثائق المتاحة في هذا التاريخ؛ يجب تحديثه عند تغيّر الحالات أو الالتزامات. الحالة في GitHub منفصلة عن الحالة الفعلية للميزة.

## الخلاصة التنفيذية

- المستودع: `areagleegy/AshenKingdoms`, الفرع الافتراضي `main`, المشروع Godot 4.6 / GDScript.
- جرد GitHub عند الفحص: 3 Issues مفتوحة (#20–#22)، ولا توجد Issues مغلقة مستقلة في نتيجة API؛ 8 Pull Requests مفتوحة (#24–#31) و20 مغلقة (#1–#19 و#23).
- لا يعني إغلاق PR أن التغيير دُمج: PRs #4–#8 مغلقة كفروع مستبدلة، بينما توضح أوصافها أن التنفيذ اللاحق أُدمج عبر PRs أحدث.
- لا يعني نجاح CI قبولًا إنتاجيًا. لم يُجرِ هذا التدقيق اختبارًا فعليًا على هاتف Android أو متصفح متصل بخادم منشور، ولم يجر قياسًا مستقلًا للأداء أو الذاكرة أو زمن بدء التشغيل.
- توصية الإصدار الحالية: **NO-GO للإصدار الإنتاجي** حتى إغلاق بوابات القبول اليدوي والأصول والأمن والتوقيع المحددة في Issue #20.

## منهج التصنيف

- **مدمج**: بيانات GitHub تشير إلى `merged_at` غير فارغ.
- **مغلق/مستبدل**: PR مغلق دون دمج، ويذكر وصفه أن PR أحدث أخذ العمل.
- **مفتوح — مسودة**: لم يدمج، ولا يُعامل كميزة موجودة في `main`.
- **مفتوح — للمراجعة**: لم يدمج؛ يلزم مراجعة التغيير ونتائج CI على رأس الفرع الحالي.
- **الحالة الفعلية للميزة** تستند إلى README وPROJECT_STATUS_AR وTEST_PLAN وأوصاف PR وتشغيلات Actions التي أمكن فحصها؛ ليست إعادة تنفيذ مستقلة لكل الاختبارات.

## Issues المفتوحة

| Issue | العنوان | الحالة الفعلية والتوصية |
|---|---|---|
| [#20](https://github.com/areagleegy/AshenKingdoms/issues/20) | Release gate: verify target devices, final assets, and production packaging | **مانع إصدار P0**. لم يثبت قبول Android على جهاز حقيقي، ولا قبول Web مستضاف، ولا توقيع الإنتاج، ولا مراجعة الترخيص النهائية، ولا قرار go/no-go موثق. أبقها مفتوحة حتى تقديم أدلة لكل بند منطبق. |
| [#21](https://github.com/areagleegy/AshenKingdoms/issues/21) | Implement and verify multiplayer transport for Web before claiming platform parity | **مانع ادعاء دعم اللعب الجماعي في Web**. يوجد مسار WebSocket تجريبي واختبارات loopback؛ لا يوجد إثبات متصفح حقيقي إلى endpoint منشور عبر `wss://`. المصادقة، وضبط المعدل لكل مسار، واختبارات الإساءة/الحمل والضوابط التشغيلية غير مثبتة. |
| [#22](https://github.com/areagleegy/AshenKingdoms/issues/22) | Add a verified free/open-license asset pack and provenance records | **مانع اعتماد الأصول النهائية**. يجب ربط كل أصل مصدره ومؤلفه والترخيص الدقيق والإسناد والتعديلات وحقوق إعادة التوزيع، وتسجيله في `assets/asset_manifest.json` و`docs/ASSET_CREDITS.md` والتحقق منه. |

لا توجد Issues مغلقة مستقلة ضمن نتيجة API في لقطة المراجعة؛ عناصر PR المغلقة أدناه ليست Issues.

## Pull Requests المفتوحة

| PR | العنوان | الحالة المسجلة | التقييم والتصرف التالي |
|---|---|---|---|
| [#24](https://github.com/areagleegy/AshenKingdoms/pull/24) | Add experimental WebSocket multiplayer and fantasy battle royale prototype | مسودة مفتوحة | CI ناجح على commit `03e680c2725a9b268440112798cd99e7337ecefc` (Validate run [39428604979](https://github.com/areagleegy/AshenKingdoms/actions/runs/39398604979)، Build run [39428605372](https://github.com/areagleegy/AshenKingdoms/actions/runs/39398605372)؛ روابط التشغيل كما وردت في وصف PR). يثبت ذلك الخطوات الآلية فقط. لا يوجد اختبار WSS منشور أو قبول Android فعلي أو اختبار حمل/أمن إنتاجي. أبقه مسودة حتى المراجعة والقبول. |
| [#25](https://github.com/areagleegy/AshenKingdoms/pull/25) | توثيق: إضافة مرجع شامل ومخططات المشروع | مفتوح، غير مسودة | تغيير توثيقي. راجع دقة المرجع والروابط ومخططات Mermaid، ثم تحقق من CI على HEAD الحالي. لا توجد حالة CI مؤكدة من بيانات التشغيل التي فُحصت لهذا HEAD. |
| [#26](https://github.com/areagleegy/AshenKingdoms/pull/26) | docs: consolidate master roadmap and project changelog | مفتوح، غير مسودة | خارطة طريق وسجل تغييرات؛ لا يغير اللعبة. تأكد من أن أهداف 8→16→32→50→100 موصوفة كأهداف قياس لا كقدرات مثبتة، وأن النطاق المعتمد Android + Web لا يوحي بدعم Web multiplayer حاليًا. تحقق من CI على HEAD. |
| [#27](https://github.com/areagleegy/AshenKingdoms/pull/27) | docs: organize repository documentation, diagrams, and references | مفتوح، غير مسودة | توثيق تدقيق المستودع ومراجع رسمية. راجع عدم تكرار أو تعارض الوثائق الجديدة مع #25 و#26، وصحة الروابط، ثم CI على HEAD. لم تُثبت حالة CI الحالية من بيانات الحالة المتاحة. |
| [#28](https://github.com/areagleegy/AshenKingdoms/pull/28) | Harden network input and damage edge cases | مسودة مفتوحة | تحسين أمني مهم: رفض قيم الحركة/الضرر غير الصالحة، حد قبول مدخلات، ومنع تكرار spawn، وتثبيت Actions على SHAs. وصف PR يذكر نجاح CI على commit أقدم `006d601974094bee2fa7bf2575d732b637cb2493` لا على HEAD `afa0f8103c33a0ae9f5bfca87a3a90f396016704`; الفرع موصوف بأنه 54 commit أمام main و5 خلفه وmergeable=false. حدّثه من main، حل التعارضات، أعد CI على HEAD، وراجع أن الحد الزمني لا يمكن تجاوزه عبر RPC بديل. |
| [#29](https://github.com/areagleegy/AshenKingdoms/pull/29) | docs: establish evidence-based execution baseline | مسودة مفتوحة | سجل baseline مفيد يفصل تعريف الاختبار عن نتيجته. وصف PR يقول إن Godot CLI لم يكن متاحًا محليًا وإن CI مطلوب؛ لا تسجّل نتائج غير منفذة. تحقق من CI والروابط على HEAD قبل الدمج. |
| [#30](https://github.com/areagleegy/AshenKingdoms/pull/30) | test: cover the solo vertical slice end to end | مسودة مفتوحة | يضيف اختبار تكامل للمسار الفردي من القائمة إلى اللعب والحوار والقتال والمكافأة والحفظ/التحميل. وصف PR يقول إن نتيجة CI على HEAD لم تثبت بعد؛ لا تعتبر المهمة مقبولة حتى تنجح الاختبارات فعليًا وتراجع حدود إعادة بناء المشاهد مقابل إعادة تشغيل التطبيق. |
| [#31](https://github.com/areagleegy/AshenKingdoms/pull/31) | fix: harden save schema, backups, and recovery | مسودة مفتوحة | تحقق آلي معلن على HEAD `d9ac7bc0c9b083a85a7fdd53dc99a0458a0263f6`: [Validate #39428663423](https://github.com/areagleegy/AshenKingdoms/actions/runs/39428663423) و[Build #39428663558](https://github.com/areagleegy/AshenKingdoms/actions/runs/39428663558) ناجحان. تشمل التغييرات schema version، والتحقق من القيم، ونسخة احتياطية واستعادة. لم يثبت تحمل انقطاع الطاقة/قتل العملية/نفاد المساحة على جهاز حقيقي. راجع التوافق والترحيل، ثم اختبر فشل IO عمليًا قبل اعتبار حفظ المستخدم محميًا. |

**ملاحظة حول #24:** روابط التشغيل المذكورة في نص PR هي الأدلة المنشورة هناك؛ عناوينها وأرقامها في وصف PR تتطلب التحقق المباشر عند إجراء مراجعة إصدار جديدة. لا تُنقل نتيجة تشغيل من commit إلى commit آخر.

## Pull Requests المغلقة

| PR | العنوان | حالة الإغلاق | التقييم الحالي |
|---|---|---|---|
| [#23](https://github.com/areagleegy/AshenKingdoms/pull/23) | docs: reorganize documentation and clarify release status | مدمج | توثيق الحالة ونطاق الإصدار؛ مرجع أساسي لكن ينبغي مراجعته مع الوثائق الأحدث. |
| [#19](https://github.com/areagleegy/AshenKingdoms/pull/19) | Fix: reject GDScript parse failures in resource smoke test | مدمج | يقوي فحص تحميل السكربتات؛ لا يغني عن اختبارات السلوك. |
| [#18](https://github.com/areagleegy/AshenKingdoms/pull/18) | Fix: make runtime input registration idempotent | مدمج | يمنع تكرار تسجيل أحداث الإدخال؛ راجع اختبارات الانحدار عند تعديل InputMap. |
| [#17](https://github.com/areagleegy/AshenKingdoms/pull/17) | Test: prevent missing touch-control node references | مدمج | يغطي مراجع عقد اللمس؛ لا يثبت تجربة اللمس على جهاز فعلي. |
| [#16](https://github.com/areagleegy/AshenKingdoms/pull/16) | Docs: refresh network acceptance and Termux setup instructions | مدمج | تحديث إرشادات القبول والشبكة؛ اختبار الشبكة الفعلي ما زال بوابة مستقلة. |
| [#15](https://github.com/areagleegy/AshenKingdoms/pull/15) | Docs: reconcile project status and validate Markdown links | مدمج | يحسن اتساق الوثائق وروابطها؛ لا يعني أن جميع الميزات موثقة كجاهزة. |
| [#14](https://github.com/areagleegy/AshenKingdoms/pull/14) | Fix missing LookPad reference in touch controls | مدمج | يصلح مرجع عقدة مفقودة؛ يلزم استمرار اختبار مشهد اللمس. |
| [#13](https://github.com/areagleegy/AshenKingdoms/pull/13) | feat: integrate ENet multiplayer prototype on current main | مدمج | يدمج نموذج ENet للمضيف/العميل؛ لا توجد مصادقة أو استضافة عامة أو حفظ شبكي دائم مثبت. |
| [#12](https://github.com/areagleegy/AshenKingdoms/pull/12) | feat: integrate local character asset and licensing pipeline | مدمج | يدمج أدوات الأصول وسجل الترخيص؛ لا يثبت اكتمال نموذج/أصول نهائية مرخصة. |
| [#11](https://github.com/areagleegy/AshenKingdoms/pull/11) | test: integrate gameplay regression suite on current main | مدمج | يضيف اختبارات انحدار؛ راجع نطاقها ولا تعتبرها بديلًا عن قبول المستخدم. |
| [#10](https://github.com/areagleegy/AshenKingdoms/pull/10) | feat: add optional Android content pack foundation | مدمج | أساس فهرس موقّع وفحص SHA-256 ومسارات آمنة؛ تنزيل المحتوى الإنتاجي معطل افتراضيًا، ولا توجد خدمة توزيع إنتاجية مثبتة. |
| [#9](https://github.com/areagleegy/AshenKingdoms/pull/9) | Add mobile touch controls and vertical-slice architecture notes | مدمج | يضيف عناصر التحكم باللمس؛ القبول على هاتف فعلي ما زال مطلوبًا. |
| [#8](https://github.com/areagleegy/AshenKingdoms/pull/8) | Add gameplay regression coverage for Godot 4.6 | مغلق دون دمج؛ مستبدل | وصف PR يذكر أن مجموعة الانحدار نُقلت إلى #11. لا تُعامل هذه النسخة المغلقة كتنفيذ مستقل. |
| [#7](https://github.com/areagleegy/AshenKingdoms/pull/7) | ربط مسار مجاني محلي للأصول البصرية والصوتية | مغلق دون دمج؛ مستبدل | وصف PR يذكر أن المسار أُعيد دمجه في #12. |
| [#6](https://github.com/areagleegy/AshenKingdoms/pull/6) | إضافة تشخيص آلي للاختبارات ومساعد AI اختياري | مغلق دون دمج؛ مستبدل | وصف PR يذكر أن أدوات التشخيص أصبحت ضمن #11. المساعد أداة اقتراح وليس إصلاحًا تلقائيًا موثوقًا. |
| [#5](https://github.com/areagleegy/AshenKingdoms/pull/5) | ربط أدوات أصول البطل وفحصها في Godot | مغلق دون دمج؛ مستبدل | وصف PR يذكر أن التكامل الحالي موجود في #12. |
| [#4](https://github.com/areagleegy/AshenKingdoms/pull/4) | Add ENet session menu and authoritative movement prototype | مغلق دون دمج؛ مستبدل | وصف PR يذكر أن نموذج الشبكة أُعيد دمجه في #13. |
| [#3](https://github.com/areagleegy/AshenKingdoms/pull/3) | Add automated gameplay smoke tests | مدمج | يغطي منطق اللعب والحفظ الأساسي؛ ليس اختبار قبول شاملًا. |
| [#2](https://github.com/areagleegy/AshenKingdoms/pull/2) | Add dialogue graphs, NPC interaction, and dialogue UI | مدمج | يضيف الحوار وNPC والاختيارات؛ توثيق المشروع يصف التكامل الشبكي للحوار والمهام بأنه غير مكتمل. |
| [#1](https://github.com/areagleegy/AshenKingdoms/pull/1) | Add playable vertical slice with progression and quests | مدمج | أساس النموذج الأولي القابل للعب؛ لا يساوي لعبة نهائية مكتملة المحتوى. |

## بوابات القبول الموصى بها

### P0 — قبل أي إصدار إنتاجي

1. **Android:** تثبيت APK على جهاز ARM64 فعلي، وتوثيق طراز الجهاز وإصدار Android ونتائج الحركة واللمس والكاميرا والقتال والحوار والجرد والحفظ/التحميل والإيقاف والاستئناف وإعادة التشغيل.
2. **Web:** نشر الملفات عبر HTTP/HTTPS واختبار المتصفحات وأحجام العرض المتفق عليها، وفحص console/runtime errors. يجب أن يظل وصف اللعب الجماعي غير مدعوم إلى حين اجتياز اختبار WSS الفعلي.
3. **حفظ البيانات:** اختبار ترحيل الحفظ القديم، ورفض مخطط أحدث غير مدعوم، وفساد الملف الأساسي، واستعادة النسخة الاحتياطية، وفشل الكتابة، وقطع العملية/نفاد المساحة على بيئة اختبار معزولة. لا تستخدم ملف حفظ حقيقيًا دون نسخة احتياطية.
4. **الأصول:** تدقيق كل ملف موزع مقابل مصدره والترخيص والإسناد وحقوق التعديل وإعادة التوزيع، ثم التحقق من سجل الأصول بأداة المشروع.
5. **التوقيع والتوزيع:** تحديد اسم التطبيق ومعرّف Android وقناة التوزيع وسياسة الإصدار، وحماية مفاتيح التوقيع عبر أسرار CI دون وضعها في المستودع.
6. **قرار الإصدار:** تسجيل قبول/قبول مشروط/رفض مع الروابط والـ SHA-256 والالتزام ونتائج الاختبار والاستثناءات المعتمدة.

### P1 — قبل إعلان اللعب الجماعي جاهزًا

- تثبيت نموذج السلطة الخادمية، والتحقق من ملكية اللاعب والمدخلات، وتغطية تحديد المعدل لكل مسارات RPC والنقل.
- اختبار الانضمام والمغادرة والانقطاع وإعادة الاتصال والرسائل غير الصالحة وتزامن الحالة من متصفحات/أجهزة حقيقية.
- اختبار flood/abuse والحمل وقياس CPU والذاكرة والكمون ومعدل التحديث تحت حمل متزايد؛ لا يُعد هدف 100 لاعب قدرة مدعومة حتى يُقاس ويُوثق.
- توثيق المصادقة والهوية وحدود الثقة والتشغيل والمراقبة والاستجابة للأعطال قبل الاستضافة العامة.

### P2 — الحجم والأداء والجودة

- لا توجد في الأدلة التي راجعتها نتائج قياس قابلة للمقارنة لأداء اللعبة على جهاز مستهدف أو زمن البدء أو استهلاك الذاكرة؛ لا أوصي بتغييرات تحسين مبكرة دون baseline.
- قياس حجم APK وحجم Web المنقول فعليًا منفصلين عن حجم أرشيف Artifact، مع حفظ commit وبيئة البناء وSHA-256 لكل قياس.
- تحسين الأصول عبر نماذج وخامات وصوتيات مضغوطة ومقاسات مناسبة للمنصة، بعد إثبات حقوقها، ثم إعادة قياس الجودة والأداء والحجم.
- الاستمرار في فحوص الموارد والانحدار والتوثيق وتثبيت GitHub Actions على SHAs موثقة ومراجعة التحديثات.

## الأدلة الرئيسية

- [GitHub Issues](https://github.com/areagleegy/AshenKingdoms/issues)
- [Pull Requests](https://github.com/areagleegy/AshenKingdoms/pulls)
- [README.md](https://github.com/areagleegy/AshenKingdoms/blob/main/README.md)
- [حالة المشروع بالعربية](https://github.com/areagleegy/AshenKingdoms/blob/main/docs/PROJECT_STATUS_AR.md)
- [خطة الاختبار](https://github.com/areagleegy/AshenKingdoms/blob/main/docs/TEST_PLAN.md)
- [Issue #20 — بوابة الإصدار](https://github.com/areagleegy/AshenKingdoms/issues/20)
- [Issue #21 — Web multiplayer](https://github.com/areagleegy/AshenKingdoms/issues/21)
- [Issue #22 — الأصول والتراخيص](https://github.com/areagleegy/AshenKingdoms/issues/22)
- [Validate #31](https://github.com/areagleegy/AshenKingdoms/actions/runs/39428663423) و[Build #31](https://github.com/areagleegy/AshenKingdoms/actions/runs/39428663558)

## مراجع معيارية للتنفيذ

هذه مراجع خارجية للمنهج والأدوات، وليست دليلًا على اجتياز المشروع للقبول:

- [Godot — التصدير](https://docs.godotengine.org/en/stable/tutorials/export/index.html)
- [Godot — الشبكات عالية المستوى](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [GitHub — مراجعة طلبات الدمج](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests)
- [GitHub Actions — استخدام الأسرار بأمان](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)
- [SPDX — قائمة معرّفات التراخيص](https://spdx.org/licenses/)

## سجل القرار

- **الحالة:** مراجعة مكتبية مستندة إلى GitHub والوثائق، وليست شهادة قبول إنتاجي.
- **قرار الإصدار:** NO-GO إلى أن تُغلق بوابات P0 بأدلة قابلة للتدقيق.
- **حدود الثقة:** نتائج CI مرتبطة بالالتزام المحدد الذي شُغّلت عليه؛ لا تنقل النتيجة إلى HEAD مختلف. لا تُسجل اختبارًا يدويًا أو قياسًا لم يُنفذ.
- **إجراء التحديث:** عند كل مراجعة، سجّل وقت اللقطة، SHA للفرع الأساسي ورؤوس PR، روابط تشغيل CI، ونتائج قبول الأجهزة والمتصفحات، ثم حدّث هذا الملف.
