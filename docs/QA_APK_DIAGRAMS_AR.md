# المخططات التفصيلية لـ AshenKingdoms QA APK

> **نوع الوثيقة:** خريطة هندسية للمكوّنات وتدفقات البيانات والاختبارات والأمان.  
> **فرع المرجع:** `feature/android-qa-reporter`  
> **Commit التنفيذ الذي أثبت نجاح CI:** `f13c1eebef821286efc1509e5b5f55f694c3e1d9`  
> **تمييز إلزامي:** «الحالي» يعني ما تنفذه الملفات الموجودة في الفرع المشار إليه؛ و«مقترح» يعني توسعة لم تُنفذ بعد. لا تُعامل مخططات AI أو الرفع أو الوكلاء الكاملة على أنها وظائف موجودة في APK الحالي.

## 1. مفتاح حالة المخططات

| الرمز | المعنى |
|---|---|
| `[CURRENT]` | موجود في التنفيذ الحالي واجتاز فحص CI على commit المرجع |
| `[PARTIAL]` | موجود جزئيًا؛ لا يغطي الوظيفة الكاملة التي يوحي بها الاسم |
| `[PROPOSED]` | هدف معماري لم يُنفذ بعد |
| `[OUT OF SCOPE]` | ليس جزءًا من هذا الإصدار |

### الحالة الفعلية مقابل الهدف

| المكوّن | الحالة | السلوك الحالي أو الحد |
|---|---|---|
| preset منفصل `Android QA` وميزة `qa_tools` | CURRENT | حزمة Android منفصلة باسم `org.ashenkingdoms.game.qa` |
| QAReporter | CURRENT | أحداث مقيّدة، عينات أداء، نقاط تحقق محلية، وتصدير JSON |
| QATestRunner | PARTIAL | يتحقق من تحميل مشاهد محددة وقراءة/كتابة ملف مؤقت؛ لا يلعب سيناريوهات كاملة |
| زر تشغيل الفحص ونسخ التقرير | CURRENT | الفحص والتصدير يتمان عند ضغط المختبِر؛ النسخ عبر Clipboard |
| أحداث حفظ وشبكة | PARTIAL | أحداث منظمة محدودة، دون سجل Android العام أو بيانات كل RPC |
| Navigator / Combat Stress / Network Fault Agents | PROPOSED | ليست وكلاء لعب كاملة في APK الحالي |
| Seed وReplay حتمي | PROPOSED | لا يوجد مسجل إعادة تشغيل كامل حاليًا |
| رفع التقرير من APK إلى Backend | OUT OF SCOPE | لا توجد قناة رفع في APK الحالي |
| AI داخل APK أو مفتاح API داخله | OUT OF SCOPE | لا نموذج محلي ولا مفاتيح AI/GitHub داخل الحزمة |
| تحليل خارجي متعدد الوكلاء وإنشاء PR | PROPOSED | يجب أن يكون خارج APK وبصلاحيات منفصلة ومراجعة بشرية |
| منع وجود QA في Release | هدف أمني | توجد حدود تصدير منفصلة؛ يلزم فحص artifact إنتاجي نهائي كخطوة مستقلة |

---

## 2. المخطط السياقي للنظام

يوضح المخطط ما هو موجود اليوم وما يمكن إضافته لاحقًا. المسار المتصل المحلي هو الموجود حاليًا؛ المسارات ذات العلامة `PROPOSED` ليست تنفيذًا حاليًا.

```mermaid
flowchart TB
  subgraph APK["Android QA APK — CURRENT"]
    GAME["Godot Game Runtime"]
    MENU["Main Menu"]
    REPORTER["QAReporter"]
    RUNNER["QATestRunner"]
    OVERLAY["QA overlay during gameplay"]
    LOCAL["user://qa_reports"]
    CLIP["Clipboard — explicit user action"]
    ANALYZER["Offline report analyzer on developer machine"]
    OLLAMA["Optional local Ollama"]
    GAME --> MENU
    MENU -->|"qa_tools enabled"| REPORTER
    MENU -->|"QA action"| RUNNER
    OVERLAY -->|"tester action in gameplay"| RUNNER
    RUNNER -->|"test results + event"| REPORTER
    REPORTER -->|"checkpoint / JSON report"| LOCAL
    REPORTER -->|"JSON shown on screen"| CLIP
    CLIP -.->|"manual copy / file transfer"| ANALYZER
    ANALYZER -.->|"explicit local model option"| OLLAMA
  end

  subgraph CI["GitHub Actions — CURRENT"]
    VALIDATE["Validate Godot Project"]
    BUILD["Build Android and Web"]
    QAAPK["Android QA artifact"]
    BUILD --> QAAPK
    VALIDATE -.->|"checks scripts/tests"| REPORTER
  end

  subgraph FUTURE["Optional external path — PROPOSED"]
    CONSENT["Tester consent + explicit upload"]
    GATEWAY["HTTPS QA Gateway"]
    VALID["Auth + Schema Validation + Redaction"]
    QUEUE["Queue + bounded storage"]
    RULES["Rule-based triage"]
    AI["External analysis models"]
    ISSUE["Issue / proposed patch / draft PR"]
    REVIEW["CI + Human review"]
    CONSENT --> GATEWAY --> VALID --> QUEUE --> RULES
    RULES --> AI --> ISSUE --> REVIEW
  end

  LOCAL -.->|"manual export only today"| CONSENT
  QAAPK -.->|"download artifact"| APK
  REVIEW -.->|"never auto-merge"| CI
```

