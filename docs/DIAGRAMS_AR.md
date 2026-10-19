# مخططات ممالك الرماد

هذه المخططات مكتوبة بصيغة Mermaid كنص داخل Git، لتبقى قابلة للتعديل والمراجعة دون صور مولّدة أو ملفات ثنائية. تصف المخططات الحالية ما يمكن ربطه بمسارات المستودع؛ أما أي مسار مستقبلي فيُوسم بوضوح بأنه مقترح وغير منفذ.

> **المرجع التنفيذي:** [البنية التقنية](TECHNICAL_ARCHITECTURE.md)، [حالة التنفيذ](PROJECT_STATUS_AR.md)، [تدقيق المستودع](REPOSITORY_AUDIT_AR.md).

## 1. دخول اللعبة واختيار النمط — الوضع الحالي

```mermaid
flowchart TD
    Project["project.godot"] --> MenuScene["scenes/ui/MainMenu.tscn"]
    MenuScene --> MenuScript["scripts/ui/main_menu.gd"]
    MenuScript --> Mode{"اختيار مسار التشغيل"}
    Mode -->|فردي| SoloScene["scenes/boot/Main.tscn"]
    SoloScene --> SoloCore["scripts/core/main.gd"]
    Mode -->|مضيف| StartHost["NetworkManager.start_host"]
    Mode -->|عميل| StartClient["NetworkManager.start_client"]
    Headless["تشغيل --server أو headless"] --> StartHost
    StartHost --> Arena["scenes/network/MultiplayerArena.tscn"]
    StartClient --> Arena
    NetworkManager["Autoload: NetworkManager"] --- StartHost
    NetworkManager --- StartClient
```

**المسارات المصدرية:** يحدد `project.godot` مشهد القائمة نقطة البداية، وتنفذ `scripts/ui/main_menu.gd` اختيار اللعب الفردي أو إعداد جلسة ENet. يعتمد وضع الخادم headless على مسار القائمة الحالي. الملف `scripts/core/server.gd` ليس نقطة الدخول الفعلية لذلك المسار، وهو هيكل تمهيدي قديم.

## 2. طبقات الأنظمة — خريطة مبسطة

```mermaid
flowchart TB
    Entry["project.godot / MainMenu"] --> UI["scripts/ui/"]
    Entry --> DialogueAuto["DialogueManager Autoload"]
    Entry --> ContentAuto["ContentManager Autoload"]
    Entry --> NetworkAuto["NetworkManager Autoload"]
    UI --> Solo["مشهد اللعب الفردي"]
    UI --> NetArena["ساحة الشبكة التجريبية"]
    Solo --> Player["scripts/player/"]
    Solo --> Components["scripts/components/"]
    Solo --> Enemies["scripts/enemies/"]
    Solo --> Quest["Progression وQuest managers"]
    Solo --> Save["scripts/core/save_system.gd"]
    DialogueAuto --> Dialogue["scripts/dialogue/"]
    Dialogue --> NPC["scripts/npc/"]
    NetworkAuto --> NetworkScripts["scripts/networking/"]
    ContentAuto --> ContentScripts["scripts/content/"]
    ContentScripts --> Catalog["Catalog + package installer"]
    Catalog --> Policy["التحقق من التوقيع والتكامل قبل التثبيت"]
```

**ملاحظات:** هذا رسم ملاحة وتبعيات عالي المستوى، وليس مخطط UML كاملًا. التفاصيل الدقيقة لملكية الحالة والنداءات موجودة في السكربتات نفسها. لا يعني ظهور الوحدة في الرسم أن جميع ميزاتها مكتملة أو مفعّلة في كل منصة.

## 3. دورة جلسة ENet التجريبية — الوضع الحالي

```mermaid
sequenceDiagram
    actor HostUser as المستخدم المضيف
    actor ClientUser as المستخدم العميل
    participant Menu as MainMenu / main_menu.gd
    participant Manager as NetworkManager
    participant ENet as ENet MultiplayerPeer
    participant Arena as MultiplayerArena

    HostUser->>Menu: اختيار استضافة جلسة
    Menu->>Manager: start_host(port, max_clients)
    Manager->>ENet: إنشاء مضيف ENet
    Manager-->>Menu: نجاح بدء المضيف
    Menu->>Arena: فتح ساحة الشبكة

    ClientUser->>Menu: إدخال العنوان والمنفذ
    Menu->>Manager: start_client(address, port)
    Manager->>ENet: إنشاء اتصال عميل
    ENet-->>Manager: إشارة نجاح الاتصال
    Manager->>Arena: فتح ساحة الشبكة
    Arena-->>ENet: مزامنة أحداث اللعب التجريبي
    ENet-->>Arena: تحديثات الجلسة
```

### الحدود الأمنية الحالية

- الساحة نموذج اختبار وليست خدمة عامة جاهزة.
- لا توجد مصادقة حسابات إنتاجية أو حفظ شبكي دائم.
- لا تكتمل مزامنة الجرد والحوار والمهام المحلية مع الجلسة الشبكية.
- النجاح على loopback يثبت مسار الاتصال المختبر فقط، لا أمان الإنترنت ولا الأداء مع 100 لاعب.
- يجب التحقق من كل إجراء مؤثر على الخادم، لا الاعتماد على قيم الضرر أو المكافآت أو اكتمال المهمة القادمة من العميل.

