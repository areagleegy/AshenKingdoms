# خريطة التداخل والاعتماد بين Pull Requests — ممالك الرماد

> **لقطة المراجعة:** 2026-10-23 UTC  
> **المصدر:** بيانات GitHub المفتوحة وقوائم الملفات المتغيرة (Files changed) لطلبات الدمج المشار إليها أدناه.  
> **الغرض:** تقليل دمج تغييرات متعارضة في الملفات نفسها، وتوضيح ترتيب المراجعة. هذه خريطة تداخل ملفات، وليست مراجعة كاملة لمنطق كل PR.

## 1. قاعدة عامة

وجود عدة Pull Requests مفتوحة لا يعني أنها جميعًا تغييرات مستقلة قابلة للدمج المتتابع. قبل دمج أي PR:
1. أعد جلب قائمة الملفات المتغيرة للـ PR ورأس الفرع الحالي.
2. قارنها بطلبات الدمج الأخرى التي تغيّر الملفات نفسها.
3. اقرأ وصف التبعيات والتكامل، وحدد ما إذا كان أحد الفروع مبنيًا على فرع آخر.
4. اختر تغييرًا مرجعيًا أو PR تجميعيًا عند تداخل المنطق، ثم أعد تشغيل الاختبارات على نتيجة الدمج الفعلية.
5. لا تدمج مجموعة من الفروع المتوازية لمجرد أن CI نجح لكل فرع على حدة.
6. سجّل قرار الدمج أو الاستبدال أو الإغلاق في GitHub بدل ترك عدة طلبات متنافسة بلا تفسير.

**مهم:** الاختبارات الناجحة على فرعين منفصلين لا تثبت أن جمع التغييرات دون تعارض دلالي أو تعارض في السلوك.

## 2. مجموعة حفظ اللعبة — أعلى تداخل في الملفات