**قراءة المخطط:** وجود ملف تقرير محلي لا يعني وجود Upload API. في النسخة الحالية لا يغادر JSON الجهاز تلقائيًا. كما أن نجاح CI يثبت اجتياز الاختبارات الآلية المحددة فقط، وليس اختبارًا على هاتف حقيقي.

## 3. حدود البناء والتغليف

```mermaid
flowchart LR
  SRC["Project source + shared gameplay scripts"] --> QA_PRESET["Android QA preset"]
  SRC --> REL_PRESET["Android production preset"]
  SRC --> WEB_PRESET["Web preset"]

  QA_PRESET --> QA_TAG["custom_features = qa_tools"]
  QA_TAG --> QA_APK["AshenKingdoms-QA.apk"]
  QA_APK --> QA_PACKAGE["org.ashenkingdoms.game.qa"]

  REL_PRESET --> REL_FILTER["Exclude scripts/qa/* and QA-only assets"]
  REL_FILTER --> REL_APK["Production APK / AAB"]
  WEB_PRESET --> WEB_FILTER["Exclude scripts/qa/* and QA-only assets"]
  WEB_FILTER --> WEB["Web export"]

  QA_APK -.-> NO_SECRETS["No AI key / no GitHub token / no auto-upload"]
  REL_APK -.-> GUARD["Release artifact inspection required"]
  WEB -.-> NO_QA_RUNTIME["No QA runtime payload intended"]
```

### حدود هذا الفصل

- يعتمد ظهور أدوات QA على feature tag المخصص `qa_tools` وليس على إخفاء زر فقط.
- يوجه preset الخاص بـ QA إلى package ID منفصل حتى لا يحل محل النسخة العادية.
- يستبعد التصديران الاعتياديان ملفات `scripts/qa/*` وفق إعدادات التصدير في الفرع.
- لا تكفي إعدادات preset وحدها كدليل نهائي على خلو Release: يلزم فحص الحزمة المبنية نفسها، وفحص manifest والمراجع والموارد والأسرار بعد التصدير.
- لا يوضع سر AI أو رمز GitHub في source أو APK أو ملف تقرير.

## 4. خريطة الملفات الفعلية والمقترحة

### الملفات الأساسية الموجودة الآن

```text
project.godot
export_presets.cfg
scripts/
├── core/
│   ├── save_system.gd                 # أحداث حفظ منظمة محدودة
│   └── network_manager.gd             # أحداث جلسة ENet محدودة
├── ui/
│   └── main_menu.gd                   # تهيئة QA وواجهة الفحص والنسخ
└── qa/
    ├── qa_reporter.gd                 # تجميع الحدث والأداء والحفظ المحلي
    └── qa_test_runner.gd              # تحميل موارد + اختبار التخزين
tests/
└── qa_reporter_smoke_test.gd           # 10 assertions في الفحص الحالي
.github/workflows/
├── build.yml                          # Android QA + Android debug + Web
└── validate.yml                       # تحقق Godot واختبار QAReporter
docs/
└── QA_ANDROID_REPORTER_AR.md
```

### التوسعات المقترحة — لا تُعد ملفات موجودة الآن

```text
scripts/qa/
├── qa_config.gd
├── qa_orchestrator.gd
├── qa_session.gd
├── scenario_registry.gd
├── action_executor.gd
├── replay_recorder.gd
├── agents/
│   ├── qa_agent_base.gd
│   ├── navigator_agent.gd
│   ├── combat_stress_agent.gd
│   ├── save_load_agent.gd
│   ├── network_fault_agent.gd
│   ├── performance_agent.gd
│   └── supervisor_agent.gd
├── metrics/
│   ├── frame_metrics.gd
│   ├── gameplay_metrics.gd
│   └── memory_metrics.gd
├── evidence/
│   ├── evidence_collector.gd
│   ├── state_snapshot.gd
│   └── report_writer.gd
├── transport/
│   ├── report_transport.gd
│   ├── local_transport.gd
│   └── https_transport.gd
└── ui/
    ├── qa_overlay.gd
    └── qa_menu.gd
```

أضف هذه الطبقات تدريجيًا بعد تثبيت التقرير المحلي واختباره على هاتف حقيقي؛ لا تنشئ كل الملفات كواجهات فارغة دفعة واحدة.