راجع [NETWORKING.md](NETWORKING.md) لملاحظات التشغيل وحدود الشبكة وخطة التحقق.

## 4. دورة حزم المحتوى — كود أولي وضبط إنتاجي غير مكتمل

```mermaid
flowchart TD
    Builder["tools/package_content.py"] --> Archive["حزمة ZIP"]
    Archive --> CatalogTool["tools/sign_content_catalog.py"]
    CatalogTool --> SignedCatalog["فهرس موقع"]
    SignedCatalog --> Configure{"هل تم إعداد الخدمة ومفتاح الثقة؟"}
    Configure -->|لا - الوضع الحالي| Disabled["التنزيل الإنتاجي يبقى معطلًا"]
    Configure -->|نعم - يتطلب قرارًا واختبارًا| Fetch["تنزيل الفهرس والحزمة عبر HTTPS"]
    Fetch --> VerifySig["التحقق من توقيع الفهرس"]
    VerifySig --> VerifyHash["التحقق من SHA-256 وحدود/ملفات الحزمة"]
    VerifyHash --> Install["التثبيت داخل مساحة بيانات التطبيق"]
    Install --> Load["تحميل موارد المحتوى المسموح بها"]
    VerifySig -->|فشل| Reject["رفض الفهرس"]
    VerifyHash -->|فشل| Reject
```

**تمييز مهم:** الكود الأولي وأدوات البناء والتحقق موجودة. إعداد فهرس إنتاجي مستضاف ومفتاح عام موثوق غير مكتمل، لذا تبقى واجهة التنزيل معطلة افتراضيًا. SHA-256 يكشف تغير المحتوى بالنسبة إلى قيمة مرجعية موثوقة، لكنه لا يحل محل التوقيع والتحقق من هوية مصدر الفهرس.

التفاصيل: [دليل حزم المحتوى](../content/README.md) و[مواصفة التصميم](superpowers/specs/2026-10-19-optional-content-packs-design.md).

## 5. التحقق والبناء — كيف نقرأ نتائج CI

```mermaid
flowchart TD
    Change["Push / Pull Request / تشغيل يدوي"] --> Validate["Validate Godot Project"]
    Change --> Build["Build Android and Web"]
    Validate --> Files["التحقق من الملفات المطلوبة"]
    Files --> Links["روابط Markdown المحلية"]
    Links --> Import["استيراد/تحليل مشروع Godot"]
    Import --> Scripts["تحميل السكربتات والمشاهد"]
    Scripts --> Gameplay["اختبارات اللعب والانحدار واللاعب"]
    Gameplay --> Network["اختبارات الشبكة المحلية"]
    Network --> Content["اختبارات فهرس وحزم المحتوى"]
    Content --> AssetCheck["فحص بيانات الأصول والتراخيص"]
    Build --> WebExport["تصدير Web"]
    Build --> AndroidExport["تصدير APK تجريبي"]
    WebExport --> Artifact["Artifacts مؤقتة"]
    AndroidExport --> Artifact
```

يعكس هذا الرسم مجموعات الفحوص المعرفة في `.github/workflows/validate.yml` و`.github/workflows/build.yml`; راجع تعريف الـ workflow وسجل التشغيل للـ commit المعني. إذا تغير تسلسل CI فحدّث الرسم مع التغيير. لا تُسجّل نجاح خطوة إلا من سجلها الفعلي؛ نجاح التصدير ليس اختبار قبول لجهاز مادي.

## 6. مسار صيانة الوثائق — القاعدة المقترحة

```mermaid
flowchart LR
    CodeChange["تغيير الكود أو السلوك"] --> OwnerDoc["تحديث الوثيقة المالكة"]
    OwnerDoc --> Index["تحديث الروابط/الفهرس إذا لزم"]
    Index --> LinkCheck["tools/validate_docs.py"]
    LinkCheck --> AssetCheck["tools/validate_free_assets.py عند تغيير الأصول"]
    AssetCheck --> CI["نتائج CI مرتبطة بالـ commit"]
    CI --> Review["مراجعة القيود والأدلة"]
    Review --> Release["قبول الإصدار أو تسجيل العمل المتبقي"]
```

## قواعد تحديث المخططات

1. لا تنشئ مخططًا ثانيًا لنفس العملية؛ حدّث القسم المقابل.
2. يجب أن يشير كل مسار ملف إلى اسم موجود بالفعل أو يُوسم بأنه مقترح.
3. افصل في النص بين «الحالي» و«المستقبلي» و«لم يُختبر».
4. اجعل الرسم مختصرًا، واجعل تفاصيل البروتوكول والخوارزميات في الوثيقة المتخصصة.
5. شغّل `python3 tools/validate_docs.py` بعد تعديل الروابط. هذا الفحص يتحقق من وجود الأهداف المحلية، ولا يثبت صحة منطق الرسم أو الروابط الخارجية.
