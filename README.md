# ممالك الرماد | AshenKingdoms

مشروع لعبة تقمّص أدوار فانتازيا ثلاثية الأبعاد مفتوح المصدر باستخدام Godot 4.6 وGDScript. يهدف المشروع إلى استهداف Android وWeb أولًا، ثم توسيعه للحاسوب وخادم لعب جماعي مخصص.

**الحالة الحالية:** هيكل أولي للتحقق والبناء الآلي، وليس لعبة مكتملة. لا توجد أنظمة قصة أو قتال أو شبكة إنتاجية حتى الآن.

## المنصات

- Android: APK تجريبي لأجهزة ARM64.
- Web: ملفات HTML5 تُحفظ كـ Artifact ويمكن نشرها على استضافة ملفات ثابتة.
- Dedicated server: تخطيط أولي فقط؛ لا توجد استضافة لعب حي مرفقة.

## العمل من الهاتف عبر Codespaces

1. افتح Code ثم Codespaces ثم Create codespace on main.
2. يثبت Dev Container أداة Godot CLI.
3. تحقق من المشروع من الطرفية:

   ~~~bash
   godot --headless --path . --editor --quit
   ~~~

4. استخدم Source Control ثم Commit وPush لحفظ التعديلات.

Codespaces مناسب لتحرير السكربتات والتوثيق والملفات النصية، لكنه ليس محرر Godot الرسومي داخل المتصفح.

## البناء الآلي

Workflow التحقق يعمل على main وعند Pull Request. Workflow البناء يصدر Android وWeb عند الدفع إلى main أو يدويًا من Actions.

- Artifact: ashen-kingdoms-web
- Artifact: ashen-kingdoms-android-debug
- إعدادات التصدير في export_presets.cfg.
- ملفات البناء مؤقتة، ولا يحتوي المشروع على مفاتيح توقيع.

## أوامر مفيدة

~~~bash
git status
git add .
git commit -m "Describe the change"
git push
godot --headless --path . --editor --quit
~~~

## التراخيص

الكود تحت MIT. لا توجد أصول فنية خارجية مضمنة. يجب توثيق رخصة كل نموذج أو خامة أو صوت أو خط يضاف لاحقًا في docs/ASSET_CREDITS.md. لا ترفع أسرارًا أو مفاتيح توقيع Android إلى المستودع.