## 5. دورة بدء التطبيق وتشغيل فحص QA — CURRENT

```mermaid
sequenceDiagram
  autonumber
  actor Tester as المختبِر
  participant Menu as MainMenu
  participant Reporter as QAReporter
  participant Runner as QATestRunner
  participant Storage as user://qa_reports
  participant UI as Report Window / Clipboard

  Tester->>Menu: فتح التطبيق
  Menu->>Menu: فحص OS.has_feature("qa_tools")
  alt QA feature enabled
    Menu->>Reporter: إنشاء QAReporter إن لم يوجد
    Reporter->>Storage: قراءة آخر checkpointين
    Reporter->>Reporter: بدء session + تسجيل main_menu_ready
    Reporter->>Storage: كتابة checkpoint
    Tester->>Menu: ضغط "فحص QA ونسخ التقرير"
    Menu->>Runner: إنشاء مشغّل الفحص
    Runner->>Runner: تحميل المشاهد المحددة
    Runner->>Storage: اختبار round-trip لملف مؤقت
    Runner-->>Reporter: set_test_results + ملخص النجاح والفشل
    Menu->>Reporter: export_report()
    Reporter->>Storage: كتابة JSON محلي
    Menu->>UI: عرض الملخص وJSON
    Tester->>UI: ضغط "نسخ JSON"
    UI-->>Tester: النص متاح في Clipboard
  else regular build
    Menu->>Menu: عدم تهيئة QA وعدم إظهار الزر
  end
```

### الفحوص التي ينفذها QATestRunner الآن

| معرف الاختبار | ما يتحقق منه | ما لا يثبته |
|---|---|---|
| `main_scene_load` | وجود وتحميل PackedScene للمشهد الرئيسي | أن كل آليات اللعب تعمل |
| `multiplayer_arena_load` | تحميل مشهد الساحة | أن الاتصال الخارجي أو اللعب بين هاتفين صالح |
| `touch_controls_load` | تحميل مورد واجهة اللمس | صحة لمس كل جهاز أو اتجاه شاشة |
| `network_avatar_load` | تحميل مورد شخصية الشبكة | صحة كل حالات المزامنة |
| `network_enemy_load` | تحميل مورد عدو الشبكة | صحة الذكاء الاصطناعي للعدو أو القتال الكامل |
| `storage_roundtrip` | إنشاء مجلد QA وكتابة/قراءة/حذف ملف اختبار | سلامة نظام الحفظ الفعلي في كل حالات الانقطاع |

**حد أساسي:** هذه فحوص موارد وتخزين، لا وكيل يتنقل في العالم أو يقاتل بشكل ذاتي.

## 6. دورة حياة الجلسة — CURRENT + TARGET

الحالة الحالية هي دورة جمع حدث وقياس وحفظ محلي. حالات الاسترداد والتنفيذ متعدد السيناريوهات هدف مقترح للموسعات القادمة.

```mermaid
stateDiagram-v2
  [*] --> Bootstrap
  Bootstrap --> Disabled: no qa_tools
  Disabled --> [*]
  Bootstrap --> RecoverCheckpoint: qa_tools enabled
  RecoverCheckpoint --> SessionActive: reporter initialized
  SessionActive --> CollectEvent
  SessionActive --> SamplePerformance: every ~5s
  SessionActive --> WriteCheckpoint: every ~30s
  CollectEvent --> SessionActive
  SamplePerformance --> SessionActive
  WriteCheckpoint --> SessionActive
  SessionActive --> RunSmoke: tester presses button
  RunSmoke --> RecordResults
  RecordResults --> ExportReport
  ExportReport --> ShowReport
  ShowReport --> SessionActive
  ShowReport --> [*]: app exits

  state "Proposed orchestrated scenarios" as Future {
    [*] --> PrepareScenario
    PrepareScenario --> ExecuteAction
    ExecuteAction --> Observe
    Observe --> Assert
    Assert --> NextStep: pass
    Assert --> CaptureFailure: fail/timeout
    CaptureFailure --> WriteFailureReport
  }
```

### حدود زمنية وتخزين موثقة في التنفيذ الحالي

| الحد | القيمة الحالية |
|---|---:|
| الحد الأقصى للأحداث في الذاكرة لكل تقرير | 300 حدث |
| تكرار أخذ عينات الأداء | نحو 5 ثوانٍ |
| دورية checkpoint | نحو 30 ثانية |
| عدد ملفات checkpoint | ملفان بالتناوب |
| أقصى حجم checkpoint مقروء | 512 KiB |
| عدد الجلسات السابقة المسترجعة | 3 |
| الإبلاغ/الرفع التلقائي | معطل؛ لا يوجد مسار Upload في APK |
| بيانات حرّة داخل تفاصيل الحدث | تُستبعد؛ تقبل المفاتيح الآمنة والقيم الرقمية/المنطقية فقط |

