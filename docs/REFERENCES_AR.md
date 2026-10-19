# المراجع التقنية ومصادر الأدوات

هذه قائمة مراجع أساسية تساعد في اتخاذ القرار وتنفيذ المشروع. يُفضَّل استخدام الوثائق الرسمية والإصدارات الثابتة المتوافقة مع Godot 4.6 بدل الاعتماد على مقالات قديمة أو أمثلة من `latest` دون مقارنة الإصدار. لا يعني إدراج أداة هنا أن المشروع يعتمدها حاليًا.

> تاريخ المراجعة الأولية: 2026-10-19. تحقّق من الإصدار والرخصة وشروط الخدمة قبل اعتماد أي تحديث.

## 1. المحرك والبرمجة والتصدير

| المصدر | الاستخدام | طريقة الاستفادة |
|---|---|---|
| [Godot 4.6 Documentation](https://docs.godotengine.org/en/4.6/) | المرجع الأساسي للمحرك المستهدف | ابدأ بالنسخة المطابقة للمشروع، ثم تحقق من Class Reference للإصدارات والخصائص المحددة |
| [Godot: GDScript](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdscript/) | أنواع المتغيرات، الإشارات، الموارد، المشاهد، السكربتات | استخدم APIs وخصائص موثقة في خط 4.6؛ لا تنقل مثالًا من إصدار آخر دون اختبار |
| [Godot: High-level multiplayer](https://docs.godotengine.org/en/4.6/tutorials/networking/high_level_multiplayer.html) | MultiplayerAPI وMultiplayerPeer وENet ودورة الاتصال | المرجع قبل تعديل `NetworkManager` أو RPC والمزامنة وحدود المنصات |
| [Godot: Networking](https://docs.godotengine.org/en/4.6/tutorials/networking/) | بروتوكولات الاتصال وHTTP وTLS وWebSocket وWebRTC | قارن خيارات النقل عند اتخاذ قرار دعم اللعب الجماعي في المتصفح |
| [Godot: Exporting for Android](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html) | المتطلبات والتصدير والأذونات | احتفظ بإعدادات التوقيع والإصدارات والأسرار خارج النصوص العامة |
| [Godot: Exporting for the Web](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html) | قيود ومتطلبات نشر نسخة Web | اختبر عبر HTTP/HTTPS والمتصفحات المستهدفة؛ لا تستنتج الدعم من نجاح التصدير فقط |
| [Godot: Exporting projects](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_projects.html) | قوالب التصدير والموارد المضمّنة وأنواع المخرجات | راجع ما يُضمّن في كل preset، ولا تنشر ملفات Debug على أنها إصدار إنتاجي |

## 2. GitHub Actions وسلسلة التوريد

| المصدر | الاستخدام | الإجراء المطلوب |
|---|---|---|
| [GitHub Actions secure use reference](https://docs.github.com/en/actions/reference/security/secure-use) | أمان workflows والأسرار وصلاحيات `GITHUB_TOKEN` وActions الخارجية | اتبع أقل الصلاحيات، ولا تطبع الأسرار أو تمررها إلى وجهات غير موثوقة |
| [GitHub Actions workflow permissions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication) | تحديد صلاحيات رمز workflow | احتفظ بصلاحيات ضيقة ومحددة، ووسّعها فقط لاحتياج مثبت |
| [GitHub Actions: workflow artifacts](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts) | حفظ مخرجات البناء والتقارير ومدة الاحتفاظ بها | عامل Artifacts بوصفها مخرجات مؤقتة مرتبطة بتشغيل؛ لا تخلطها مع إصدار منشور أو موقع |
| [GitHub: Dependency review](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-dependency-review) | مراجعة تغييرات الاعتماديات في Pull Requests | أضف الفحص عندما تكون سياسة الاعتماديات وحدود الرخصة واضحة |
| [OpenSSF Scorecard](https://scorecard.dev/) | تقييم بعض ممارسات سلسلة التوريد مفتوحة المصدر | أداة إرشادية إضافية، وليست شهادة أمان أو بديلًا عن مراجعة إعداد المشروع |

**ملاحظة حالية:** يستخدم المستودع مراجع Actions بصيغة tags مثل `@v4`. توصي وثائق GitHub بتقييم تثبيت الإجراءات إلى commit SHA كامل (أو آلية lockfile المدعومة) لتحسين ثبات الاعتمادية ومقاومة تغيير الوسم. يجب تنفيذ هذا التغيير بمراجعة واعية لعنوان المصدر وآلية التحديث واختبارات CI، لا باستبدال آلي غير متحقق منه.

## 3. أدوات الاختبار والتحقق المحلية

| المصدر | الاستخدام | مكان الربط |
|---|---|---|
| [Python `unittest`](https://docs.python.org/3/library/unittest.html) | اختبارات أدوات بناء الحزم والتوقيع | `tools/test_package_content.py` و`tools/test_sign_content_catalog.py` |
| [Python `hashlib`](https://docs.python.org/3/library/hashlib.html) | تجزئة المحتوى، بما فيها SHA-256 | أدوات المحتوى والتحقق؛ التجزئة لا تُثبت هوية الناشر بحد ذاتها |
| [Python `zipfile`](https://docs.python.org/3/library/zipfile.html) | التعامل مع ملفات ZIP | بناء وفحص حزم المحتوى، مع الانتباه لمسارات الأرشيف والأحجام وحدود الموارد |
| [Mermaid flowcharts](https://mermaid.js.org/syntax/flowchart.html) | حفظ المخططات النصية في Git | [مخططات المشروع](DIAGRAMS_AR.md) |
| [SPDX License List](https://spdx.org/licenses/) | أسماء ومعرّفات الرخص الشائعة | مساعد لتطبيع بيانات الرخص؛ لا يغني عن قراءة نص الرخصة الفعلي والتحقق من الإسناد |

لا تضف اعتمادًا برمجيًا جديدًا لمجرد أنه مشهور. ابدأ بمكتبات المحرك أو المكتبة القياسية عندما تفي بالمتطلبات. إذا أُضيفت حزمة أو Plugin، وثّق سبب الحاجة إليها، والرخصة، والمصدر، وإصدارها، والسطح الأمني، وكيفية إزالتها أو تحديثها.

## 4. الأمن والهندسة القابلة للصيانة

| المصدر | الاستخدام | التطبيق في هذا المشروع |
|---|---|---|
| [NIST SP 800-218 — Secure Software Development Framework (SSDF)](https://csrc.nist.gov/pubs/sp/800/218/final) | تنظيم ممارسات التطوير الآمن ضمن دورة التطوير | استخدمه كقائمة مراجعة للعملية وسلسلة التوريد، لا كادعاء اعتماد |
| [OWASP Application Security Verification Standard (ASVS)](https://owasp.org/www-project-application-security-verification-standard/) | قائمة متطلبات أمنية قابلة للتحقق للأنظمة ذات المكونات الخدمية | مرجع لتنظيم متطلبات واجهة/خدمة حسابات مستقبلية إن أضيفت؛ لا يفترض وجود خدمة حسابات الآن |
| [OWASP Mobile Application Security](https://mas.owasp.org/) | مخاطر تطبيقات الهاتف والتخزين والاتصالات | يُستخدم قبل نقل مفاتيح أو بيانات حساسة إلى العميل أو تجهيز توزيع Android |
| [The C4 model](https://c4model.com/) | مستويات وصف السياق والحاويات والمكونات | يمكن استخدامه إذا احتاجت المعمارية إلى رسوم تفصيلية متعددة المستويات؛ مخططات Mermaid الحالية خريطة مبسطة وليست C4 كاملة |

### مبادئ أمن خاصة بممالك الرماد

- اعتبر العميل غير موثوق في اللعبة الشبكية؛ لا يعتمد الخادم على نتائج ضرر أو رصيد أو مكافأة يرسلها العميل دون تحقق.
- لا تحزم مفتاحًا خاصًا أو سر API داخل المستودع أو APK أو تصدير Web. المفاتيح الخاصة خارج نطاق الملفات العامة، مع طريقة لتدويرها وإبطالها.
- تحقق من التوقيع والتصريح بالمصدر قبل تثبيت حزمة محتوى؛ لا تعتبر SHA-256 وحده إثباتًا على الجهة الناشرة.
- طبّق حدودًا على عدد الملفات وحجمها واستخراج ZIP ومسارات الملفات وعمليات إعادة المحاولة قبل إتاحة التنزيل العام.
- لا تعرض إنجازات أمنية على أساس وجود فحص فقط؛ اربط الادعاء بسيناريو اختبار ونتيجة موثقة.

## 5. قواعد اختيار المراجع

1. **الأصل الرسمي أولًا:** وثائق المشروع الذي نستخدمه، مستودعه الرسمي، وملاحظات إصداره.
2. **طابق الإصدار:** Godot 4.6 هو خط التوافق في إعداد المشروع؛ لا تعتمد APIs من `latest` قبل التحقق من توثيق 4.6.
3. **تحقق من الرخصة:** خصوصًا الأصول الفنية والصوتيات والخطوط والـ Plugins والشفرة المنقولة.
4. **ثبّت القرار لا الرابط فقط:** عند اتخاذ قرار تقني مهم، سجّل سبب اختيار الأداة وإصدارها وبدائلها المختبرة داخل الوثيقة المالكة أو قرار تصميم صغير.
5. **تجنّب الادعاءات التسويقية:** شعبية الأداة لا تثبت الأداء أو الأمان أو التوافق. اختبر على سيناريو المشروع الفعلي.
6. **راجع هذه الصفحة دوريًا:** حدّث الروابط عند تغير إصدارات Godot أو GitHub Actions أو سياسة الرخص والتوزيع.

## 6. روابط داخلية ذات صلة

- [فهرس الوثائق](README.md)
- [تدقيق المستودع وخطة التنظيف](REPOSITORY_AUDIT_AR.md)
- [المخططات](DIAGRAMS_AR.md)
- [البنية التقنية](TECHNICAL_ARCHITECTURE.md)
- [خطة الاختبار](TEST_PLAN.md)
- [دليل حزم المحتوى](../content/README.md)
- [سجل الأصول والتراخيص](ASSET_CREDITS.md)
