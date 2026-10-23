# سجل العمل المفتوح في GitHub — ممالك الرماد

> **لقطة بيانات:** 2026-10-23 UTC  
> **المستودع:** [areagleegy/AshenKingdoms](https://github.com/areagleegy/AshenKingdoms)  
> **الغرض:** سجل مرجعي لحالات القضايا وطلبات الدمج المفتوحة التي أرجعتها واجهة GitHub وقت إنشاء اللقطة. هذا السجل ليس حالة حيّة، ولا يثبت اكتمال أي ميزة.

## متابعة بعد الدمج — 2026-10-23

بعد إعداد اللقطة التاريخية التالية ودمج [PR #97](https://github.com/areagleegy/AshenKingdoms/pull/97)، أُعيد الاستعلام عن GitHub:

- رأس `main` عند المتابعة: `11f1168a9a33c06a20c93a12ba2eef0f8bc8be43`.
- العدد الحالي وقت هذا الاستعلام: **53 Pull Requests مفتوحة** و**16 Issue مفتوحة مستقلة**.
- [PR #97](https://github.com/areagleegy/AshenKingdoms/pull/97) مدمج؛ لم يعد ضمن قائمة PRs المفتوحة.
- الجدول التاريخي أدناه يحتفظ بلقطة ما قبل الدمج عمدًا: لذلك يظهر فيه 54 PR مفتوحًا ويعرض PR #97 مفتوحًا. لا تستخدم الأعداد أو الحالة في الجدول التاريخي باعتبارها العدد الحي.
- المصدر الحالي قبل اتخاذ إجراء هو [قائمة Pull Requests](https://github.com/areagleegy/AshenKingdoms/pulls) و[قائمة Issues](https://github.com/areagleegy/AshenKingdoms/issues). أعد الاستعلام لتحديث اللقطة بدل تعديل الماضي بأثر رجعي.

## 1. ملخص اللقطة

- رأس الفرع الافتراضي `main`: `683975a2ef03bd283ee821b075d7b9f81f2c05b8`.
- عدد طلبات الدمج المفتوحة التي أُعيدت من GitHub: **54**.
- عدد Issues المفتوحة المستقلة (استبعاد العناصر التي تمثل Pull Requests): **16**.
- طلب توثيق الاستمرارية [PR #97](https://github.com/areagleegy/AshenKingdoms/pull/97): `مفتوح — غير مسودة`; رأس الفرع المرصود `0c6dc9dc3237941e5dde949f65e538bcd116e068`; قاعدة الدمج `683975a2ef03bd283ee821b075d7b9f81f2c05b8`.
- حالة الدمج والاختبارات قابلة للتغير مباشرة بعد وقت اللقطة. أعد جلب بيانات GitHub قبل الاعتماد التشغيلي.
- قد يحتوي المستودع على فروع وعمليات محلية وطلبات مغلقة لا تظهر في الجدولين؛ هذه اللقطة تغطي العناصر المفتوحة فقط.

## 2. قواعد تفسير البيانات

- **مفتوح — مسودة:** طلب الدمج لم يُدمج، وقد يكون العمل غير جاهز للمراجعة النهائية.
- **مفتوح — غير مسودة:** لا يعني الموافقة أو نجاح CI؛ يظل الدمج مشروطًا بالمراجعة ومتطلبات المستودع.
- **رأس الفرع (SHA):** يحدد الالتزام الذي شوهد وقت اللقطة؛ أي نجاح CI يجب ربطه برأس محدد.
- **تاريخ التحديث:** وقت آخر تحديث مسجل في GitHub، وليس بالضرورة تاريخ آخر تعديل للكود.
- **Issue مفتوحة:** لا يعني أنها مانعة للإصدار تلقائيًا؛ راجع الوصف ومعايير القبول والمخاطر.
- الحالات هنا **لقطة موثقة آليًا**. راجع وصف PR، الملفات المتغيرة، المراجعات، وسجلات Actions قبل اتخاذ قرار.

## 3. كل Pull Requests المفتوحة

ترتيب الجدول وفق آخر تحديث أرجعته API. لا يعني ترتيبها الأولوية أو الاستعداد للدمج.

| PR | العنوان | الحالة | الفرع | رأس SHA وقت اللقطة | آخر تحديث UTC |
|---|---|---|---|---|---|
| [#97](https://github.com/areagleegy/AshenKingdoms/pull/97) | docs: preserve project context and map repository coverage | مفتوح — غير مسودة | `docs/context-preservation-20261023` | `0c6dc9dc3237` | 2026-10-23 |
| [#95](https://github.com/areagleegy/AshenKingdoms/pull/95) | refactor: extract shared progression threshold rule | مفتوح — غير مسودة | `refactor/domain-progression-rules` | `1ab6508d3910` | 2026-10-23 |
| [#88](https://github.com/areagleegy/AshenKingdoms/pull/88) | test: verify asset editor plugin registration | مفتوح — غير مسودة | `test/asset-plugin-smoke-tests` | `1e5cc09afe85` | 2026-10-23 |
| [#94](https://github.com/areagleegy/AshenKingdoms/pull/94) | docs: add engineering blueprint and staged architecture roadmap | مفتوح — مسودة | `docs/engineering-blueprint-ar` | `5794da711e4f` | 2026-10-23 |
| [#67](https://github.com/areagleegy/AshenKingdoms/pull/67) | Add Arabic world bible and structured Ashen Kingdoms catalog | مفتوح — مسودة | `ai/world-expansion-phase-1` | `382eabc4d2b3` | 2026-10-23 |
| [#64](https://github.com/areagleegy/AshenKingdoms/pull/64) | feat: add combat catalogs and wire player damage and timing | مفتوح — مسودة | `feature/combat-catalog-validation` | `95326aa06156` | 2026-10-23 |
| [#61](https://github.com/areagleegy/AshenKingdoms/pull/61) | fix: make save writes recoverable and add atomic-save tests | مفتوح — مسودة | `fix/atomic-save-reliability` | `b48a70b873b2` | 2026-10-23 |
| [#93](https://github.com/areagleegy/AshenKingdoms/pull/93) | Draft: harden local save validation and recovery | مفتوح — مسودة | `fix/save-system-hardening-2026-10-23` | `28b2a4b15763` | 2026-10-23 |
| [#92](https://github.com/areagleegy/AshenKingdoms/pull/92) | ci: add experimental Android QA APK with diagnostics | مفتوح — مسودة | `qa/experimental-apk-ai-diagnostics-2026-10-23` | `59271be37e2c` | 2026-10-23 |
| [#90](https://github.com/areagleegy/AshenKingdoms/pull/90) | docs: add comprehensive core audit report (2026-10-23) | مفتوح — مسودة | `docs/core-audit-ar-2026-10-23` | `876e4567e68c` | 2026-10-23 |
| [#74](https://github.com/areagleegy/AshenKingdoms/pull/74) | Harden save integrity, validation, and recovery | مفتوح — غير مسودة | `fix/p0-save-integrity` | `32b6b59ee2c3` | 2026-10-23 |
| [#89](https://github.com/areagleegy/AshenKingdoms/pull/89) | qa: extend Android beta device testing and local AI triage | مفتوح — مسودة | `qa/android-device-behavior-analysis` | `c12485cccb72` | 2026-10-23 |
| [#87](https://github.com/areagleegy/AshenKingdoms/pull/87) | docs: define free-first AI integration path | مفتوح — غير مسودة | `docs/aimlapi-free-first-integration` | `c830b7e81e26` | 2026-10-23 |
| [#81](https://github.com/areagleegy/AshenKingdoms/pull/81) | Fix autosave handling on window close | مفتوح — مسودة | `fix/ashen-patch-close-save` | `f517a35fcf36` | 2026-10-23 |
| [#86](https://github.com/areagleegy/AshenKingdoms/pull/86) | security: require verified provenance for downloadable content | مفتوح — مسودة | `security/content-provenance-gate` | `8ddc0a7f2833` | 2026-10-22 |
| [#80](https://github.com/areagleegy/AshenKingdoms/pull/80) | Add Android QA runtime reporting and smoke checks | مفتوح — مسودة | `feature/android-qa-reporter` | `f2b002f08511` | 2026-10-22 |
| [#71](https://github.com/areagleegy/AshenKingdoms/pull/71) | Harden save recovery, network input validation, and CI credentials | مفتوح — مسودة | `fix/audit-save-network-ci` | `32d363166a1e` | 2026-10-22 |
| [#72](https://github.com/areagleegy/AshenKingdoms/pull/72) | Add cross-platform exports, controller UX, network hardening and Android release pipeline | مفتوح — غير مسودة | `ci/multiplatform-export-presets` | `9aa01f47b795` | 2026-10-22 |
| [#77](https://github.com/areagleegy/AshenKingdoms/pull/77) | Harden remote content package URL validation | مفتوح — مسودة | `security/strict-content-url-validation` | `4a765d5acd29` | 2026-10-22 |
| [#76](https://github.com/areagleegy/AshenKingdoms/pull/76) | fix: preserve content pack failure notifications | مفتوح — مسودة | `fix/content-catalog-failure-state` | `68acd575807f` | 2026-10-22 |
| [#75](https://github.com/areagleegy/AshenKingdoms/pull/75) | Validate multiplayer input and rate-limit RPCs | مفتوح — غير مسودة | `fix/network-rpc-validation` | `9980e6cca636` | 2026-10-22 |
| [#70](https://github.com/areagleegy/AshenKingdoms/pull/70) | docs: add repository-grounded architecture briefing | مفتوح — غير مسودة | `docs/project-architecture-briefing-2026-10-22` | `6de52edfb88a` | 2026-10-22 |
| [#69](https://github.com/areagleegy/AshenKingdoms/pull/69) | Harden local saves and network input RPCs | مفتوح — مسودة | `hardening/save-system-v1` | `0f117a3236e3` | 2026-10-22 |
| [#66](https://github.com/areagleegy/AshenKingdoms/pull/66) | Harden Android save persistence and add regression tests | مفتوح — مسودة | `fix/android-save-system-hardening` | `2d70394a59f9` | 2026-10-22 |
| [#68](https://github.com/areagleegy/AshenKingdoms/pull/68) | Add grid inventory UI and loot transfer foundation | مفتوح — مسودة | `feature/inventory-grid-loot-foundation` | `b5afcc54d518` | 2026-10-22 |
| [#65](https://github.com/areagleegy/AshenKingdoms/pull/65) | Add GDScript quality gates and combat regression coverage | مفتوح — مسودة | `ai/quality-gates-combat-tests` | `dfad250605ff` | 2026-10-21 |
| [#63](https://github.com/areagleegy/AshenKingdoms/pull/63) | feat(combat): add weapon data and deterministic attack runtime | مفتوح — مسودة | `docs/world-content-combat-blueprint-ar` | `50ec1262ef6b` | 2026-10-21 |
| [#62](https://github.com/areagleegy/AshenKingdoms/pull/62) | ci: add GDScript and Python static checks | مفتوح — مسودة | `ci/gdscript-python-linting` | `0bb7a3d236cb` | 2026-10-21 |
| [#60](https://github.com/areagleegy/AshenKingdoms/pull/60) | test: add physics and combat regression coverage | مفتوح — مسودة | `test/physics-combat-vehicle-companion-2026-10-21` | `e7710c113d0b` | 2026-10-21 |
| [#59](https://github.com/areagleegy/AshenKingdoms/pull/59) | fix(audio): add category mixer buses and persistence tests | مفتوح — مسودة | `fix/audio-mixer-buses-2026-10-21` | `541dd5c5eeac` | 2026-10-21 |
| [#58](https://github.com/areagleegy/AshenKingdoms/pull/58) | docs: comprehensive visual, audio, and asset-package coverage plan | مفتوح — مسودة | `docs/full-asset-coverage-plan-2026-10-21` | `2d217013ad3b` | 2026-10-21 |
| [#54](https://github.com/areagleegy/AshenKingdoms/pull/54) | Harden local save writes against interrupted writes | مفتوح — مسودة | `fix/atomic-save-system` | `532fb32d09da` | 2026-10-21 |
| [#56](https://github.com/areagleegy/AshenKingdoms/pull/56) | Validate and rate-limit network movement input | مفتوح — مسودة | `fix/network-input-validation-20261021` | `226ecc391379` | 2026-10-21 |
| [#57](https://github.com/areagleegy/AshenKingdoms/pull/57) | Add automated Test Lab, scenario catalog, and AI-assisted diagnostics | مفتوح — مسودة | `qa/ai-test-lab-scenarios-20261021` | `e48c0ad4893e` | 2026-10-21 |
| [#55](https://github.com/areagleegy/AshenKingdoms/pull/55) | Document forensic development and release-quality roadmap | مفتوح — مسودة | `docs/forensic-development-roadmap` | `6a4e2a4cc007` | 2026-10-21 |
| [#53](https://github.com/areagleegy/AshenKingdoms/pull/53) | test: add comprehensive enemy AI behavior coverage | مفتوح — مسودة | `test/enemy-ai-coverage-2026-10-21` | `a63570dfbbf6` | 2026-10-21 |
| [#51](https://github.com/areagleegy/AshenKingdoms/pull/51) | Harden save replacement and network input validation | مفتوح — مسودة | `fix/save-network-hardening-followup` | `9d52821ad844` | 2026-10-21 |
| [#52](https://github.com/areagleegy/AshenKingdoms/pull/52) | fix: validate and rate-limit multiplayer input updates | مفتوح — مسودة | `fix/network-input-hardening-2026-10-21` | `4654d5d28c7d` | 2026-10-21 |
| [#49](https://github.com/areagleegy/AshenKingdoms/pull/49) | assets: add UI icons, original SFX pack, and forensic pipeline | مفتوح — مسودة | `assets/ui-foundation-icons-2026-10-21` | `f212eed04b03` | 2026-10-21 |
| [#50](https://github.com/areagleegy/AshenKingdoms/pull/50) | assets: integrate original synthesized gameplay audio pack | مفتوح — مسودة | `assets/audio-foundation-sfx-2026-10-21` | `4b5c6056e809` | 2026-10-21 |
| [#38](https://github.com/areagleegy/AshenKingdoms/pull/38) | fix: validate and rate-limit multiplayer input RPC | مفتوح — مسودة | `fix/network-input-validation-2026-10-20` | `fd2b3086617e` | 2026-10-20 |
| [#37](https://github.com/areagleegy/AshenKingdoms/pull/37) | fix: protect save data during interrupted writes | مفتوح — مسودة | `fix/save-system-atomic-write` | `99c854ce9545` | 2026-10-20 |
| [#36](https://github.com/areagleegy/AshenKingdoms/pull/36) | Harden save recovery and multiplayer input validation | مفتوح — مسودة | `fix/p0-save-hardening` | `1927a9df2fcb` | 2026-10-20 |
| [#32](https://github.com/areagleegy/AshenKingdoms/pull/32) | Harden save persistence and network movement input | مفتوح — مسودة | `fix/security-save-hardening` | `ae654fd6b1ff` | 2026-10-20 |
| [#29](https://github.com/areagleegy/AshenKingdoms/pull/29) | docs: establish Android-first phase 1 baseline | مفتوح — مسودة | `docs/execution-baseline-2026-10-20` | `38cde01316c0` | 2026-10-20 |
| [#35](https://github.com/areagleegy/AshenKingdoms/pull/35) | P0: harden save writes and validate network input | مفتوح — مسودة | `fix/p0-save-network-validation` | `7ac4c8b3934b` | 2026-10-20 |
| [#33](https://github.com/areagleegy/AshenKingdoms/pull/33) | Reject non-finite multiplayer movement input | مفتوح — مسودة | `fix/network-input-validation` | `72e3fcaad6aa` | 2026-10-20 |
| [#31](https://github.com/areagleegy/AshenKingdoms/pull/31) | fix: harden save schema, backups, and recovery | مفتوح — مسودة | `fix/save-integrity-schema-v1-2026-10-20` | `d9ac7bc0c9b0` | 2026-10-20 |
| [#30](https://github.com/areagleegy/AshenKingdoms/pull/30) | test: cover the solo vertical slice end to end | مفتوح — مسودة | `test/vertical-slice-integration-2026-10-20` | `304d70fcf850` | 2026-10-20 |
| [#24](https://github.com/areagleegy/AshenKingdoms/pull/24) | Add experimental WebSocket multiplayer and fantasy battle royale prototype | مفتوح — مسودة | `feat/websocket-multiplayer-online` | `03e680c2725a` | 2026-10-20 |
| [#28](https://github.com/areagleegy/AshenKingdoms/pull/28) | Harden network input and damage edge cases | مفتوح — مسودة | `fix/finite-network-input-damage` | `afa0f8103c33` | 2026-10-20 |
| [#27](https://github.com/areagleegy/AshenKingdoms/pull/27) | docs: organize repository documentation, diagrams, and references | مفتوح — غير مسودة | `docs/repository-audit-diagrams-2026-10-19` | `ff316b5d3339` | 2026-10-19 |
| [#26](https://github.com/areagleegy/AshenKingdoms/pull/26) | docs: consolidate master roadmap and project changelog | مفتوح — غير مسودة | `docs/master-roadmap-2026-10` | `aafc59e3df00` | 2026-10-19 |
| [#25](https://github.com/areagleegy/AshenKingdoms/pull/25) | توثيق: إضافة مرجع شامل ومخططات المشروع | مفتوح — غير مسودة | `docs/project-master-reference-ar` | `cbf815077ebd` | 2026-10-19 |

## 4. كل Issues المفتوحة المستقلة

استبعدنا العناصر التي تمثل PR من قائمة Issues. هذه قائمة فهرسة؛ تفاصيل المخاطر ومعايير إغلاق كل قضية تبقى في صفحة القضية نفسها.

| Issue | العنوان | آخر تحديث UTC |
|---|---|---|
| [#96](https://github.com/areagleegy/AshenKingdoms/issues/96) | Align progression level bounds and XP-at-cap behavior | 2026-10-23 |
| [#91](https://github.com/areagleegy/AshenKingdoms/issues/91) | [P1] Make save writes recoverable and validate loaded game state | 2026-10-23 |
| [#48](https://github.com/areagleegy/AshenKingdoms/issues/48) | [A1/A9/P0] Forensic review of Godot add-ons, generator and content loaders | 2026-10-22 |
| [#42](https://github.com/areagleegy/AshenKingdoms/issues/42) | [A4/P0] Build the first playable Ashen Ruins environment slice | 2026-10-22 |
| [#34](https://github.com/areagleegy/AshenKingdoms/issues/34) | [P0] Close release-blocking gaps from Unified Development Blueprint | 2026-10-22 |
| [#73](https://github.com/areagleegy/AshenKingdoms/issues/73) | Plan native PlayStation 5 and Xbox Series X\|S releases | 2026-10-22 |
| [#47](https://github.com/areagleegy/AshenKingdoms/issues/47) | [A9/P0] Gate content packs on asset provenance, integrity and rollback | 2026-10-20 |
| [#46](https://github.com/areagleegy/AshenKingdoms/issues/46) | [A8/P0] Establish Android visual/audio performance and acceptance tests | 2026-10-20 |
| [#45](https://github.com/areagleegy/AshenKingdoms/issues/45) | [A7/P1] Add UI icon assets and readable combat feedback | 2026-10-20 |
| [#44](https://github.com/areagleegy/AshenKingdoms/issues/44) | [A6/P0] Build the first licensed audio pack and Arabic dialogue workflow | 2026-10-20 |
| [#43](https://github.com/areagleegy/AshenKingdoms/issues/43) | [A3/P1] Create the first Ash Wraith model and core combat animation set | 2026-10-20 |
| [#41](https://github.com/areagleegy/AshenKingdoms/issues/41) | [A3/P0] Replace the player fallback with one licensed, rigged GLB | 2026-10-20 |
| [#40](https://github.com/areagleegy/AshenKingdoms/issues/40) | [A1/P0] Automate the visual/audio asset forensic inventory | 2026-10-20 |
| [#20](https://github.com/areagleegy/AshenKingdoms/issues/20) | Release gate: verify target devices, final assets, and production packaging | 2026-10-20 |
| [#21](https://github.com/areagleegy/AshenKingdoms/issues/21) | Implement and verify multiplayer transport for Web before claiming platform parity | 2026-10-20 |
| [#22](https://github.com/areagleegy/AshenKingdoms/issues/22) | Add a verified free/open-license asset pack and provenance records | 2026-10-19 |

## 5. نتائج CI الخاصة بطلب التوثيق PR #97

النتائج التالية هي ما أرجعته GitHub Actions في وقت توليد اللقطة، مرتبطة برأس كل تشغيل؛ إذا كان التشغيل على SHA أقدم من رأس PR الحالي فلا يُعد دليلًا على الرأس الجديد.

| سير العمل | SHA المختصر | الحالة | النتيجة |
|---|---|---|---|
| [Validate Godot Project — #40005100375](https://github.com/areagleegy/AshenKingdoms/actions/runs/40005100375) | `0c6dc9dc3237` | completed | success |
| [Build Android and Web — #40005100654](https://github.com/areagleegy/AshenKingdoms/actions/runs/40005100654) | `0c6dc9dc3237` | completed | success |
| [Validate Godot Project — #40005042693](https://github.com/areagleegy/AshenKingdoms/actions/runs/40005042693) | `0851834f22a1` | completed | success |
| [Build Android and Web — #40005042738](https://github.com/areagleegy/AshenKingdoms/actions/runs/40005042738) | `0851834f22a1` | completed | success |
| [Validate Godot Project — #40005021816](https://github.com/areagleegy/AshenKingdoms/actions/runs/40005021816) | `ebd1abe1e919` | completed | success |
| [Build Android and Web — #40005021815](https://github.com/areagleegy/AshenKingdoms/actions/runs/40005021815) | `ebd1abe1e919` | completed | success |

رأس PR #97 الذي رُصد عند إنشاء هذا السجل: `0c6dc9dc3237941e5dde949f65e538bcd116e068`. يجب الرجوع إلى [PR #97](https://github.com/areagleegy/AshenKingdoms/pull/97) للتحقق من رأسه الحالي ومن أن جميع الفحوص المطلوبة قد انتهت.

## 6. العمل التوثيقي المرتبط

- [فهرس التوثيق](README.md).
- [خريطة تغطية توثيق المستودع](REPOSITORY_DOCUMENTATION_MAP_AR.md).
- [سجل الاستمرارية](CONTINUITY.md).
- [فهرس سياق المحادثات](CONVERSATION_CONTEXT_ARCHIVE_AR.md).
- [نقطة تسليم الجلسة](SESSION_HANDOFF_AR.md).
- [تدقيق التوثيق وخطة الاستكمال](DOCUMENTATION_AUDIT_AR.md).
- [تدقيق Issues وPull Requests التاريخي](ISSUE_AUDIT_AR.md)؛ يحتوي على لقطة أقدم ولا ينبغي الخلط بينها وبين هذه اللقطة المؤرخة.

## 7. قواعد تحديث السجل

1. عند كل مراجعة كبيرة، أعد جلب قائمة PRs وIssues المفتوحة من GitHub.
2. سجّل التاريخ وUTC، SHA الفرع الأساسي، SHA رأس PR التوثيقي، وعدد العناصر في اللقطة.
3. احتفظ بروابط GitHub الأصلية بدل نسخ تفاصيل طويلة قد تتقادم.
4. حدّث التحليل والأولويات في [تدقيق Issues وPRs](ISSUE_AUDIT_AR.md) عند تغيّر المخاطر، ولا تعتبر اسم الفرع أو عنوان PR دليلًا على أن الإصلاح اكتمل.
5. لا تدمج أو تغلق العناصر تلقائيًا بغرض تنظيف القائمة؛ يجب مراجعة النطاق والفروع والأدلة أولًا.
6. لا تضع أسرارًا أو رموز وصول أو مفاتيح توقيع في سجل العمل.
7. أبقِ هذا الملف لقطة موقّتة، لا بديلًا عن GitHub نفسه.

**ملاحظة:** تسجيل جميع العناصر المفتوحة يعزز قابلية التتبع لكنه لا يعني أن جميعها ضمن الإصدار نفسه، أو أنها متوافقة مع بعضها، أو أن دمجها كلها مطلوب. يجب ترتيبها حسب الأولوية والاعتماديات وخطر التغيير.


- [خريطة تداخل طلبات الدمج](PR_REVIEW_DEPENDENCIES_AR.md) تحلل الملفات المشتركة في مجموعات الحفظ والشبكة والمحتوى والأصول وQA؛ استخدمها قبل دمج طلبات متوازية.