لا تضمن checkpoint كل حدث على القرص في لحظته؛ لذلك قد تضيع أحداث بعد آخر نقطة مكتوبة عند انهيار مفاجئ.

## 7. المعمارية المستهدفة للـ Orchestrator والوكلاء — PROPOSED

```mermaid
flowchart TB
  BOOT["QA Bootstrap"] --> CFG["Validated QA Config"]
  CFG --> SESSION["Session Manager + build/commit"]
  SESSION --> ORCH["QA Orchestrator"]
  ORCH --> REG["Scenario Registry"]
  REG --> S["Scenario + fixed seed + attempt limit"]
  S --> EXEC["Action Executor"]
  EXEC --> OBS["Observe Game State"]
  OBS --> ASSERT["Assertions + timeout rules"]
  ASSERT -->|pass| STEP["Next action / next scenario"]
  STEP --> EXEC
  ASSERT -->|fail / stuck / timeout| EVIDENCE["Evidence Collector"]
  EVIDENCE --> SNAP["State snapshot + action tail + metrics"]
  SNAP --> WRITER["Report Writer + Schema validation"]
  WRITER --> STORE["Local bounded report store"]
  STORE --> END["Stop / continue by policy"]

  ORCH --> NAV["Navigator Agent"]
  ORCH --> COMBAT["Combat Stress Agent"]
  ORCH --> SAVE["Save/Load Agent"]
  ORCH --> NET["Network Fault Agent"]
  ORCH --> PERF["Performance Agent"]
  NAV --> EXEC
  COMBAT --> EXEC
  SAVE --> EXEC
  NET --> EXEC
  PERF --> OBS

  SUP["Supervisor — proposed arbitration"] -.-> ORCH
  SUP -.-> EVIDENCE
```

### عقد الوكيل المقترح

كل وكيل جديد يجب أن يعرّف على الأقل:

```text
agent_id
supported_scenarios
preconditions
actions
observations
assertions
per_action_timeout
scenario_timeout
max_retries
recovery_policy
evidence_policy
cleanup
result_status
```

ويجب أن يكون لكل وكيل نطاق أفعال محدد. لا تسمح لوكيل الشبكة بتغيير ملفات حفظ حقيقية، ولا لوكيل الأداء بتشغيل اختبارات تغير الجرد أثناء قياس خط أساس الأداء.

## 8. مخطط الوكلاء وتغطية السيناريوهات — TARGET

```mermaid
flowchart LR
  subgraph GAMEPLAY["Gameplay"]
    N["Navigator"]
    C["Combat Stress"]
  end
  subgraph PERSIST["Persistence"]
    S["Save/Load"]
  end
  subgraph CONNECTIVITY["Connectivity"]
    F["Network Fault"]
  end
  subgraph OBSERVABILITY["Observability"]
    P["Performance"]
    E["Evidence Collector"]
  end
  O["Orchestrator"] --> N
  O --> C
  O --> S
  O --> F
  O --> P
  N --> E
  C --> E
  S --> E
  F --> E
  P --> E
  E --> R["Validated report"]
```

| الوكيل المقترح | سيناريوهات نموذجية | شرط فشل قابل للقياس |
|---|---|---|
| Navigator | حركة، اصطدام، جدار، حافة، مسار مسدود | عدم تغير الموضع خارج هامش متفق عليه طوال مهلة الحركة |
| Combat Stress | هجوم/مراوغة/مهارة، تبريد، عدة أعداء | ضرر خارج المتوقع، مهلة لا تنتهي، موت أو حالة غير صالحة |
| Save/Load | تعديل حالة fixture، حفظ، إعادة تحميل، مقارنة snapshot | فرق حتمي في الحقول المتوقعة أو JSON غير قابل للقراءة |
| Network Fault | فصل، مهلة اتصال، رسالة مكررة، RPC غير صالح | crash أو تغيير حالة خادم غير مصرح أو غياب نتيجة متوقعة |
| Performance | مشهد وخطوات ثابتة، قياسات إطارات | تجاوز خط أساس مضبوط على جهاز/محرك/مشهد مطابق |
| Evidence | تلخيص حالة الفشل وسجل الأفعال | تقرير ناقص، كبير جدًا، أو يحتوي على حقل محظور |

لا يعدّل الوكيل الشيفرة. ينتج أدلة قابلة للتكرار؛ التنفيذ والاختبار يظلان منفصلين عن أي اقتراح AI لاحق.

## 9. مخطط تقرير JSON — الموجود والمستهدف

### الحقول الموجودة الآن

تحتوي بنية التقرير الحالية على:

```text
schema_version
report_type
generated_at
checkpoint_unix
session_id
session_started_at
session_duration_seconds
build:
  commit
  project_name
  project_version
  godot_version
  os_name
  android
  qa_tools
  debug_build
current_scene
performance:
  sample_count
  average_fps
  minimum_fps
  maximum_fps
  peak_static_memory_mb
test_results[]
events[]
previous_sessions[]
safety:
  local_only
  automatic_upload
  ai_requests_from_apk
  raw_dialogue_or_chat_recorded
  save_contents_recorded
  network_addresses_recorded
  event_limit
```

