# المساهمة في ممالك الرماد | AshenKingdoms

المشروع نموذج أولي قيد التطوير مبني على Godot 4.6 وGDScript. قبل العمل، راجع [حالة التنفيذ](docs/PROJECT_STATUS_AR.md) و[نطاق الإصدار](docs/RELEASE_SCOPE_AR.md). الميزات التجريبية أو الموجودة على فرع تطوير لا تُعامل كميزات إصدار مكتملة.

## بيئة التطوير

- Godot 4.6 stable مع قوالب التصدير المطابقة عند اختبار التصدير.
- Python 3 لفحوص الوثائق والأصول وأدوات حزم المحتوى.
- بيئة Unix-like لتشغيل timeout وtools/test-network-loopback.sh.
- ارجع إلى [دليل البناء](docs/BUILD_ANDROID_WEB_AR.md) و[دليل التطوير من هاتف Android](docs/CLOUD_PHONE_GUIDE_AR.md) عند الحاجة.

## سير العمل

1. أنشئ فرعًا مخصصًا للتغيير، ولا تعدّل main مباشرة.
2. اجعل التغيير محدود النطاق، وأضف أو حدّث اختبارًا يثبت السلوك المطلوب.
3. حدّث الوثائق في Pull Request نفسه. يجب أن تتطابق README.md وdocs/README.md وصفحة حالة التنفيذ مع الواقع.
4. اشرح في وصف PR المشكلة والحل والمخاطر والقيود المتبقية والاختبارات التي شُغّلت فعلًا.
5. لا تدمج قبل نجاح جميع فحوص CI على رأس الفرع الحالي ومراجعة التغيير. لا تعتمد على تشغيل ناجح لنسخة أقدم من الـ commit.

## فحوص محلية مفيدة

شغّل من جذر المستودع بعد تثبيت المتطلبات:

~~~bash
python3 tools/validate_docs.py
python3 tools/validate_free_assets.py
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/script_load_smoke_test.gd
godot --headless --path . --script res://tests/gameplay_smoke_test.gd
godot --headless --path . --script res://tests/gameplay_regression_test.gd
godot --headless --path . --script res://tests/player_character_smoke_test.gd
timeout 45s godot --headless --path . res://tests/network_combat_smoke_test.tscn
godot --headless --path . --script res://tests/battle_royale_rules_smoke_test.gd
bash tools/test-network-loopback.sh enet
bash tools/test-network-loopback.sh websocket
godot --headless --path . --script res://tests/content_catalog_smoke_test.gd
python -m unittest tools.test_package_content tools.test_sign_content_catalog -v
~~~

هذه قائمة محلية مرجعية؛ راجع docs/TEST_PLAN.md للتفاصيل. لا تدّعِ نجاح اختبار لم يتم تشغيله. اختبارات loopback لا تعادل تجربة متصفح مع خادم WSS منشور، أو اختبار أجهزة فعلية، أو اختبار حمل.

## الأصول والرخص

قبل إضافة نموذج أو خامة أو صوت أو خط أو فيديو، تحقق من المصدر الأصلي ونص الرخصة وحقوق الاستخدام التجاري والتعديل وإعادة التوزيع والإسناد. حدّث assets/asset_manifest.json وdocs/ASSET_CREDITS.md وشغّل python3 tools/validate_free_assets.py. «مجاني» لا يعني بالضرورة «مفتوح الترخيص».

## الأمان والخصوصية

لا تضف أسرارًا أو مفاتيح توقيع أو مفاتيح API أو سجلات تتضمن بيانات شخصية إلى Git. راجع [سياسة الأمان](SECURITY.md) قبل الإبلاغ عن مشكلة حساسة. أنظمة الشبكة تجريبية وليست جاهزة لاستضافة عامة إنتاجية.