طلبات الدمج التي تمت مراجعة قوائم ملفاتها:
- [PR #93](https://github.com/areagleegy/AshenKingdoms/pull/93) — harden local save validation and recovery.
- [PR #74](https://github.com/areagleegy/AshenKingdoms/pull/74) — save integrity, validation, and recovery.
- [PR #69](https://github.com/areagleegy/AshenKingdoms/pull/69) — harden local saves and network input RPCs.
- [PR #61](https://github.com/areagleegy/AshenKingdoms/pull/61) — recoverable save writes and atomic-save tests.
- [PR #54](https://github.com/areagleegy/AshenKingdoms/pull/54) — interrupted-write protection.
- [PR #37](https://github.com/areagleegy/AshenKingdoms/pull/37) — protect save data during interrupted writes.
- [PR #66](https://github.com/areagleegy/AshenKingdoms/pull/66) — Android save persistence and regression tests.
- [PR #71](https://github.com/areagleegy/AshenKingdoms/pull/71), [PR #51](https://github.com/areagleegy/AshenKingdoms/pull/51), [PR #36](https://github.com/areagleegy/AshenKingdoms/pull/36), [PR #35](https://github.com/areagleegy/AshenKingdoms/pull/35), [PR #32](https://github.com/areagleegy/AshenKingdoms/pull/32), [PR #31](https://github.com/areagleegy/AshenKingdoms/pull/31) — save/network hardening iterations that also touch overlapping implementation or test files.
- Issue tracking: [Issue #91](https://github.com/areagleegy/AshenKingdoms/issues/91).

### التداخل المثبت من قوائم الملفات

| الملفات المشتركة | PRs المرصودة | دلالة التداخل |
|---|---|---|
| `scripts/core/save_system.gd` | #93, #74, #69, #61, #54, #71, #51, #37, #36, #35, #32, #31, #66 | هذه ليست تغييرات مستقلة في نظام الحفظ؛ قد تختلف استراتيجية الكتابة والنسخ والاستعادة بين الفروع. |
| `tests/gameplay_regression_test.gd` و/أو `tests/gameplay_smoke_test.gd` | #93, #74, #69, #61, #54, #71, #51, #37, #36, #31 | اختلافات الاختبار قد تُطغى عند الدمج؛ اجمع تغطية كل السيناريوهات في PR نهائي واحد. |
| `scripts/networking/network_avatar.gd` | #69, #61, #71, #66, #51, #36, #35, #32 | تغييرات حفظ/شبكة متداخلة. راجع حد الثقة وسياسة التحقق من RPC بدل اختيار نسخة ملف عشوائية. |
| `.github/workflows/validate.yml` و/أو `build.yml` | #93, #69, #61, #71, #66, #51, #31 | تعديل workflow قد يزيل فحصًا موجودًا أو يكرر الاختبار؛ حافظ على جميع بوابات التحقق. |

### التوصية

- لا تدمج كل هذه الفروع بالتتابع بلا مراجعة. حدد PR الأساسي الذي يجمع متطلبات الحفظ المطلوبة، وقارن التغييرات الفعلية والمراجعات والحالة الحالية لكل فرع.
- استخدم [Issue #91](https://github.com/areagleegy/AshenKingdoms/issues/91) لتتبع معايير سلامة الحفظ والتحقق من حالة اللعبة.
- لا تعلن حماية حفظ مكتملة قبل اختبار الكتابة الذرية، وفشل الكتابة، والملف التالف، واستعادة النسخة الاحتياطية، والحدود والترحيل.
- لا تُغلق الطلبات الأخرى إلا بعد التأكد من نقل تغييراتها المطلوبة أو توثيق أنها مستبدلة.

## 3. مجموعة التحقق من مدخلات الشبكة وRPC

طلبات الدمج التي تمت مراجعة قوائم ملفاتها:
- [PR #75](https://github.com/areagleegy/AshenKingdoms/pull/75)
- [PR #56](https://github.com/areagleegy/AshenKingdoms/pull/56)
- [PR #52](https://github.com/areagleegy/AshenKingdoms/pull/52)
- ومعها التداخلات الشبكية في [PR #61](https://github.com/areagleegy/AshenKingdoms/pull/61)، [PR #69](https://github.com/areagleegy/AshenKingdoms/pull/69)، [PR #71](https://github.com/areagleegy/AshenKingdoms/pull/71)، [PR #66](https://github.com/areagleegy/AshenKingdoms/pull/66)، [PR #51](https://github.com/areagleegy/AshenKingdoms/pull/51)، [PR #36](https://github.com/areagleegy/AshenKingdoms/pull/36)، [PR #35](https://github.com/areagleegy/AshenKingdoms/pull/35)، [PR #32](https://github.com/areagleegy/AshenKingdoms/pull/32).

### الملفات المشتركة

- `scripts/networking/network_avatar.gd` يظهر في عدة فروع.
- `tests/network_combat_smoke_test.gd` وملفات اختبار RPC تظهر في أكثر من فرع.
- `docs/NETWORKING.md` و`docs/NETWORK_THREAT_MODEL_AR.md` تتغير في عدة طلبات.

### التوصية

- راجع شروط قبول المدخلات، القيم غير المنتهية، حدود المتجهات، وتحديد المعدل على الخادم معًا.
- تأكد من أن الحد لا يمكن الالتفاف حوله بإرسال RPC بديل أو إعادة الاتصال أو طلب من فئة أخرى.
- حافظ على اختبارات الانحدار الحالية عند دمج تغييرات لاحقة.
- وثّق بوضوح أن فحص loopback لا يثبت أمان الإنترنت العام أو مكافحة غش إنتاجية.
- لا تدمج نسختين من `network_avatar.gd` من دون مقارنة دلالية للقيود وترتيب التحقق.

## 4. سلامة حزم المحتوى ومصدر الأصول

- [PR #77](https://github.com/areagleegy/AshenKingdoms/pull/77) — التحقق الصارم من روابط حزم المحتوى.
- [PR #86](https://github.com/areagleegy/AshenKingdoms/pull/86) — التحقق من مصدر المحتوى وسلامته.
- [Issue #47](https://github.com/areagleegy/AshenKingdoms/issues/47) — بوابة التحقق من المصدر والسلامة والتراجع.

**تداخل الملفات الذي تم رصده:** `scripts/content/content_catalog.gd`، `tests/content_catalog_smoke_test.gd`، `tools/package_content.py`، `tools/test_package_content.py`، و`docs/NETWORK_THREAT_MODEL_AR.md`.

### التوصية

يجب أن يجمع مسار الدمج النهائي التحقق من HTTPS/الرابط والمصدر والتوقيع والتكامل وحجم الحزمة والمسارات والتراجع عند الفشل. لا تفعّل التنزيل الإنتاجي لمجرد وجود تحقق URL أو توقيع فهرس في فرع منفصل. تحقق من كل PR وعلى رأس الفرع بعد أي إعادة تأسيس.

## 5. الصوت والأصول المرئية

- [PR #49](https://github.com/areagleegy/AshenKingdoms/pull/49) يغير الأصول وسجل الأصول والتراخيص، وملفات اللعب، وسير عمل التحقق.
- [PR #50](https://github.com/areagleegy/AshenKingdoms/pull/50) يضيف ملفات صوتية وتعديلات في `scripts/audio/audio_manager.gd` و`tests/audio_asset_smoke_test.gd` وسجل الأصول.
- [PR #59](https://github.com/areagleegy/AshenKingdoms/pull/59) يغير كذلك `scripts/audio/audio_manager.gd` و`tests/audio_asset_smoke_test.gd` ووثيقة حزمة الصوت؛ وصفه الحالي يشير إلى أنه مبني على فرع PR #50، ويوصي بمراجعة #50 أولًا.
- [PR #58](https://github.com/areagleegy/AshenKingdoms/pull/58) عبارة عن خطة تغطية أصول مرئية وصوتية.

### ترتيب المراجعة

1. راجع ترخيص الأصول وسجل المصادر قبل قبول الملفات في الإصدار.
2. راجع [PR #50](https://github.com/areagleegy/AshenKingdoms/pull/50) ومتطلباته أولًا ثم [PR #59](https://github.com/areagleegy/AshenKingdoms/pull/59) لأنه يصرح باعتماده على فرع #50.
3. راجع تداخل الأصول وسير عمل التحقق في #49، واحتفظ باختبارات الصوت والبطل والعدو والـ asset manifest.
4. لا تخلط بين وجود ملفات WAV/GLB داخل فرع وبين قبولها وترخيصها واختبارها في حزمة الإصدار.

## 6. تشخيص Android وQA والذكاء الاصطناعي

- [PR #80](https://github.com/areagleegy/AshenKingdoms/pull/80) — تقرير QA runtime وتغييرات build/validate وواجهة التشغيل.
- [PR #89](https://github.com/areagleegy/AshenKingdoms/pull/89) — اختبارات أجهزة Android والتحليل المحلي، ويشارك ملفات في واجهة اللعبة واللاعب والعدو والمهمة والشبكة و`tests/qa_test_runner_smoke_test.gd`.
- [PR #92](https://github.com/areagleegy/AshenKingdoms/pull/92) — سير عمل مستقل لإنتاج APK تجريبي مع تشخيص.

### التوصية

- ادمج تقارير QA مع الحفاظ على الفصل بين APK تشخيصي ونسخة المستخدم.
- لا تضمّن مفاتيح خدمة أو أسرارًا في APK أو السجلات.
- اجعل التحليل الآلي اقتراحًا يخضع للمراجعة، واحفظ تقريرًا يمكن ربطه برقم إصدار وcommit.
- لا تُعلن نجاح اختبار جهاز فعلي إذا كانت النتيجة مجرد بناء CI أو محاكاة.
- احتفظ بملفات workflow منفصلة عندما يكون الغرض مختلفًا، ولا تلغِ بوابات CI الحالية دون بديل واضح.

## 7. المحتوى والعالم

- [PR #67](https://github.com/areagleegy/AshenKingdoms/pull/67) يضيف مواصفات العالم وفهرسًا وملفات بناء المنطقة الأولى ومجموعة اختبارات لهذه المكونات.
- وثائق العالم والمخططات تُعامل كمواصفات حتى تثبت وجود الملفات والموارد الفعلية واختبارات سلوكها.
- افصل البيانات عن المنطق القابل للتنفيذ، وتحقق من المخطط والمعرفات الثابتة والروابط بين المناطق والتفاعلات.
- لا تعلن اكتمال العالم أو الشخصية أو المركبة استنادًا إلى مخطط التصميم فقط.

## 8. مجموعة توثيق المشروع

طلبات الدمج التي تتداخل في الوثائق أو فهرس الوثائق تشمل:
- [PR #97](https://github.com/areagleegy/AshenKingdoms/pull/97): سجل الاستمرارية، خريطة التغطية، سجل العمل المفتوح، وسياق المحادثات.
- [PR #94](https://github.com/areagleegy/AshenKingdoms/pull/94): المخطط الهندسي وخارطة المعمارية المرحلية.
- [PR #90](https://github.com/areagleegy/AshenKingdoms/pull/90): تدقيق الأنظمة والاختبارات.
- [PR #87](https://github.com/areagleegy/AshenKingdoms/pull/87): مسار تكامل AI مجاني أولًا.
- [PR #70](https://github.com/areagleegy/AshenKingdoms/pull/70): موجز المعمارية المبني على المستودع.
- [PRs #25–#27](https://github.com/areagleegy/AshenKingdoms/pulls?q=is%3Apr+is%3Aopen) و[PR #29](https://github.com/areagleegy/AshenKingdoms/pull/29): وثائق مرجع المشروع والroadmap وتنظيم الوثائق وخط الأساس.

هذه المجموعة تتشارك بعض تغييرات `docs/README.md` أو وثائق معمارية/خارطة طريق. لا تدمج نسخًا مكررة من الرؤية أو الحالة أو الخطة بلا مقارنة.

### التوصية

- اعتبر PR #97 حاليًا نقطة توثيق استمرارية وفهرسة فقط؛ لا يفترض أن يحل محل محتوى تخصصي مثل خطة الاختبار أو نموذج التهديد أو دليل البناء.
- قبل دمج PR توثيقي، افحص الروابط الداخلية، التكرار، مصدر كل ادعاء، وتاريخ لقطة GitHub.
- استخدم [سجل العمل المفتوح](OPEN_WORK_REGISTER_AR.md) لمعرفة ما لا يزال مفتوحًا، و[خريطة التغطية](REPOSITORY_DOCUMENTATION_MAP_AR.md) لربط الموضوع بمرجعه الأساسي.

## 9. قائمة تحقق قبل دمج طلبات متداخلة

- [ ] تأكيد ما إذا كان الفرع مبنيًا على فرع PR آخر.
- [ ] مقارنة الملفات المشتركة ومواضع التغيير، وليس عدد الإضافات والحذف فقط.
- [ ] التأكد من عدم إسقاط فحوص CI أو اختبارات موجودة.
- [ ] إعادة تشغيل الاختبارات على رأس الفرع الناتج بعد الدمج أو إعادة التأسيس.
- [ ] مراجعة أثر التغيير على حفظ المستخدم ومدخلات الشبكة والأصول والتوقيع.
- [ ] تحديث الوثائق المرجعية وحالة العمل والقضية المرتبطة.
- [ ] إغلاق أو وسم الطلبات المستبدلة بعد توثيق سبب الاستبدال.
- [ ] عدم إعلان جاهزية إصدار قبل اجتياز بوابات القبول اليدوية والأمنية.

## 10. حدود المراجعة

هذه الخريطة بُنيت من عناوين PRs وأوصافها وقوائم الملفات المتغيرة المسترجعة عبر GitHub في تاريخ اللقطة. لا تثبت أن كل تغيير صحيح أو أن الفروع قابلة للدمج معًا، ولا تمثل مراجعة كاملة لكل diff أو سجل مراجعات. يلزم فحص الرؤوس والفروق ونتائج CI الحالية قبل التنفيذ.

### مراجع داخلية

- [فهرس الوثائق](README.md)
- [خريطة التوثيق الشامل](REPOSITORY_DOCUMENTATION_MAP_AR.md)
- [سجل العمل المفتوح](OPEN_WORK_REGISTER_AR.md)
- [تدقيق Issues وPRs](ISSUE_AUDIT_AR.md)
- [خطة الاختبار](TEST_PLAN.md)
- [نموذج تهديدات الشبكة](NETWORK_THREAT_MODEL_AR.md)