### الإضافات المقترحة فقط

حقول `device_hash` و`android_api` و`renderer` و`scenario_id` و`seed` و`replay_id` و`artifacts[]` لا ينبغي الإيحاء بأنها موجودة في التقرير الحالي؛ تضاف بعد تصميم خصوصية واختبارات مخطط مستقلة.

```mermaid
classDiagram
  class Report {
    +int schema_version
    +string report_type
    +string session_id
    +string generated_at
    +float session_duration_seconds
    +string current_scene
    +BuildInfo build
    +PerformanceSummary performance
    +TestResult[] test_results
    +Event[] events
    +SessionSnapshot[] previous_sessions
    +SafetyFlags safety
  }
  class BuildInfo {
    +string commit
    +string project_name
    +string project_version
    +string godot_version
    +string os_name
    +bool android
    +bool qa_tools
    +bool debug_build
  }
  class Event {
    +string at
    +float elapsed_seconds
    +string event
    +string scene
    +Dictionary details
  }
  class TestResult {
    +string id
    +string status
    +int duration_ms
    +int error_code
  }
  class PerformanceSummary {
    +int sample_count
    +float average_fps
    +float minimum_fps
    +float maximum_fps
    +float peak_static_memory_mb
  }
  class SafetyFlags {
    +bool local_only
    +bool automatic_upload
    +bool ai_requests_from_apk
    +bool save_contents_recorded
    +bool network_addresses_recorded
    +int event_limit
  }
  Report --> BuildInfo
  Report --> PerformanceSummary
  Report --> TestResult
  Report --> Event
  Report --> SafetyFlags
```

### ضوابط المخطط

- `schema_version` إلزامي لكل نسخة مستقبلية من التقرير.
- `status` في نتائج الاختبارات يقتصر على `pass` و`fail` و`skip`.
- `event` اسم منظم قصير؛ لا تستخدمه لتخزين stack trace أو نص الحوار.
- تفاصيل الحدث الحالية ترفض النصوص الحرة، وتقبل قيمًا رقمية/منطقية من مفاتيح مطابقة للنمط المسموح.
- يجب أن يكون كل تطور غير متوافق في بنية التقرير مصحوبًا بتحديث اختبارات schema وأداة التحقق.

## 10. تخزين محلي ونقاط تحقق — CURRENT

```mermaid
flowchart TD
  EVT["record_event()"] --> BUF["In-memory bounded events: max 300"]
  PERF["Performance sample ~5s"] --> EVT
  SAVE["SaveSystem / NetworkManager events"] --> EVT
  BUF -->|20 events since checkpoint| CP["Checkpoint writer"]
  TIMER["~30s timer"] --> CP
  INIT["Startup"] --> READ["Read checkpoint A and B"]
  READ --> VALIDATE["Size <= 512 KiB + parse JSON"]
  VALIDATE --> CHOOSE["Choose newest checkpoint_unix"]
  CHOOSE --> RECOVER["Recover up to 3 previous sessions"]
  CP --> SLOT["Write alternate checkpoint slot"]
  SLOT --> A["qa_session_checkpoint_a.json"]
  SLOT --> B["qa_session_checkpoint_b.json"]
  TAP["Tester presses QA button"] --> EXPORT["Export report"]
  EXPORT --> FILE["qa_report_<unix>.json"]
  EXPORT --> DISPLAY["Show report JSON"]
  DISPLAY --> COPY["Explicit clipboard copy"]
```

### متطلبات التخزين المستهدفة

| العنصر | التوصية المستقبلية |
|---|---|
| التقرير المؤقت | الكتابة إلى ملف مؤقت ثم إعادة تسمية بعد النجاح |
| حجم كل تقرير | حد مقترح 256 KiB؛ لا يزال يحتاج تطبيقًا واختبارًا |
| عدد التقارير غير المرفوعة | حد مقترح 20 تقريرًا |
| المرفقات | حد مقترح 5 مرفقات، مع screenshots اختيارية عند الفشل فقط |
| التنظيف | تدوير مضبوط يحتفظ بآخر التقارير الفاشلة وملخصاتها |
| فشل التخزين | تسجيل حدث مختصر ثم استمرار اللعبة؛ لا crash بسبب QA |
| تعطل الجهاز | لا وعد باسترجاع الأحداث الأحدث من checkpoint آخر ناجح |

الحدود في الجدول المستهدف لا تدخل كلها في التنفيذ الحالي تلقائيًا؛ يجب تنفيذ كل حد واختباره قبل وصفه بأنه ضمان قائم.

## 11. إرسال خارجي وتحليل AI — PROPOSED ONLY

```mermaid
sequenceDiagram
  autonumber
  actor Tester as المختبِر
  participant APK as QA APK
  participant Gateway as HTTPS Gateway
  participant Validate as Auth / Schema / Redaction
  participant Queue as Bounded Queue
  participant Rules as Local/Server Rules
  participant AI as External Model Service
  participant GitHub as GitHub Issue or Draft PR
  participant CI as Validate + Build
  actor Human as مراجع بشري

  Tester->>APK: موافقة صريحة على التقرير
  APK->>Gateway: HTTPS + report + request id
  Gateway->>Validate: تحقق token / schema / size / rate
  Validate-->>Gateway: allow or reject
  Gateway->>Queue: enqueue sanitized report
  Queue->>Rules: categorize findings
  Rules->>AI: redacted excerpts only (optional)
  AI-->>Rules: hypothesis + evidence + safe checks
  Rules->>GitHub: create issue or draft patch proposal
  GitHub->>CI: run checks on proposed branch
  CI-->>Human: results + artifacts
  Human->>GitHub: review / request changes
  Note over APK,AI: لا يُرسل شيء من APK الحالي؛ هذا التدفق مستقبل مقترح.
  Note over GitHub,Human: لا دمج تلقائي حتى مع نجاح AI أو CI.
```

### عقد الواجهة المقترح

```http
POST /v1/qa/reports
Content-Type: application/json
X-QA-Build-ID: <build-id>
X-QA-Request-ID: <uuid>
Authorization: <short-lived QA credential>
```

- يجب أن تنفذ الخدمة المصادقة وتحقق الحجم والمخطط ومعدل الطلب قبل تخزين التقرير.
- يتم التنقيح عند العميل وعند Gateway؛ التنقيح المزدوج ليس بديلًا عن حظر حقول حساسة أصلًا.
- أسرار المزود تحفظ في Secret Manager/GitHub Secrets، ولا ترجع إلى APK.
- تخضع أي بيانات مرسلة خارجيًا لموافقة المختبِر وسياسة الاحتفاظ وخصوصية المزوّد.
- إذا كانت نقطة النهاية غير آمنة أو فشل الرفع، يبقى التقرير محليًا؛ لا يعطل ذلك اللعب.
- GitHub Models ليس أساسًا مفترضًا لهذا التصميم؛ اختر مزوّدًا حاليًا موثّقًا وأعد التحقق من سياساته وحدوده عند التنفيذ.

## 12. مناطق الثقة والأمان

```mermaid
flowchart TB
  subgraph UNTRUSTED["منطقة غير موثوقة: جهاز المختبِر / APK"]
    GAME["Game runtime"]
    REPORT["Local report"]
    UI["Explicit export / consent"]
    GAME --> REPORT --> UI
  end

  subgraph TRUST1["بوابة HTTPS — مستقبل مقترح"]
    TLS["TLS + endpoint allowlist"]
    AUTH["Short-lived auth / rate limit"]
    SCHEMA["Schema + size validation"]
    REDACT["Redaction + content policy"]
    TLS --> AUTH --> SCHEMA --> REDACT
  end

  subgraph TRUST2["خدمات خارجية"]
    SECRET["Secret Manager"]
    MODEL["AI provider"]
    GIT["GitHub App / limited permissions"]
    CHECKS["CI / checks"]
    HUMAN["Human approval"]
    SECRET --> MODEL
    REDACT --> MODEL
    MODEL --> GIT --> CHECKS --> HUMAN
  end

  UI -.->|"only after consent"| TLS
  GAME -.->|"no embedded provider key"| SECRET
  HUMAN -.->|"approval required"| GIT
```

### قواعد أمنية غير قابلة للتفاوض

1. **لا مفاتيح AI أو GitHub داخل APK.** أي قيمة مدرجة في حزمة عميل تعتبر قابلة للاستخراج.
2. التقارير لا تحتوي على save-file body، نصوص الحوارات، إدخال المستخدم الخام، عناوين الشبكة، أو أسرار.
3. لا يقبل Gateway تقريرًا لمجرد احتوائه على `commit`؛ يتحقق من الحجم والمخطط والمصادقة والحصة.
4. لا يحصل وكيل التحليل على صلاحية تعديل `main` أو دمج PR.
5. أي patch مقترح يمر باختبارات تلقائية ومراجعة بشرية.
6. لا تنشأ جلسة تصوير أو تسجيل مستمر خفي؛ الأثر الإضافي محدود ومقصود ومُعطّل افتراضيًا.
7. تُسجل حالة «لم تُلتقط أدلة كافية» بدل الاستنتاج بأن اللعبة سليمة.

## 13. مخطط CI وRelease Guard

```mermaid
flowchart TD
  CHANGE["Pull Request / commit"] --> PY["Python diagnostic tests + corpus benchmark"]
  PY --> GODOT["Godot import + script/scene validation"]
  GODOT --> QA_TEST["QAReporter smoke test"]
  QA_TEST --> GAME_TEST["Gameplay / regression / player tests"]
  GAME_TEST --> NET_TEST["ENet combat + loopback"]
  NET_TEST --> CONTENT["Content / asset / installer tests"]
  CONTENT --> VALIDATE["Validate workflow green"]

  CHANGE --> WEB["Web export"]
  CHANGE --> ANDROID["Android debug export"]
  ANDROID --> QABUILD["Stamp tested commit + Android QA export"]
  QABUILD --> QAAPK["Upload ashen-kingdoms-android-qa"]
  WEB --> ART["Artifacts"]
  QAAPK --> ART

  ART --> DEVICE["Physical-device verification — separate gate"]
  DEVICE --> REPORT["Attach report + device matrix"]
  REPORT --> RELEASE_GUARD["Inspect release artifact"]
  RELEASE_GUARD -->|pass| RELEASE["Release candidate"]
  RELEASE_GUARD -->|fail| BLOCK["Block release + investigate"]
  VALIDATE --> RELEASE_GUARD
```

### Release Guard المقترح

| الفحص | دليل النجاح المطلوب |
|---|---|
| لا scripts/qa | فحص محتويات export/pack النهائي، وليس اعتمادًا على preset فقط |
| لا QA overlay / menu | بحث الموارد والنصوص والمراجع في الحزمة |
| لا أسرار | secret scan للمصدر ولملفات APK المستخرجة |
| package identity صحيح | تحقق manifest وapplication ID |
| build provenance | commit كامل ومحدد وworkflow ناجح |
| schema / tests | اختبارات schema والانحدار ناجحة |
| جهاز حقيقي | تقرير مثبت على commit والبناء والطراز وإصدار Android |
| بوابة الدمج | نجاح CI ومراجعة بشرية؛ لا دمج تلقائي |

**لا يثبت Build Android and Web وحده** أن APK قد شُغّل على هاتف حقيقي، كما أن نجاح Export لا يثبت سلوك اللمس أو الحرارة أو انقطاع الطاقة.

## 14. مصفوفة سيناريوهات الاختبار

جميع المعرفات التالية ما عدا فحوص الموارد والتخزين الحالية هي سيناريوهات مستهدفة، وتحتاج تنفيذًا واختبارًا منفصلين.

| الفئة | المعرف | الإجراء | النتيجة القابلة للتحقق |
|---|---|---|---|
| Smoke | S001 | boot + main scene | لا crash + المشهد المتوقع |
| Smoke | S002 | enter world | العالم ظاهر وplayer node موجود |
| Movement | S003 | تحرك نحو waypoint | تغير الموضع داخل مهلة محددة |
| Combat | S004 | attack مرة واحدة | HP/حدث الضرر يطابق التوقع |
| Dialogue | S005 | فتح/اختيار حوار | flag وحالة الاختيار متوقعان |
| Quest | S006 | تتبع/تحديث مهمة | انتقال الحالة مرة واحدة |
| Save | S007 | حفظ fixture | الملف قابل للقراءة والحقول المطابقة |
| Reload | S008 | إعادة تحميل | snapshot المتوقع يطابق الفعلي |
| Regression | S101 | inventory cycle | العناصر والكميات صحيحة |
| Regression | S102 | player death/respawn | انتقال حالات الموت والظهور مضبوط |
| Regression | S103 | enemy reward twice | مكافأة واحدة فقط |
| Persistence | S105 | JSON تالِف | رفض آمن دون crash أو استبدال بيانات سليمة |
| Boundary | S106 | اصطدام/حافة | لا خروج غير مصرح من العالم |
| Stress | S201 | attack/dodge/skill بالتتابع | لا soft lock ولا زمن انتظار مكسور |
| Stress | S204 | فتح/إغلاق inventory | حالة UI متسقة |
| Network | S301 | ENet host loopback | اتصال محلي ونتيجة واضحة |
| Network | S303 | disconnect | حدث انقطاع وحالة جلسة معروفة |
| Network | S305 | invalid RPC | رفض آمن وعدم تغيير حالة غير مصرح |
| Network | S306 | request flood | تحديد معدل موثّق دون crash |

### شرط إعادة الإنتاج

لكل سيناريو آلي مستقبلي يجب تسجيل `scenario_id` و`seed` و`attempt` ونسخة البناء والـ commit، ثم تقييد الأفعال والمهلات وعدد المحاولات. لا تعتبر تكرار الاختبار «إعادة إنتاج» إذا تغير البناء أو الجهاز أو الإعدادات دون توثيق ذلك.

## 15. مقاييس الأداء وخطة القياس

### مقاييس موجودة الآن

- متوسط FPS محسوب على عينات غير صفرية.
- أدنى وأعلى FPS ضمن العينات.
- ذروة الذاكرة الساكنة التي يقيسها Godot.
- أزمنة processing/physics في أحداث عينات دورية.

### مقاييس مستهدفة لم تُطبق بعد

```text
frame_time_ms
p50_frame_ms
p95_frame_ms
p99_frame_ms
max_frame_ms
physics_time_ms
startup_ms
scene_load_ms
scenario_duration_ms
action_count
error_count
thermal_state          # إذا توفر مصدر موثوق على الجهاز
android_memory_bytes   # يتطلب مصدر Android موثقًا
```

لا تحدد عتبة أداء عامة قبل جمع خط أساس على أجهزة مستهدفة متفق عليها. قارن فقط نتائج لها نفس build، والجهاز/فئته، وإصدار Android، والـ renderer، والمشهد والسيناريو. شغّل profiler الثقيل في جلسات تشخيص منفصلة إذا أثّر في القياس.

## 16. خطة التنفيذ ذات بوابات قبول

```mermaid
flowchart TD
  P1["Phase 1: Current local reporter"] --> G1{"QA smoke + JSON/privacy pass?"}
  G1 -->|no| FIX1["fix and rerun CI"]
  FIX1 --> G1
  G1 -->|yes| P2["Phase 2: deterministic scenario runner"]
  P2 --> G2{"seed + timeout + replay tests pass?"}
  G2 -->|no| FIX2["fix scenario contract"]
  FIX2 --> G2
  G2 -->|yes| P3["Phase 3: gameplay/save/network agents"]
  P3 --> G3{"device tests and regression pass?"}
  G3 -->|no| FIX3["fix agent/gameplay integration"]
  FIX3 --> G3
  G3 -->|yes| P4["Phase 4: optional HTTPS gateway"]
  P4 --> G4{"auth + redaction + quota + offline fallback pass?"}
  G4 -->|no| FIX4["harden backend"]
  FIX4 --> G4
  G4 -->|yes| P5["Phase 5: external AI triage + draft PR"]
  P5 --> G5{"CI + human review?"}
  G5 -->|no| BLOCK["do not merge"]
  G5 -->|yes| MERGE["human-authorized merge"]
```

### تعريف اكتمال كل مرحلة

| المرحلة | دليل القبول |
|---|---|
| P1 المحلي | Godot smoke، JSON صالح، تنقية، حدود أحداث، فشل التخزين آمن، اختبار جهاز يدوي |
| P2 السيناريوهات | seed يعيد نفس تسلسل الأفعال، timeout لكل فعل وسيناريو، cleanup بعد الفشل |
| P3 وكلاء اللعب | fixtures، assertions صريحة، حالات نجاح/فشل، تقرير لكل سيناريو |
| P4 النقل | موافقة صريحة، HTTPS، مصادقة محدودة، schema validation، redaction، offline queue bounded |
| P5 التحليل | أدلة مرتبطة بالـ commit، افتراضات موسومة، patch مقترح، CI أخضر ومراجعة بشرية |

## 17. أمور يجب ألا تستنتجها من المخططات

- نجاح CI لا يعني تجربة على هاتف حقيقي.
- `storage_roundtrip` ليس اختبار crash-consistency ولا يثبت مقاومة فقد الطاقة.
- تحميل مشهد لا يثبت أن القتال أو اللمس أو AI للعدو يعمل.
- ENet loopback لا يثبت سلامة اتصال الإنترنت أو خادم عام.
- قياسات Godot لا تمثل كامل استهلاك Android/thermal behavior.
- التقرير المحلي ليس رفعًا إلى AI.
- نموذج AI لا يعرف إلا الدليل المرسل له ولا ينفذ إصلاحًا موثوقًا بذاته.
- إنشاء draft PR ليس دليل صحة؛ يجب تنفيذ الاختبارات ومراجعة الفروق.
- لا تذكر سعة «100 لاعب» أو جاهزية multiplayer الإنتاجي بلا اختبار حمل مستقل على البنية الحقيقية.

## 18. مراجع التنفيذ داخل المستودع

- `scripts/qa/qa_reporter.gd` — الحدث، الأداء، checkpoints، JSON.
- `scripts/qa/qa_test_runner.gd` — فحوص موارد وتخزين أساسية.
- `scripts/ui/main_menu.gd` — تهيئة QA وزر الفحص وعرض/نسخ التقرير.
- `scripts/core/save_system.gd` — أحداث محلية لعمليات الحفظ.
- `scripts/core/network_manager.gd` — أحداث محدودة لحالة جلسة ENet.
- `tests/qa_reporter_smoke_test.gd` — اختبارات التنقية والحدود والتصدير.
- `.github/workflows/validate.yml` — اختبارات Godot والتحقق الآلي.
- `.github/workflows/build.yml` — تصدير Android QA وAndroid debug وWeb.
- `docs/QA_ANDROID_REPORTER_AR.md` — خطوات استخدام QA على الجهاز.

راجع الملفات ونتائج CI على نفس commit قبل استخدام هذا المخطط كوثيقة اعتماد.
