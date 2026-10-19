# دليل التطوير السحابي من متصفح هاتف Android

## ما الذي يعمل في المتصفح؟

GitHub Codespaces يوفر محررًا شبيهًا بـ VS Code وطرفية سحابية لتعديل GDScript وملفات المشروع وYAML وMarkdown وتشغيل Godot headless. لكنه ليس محرر Godot الرسومي داخل المتصفح.

## بدء Codespace

1. افتح المستودع في GitHub.
2. اختر Code ثم Codespaces ثم Create codespace on main.
3. انتظر انتهاء إعداد Dev Container وتنزيل Godot CLI.
4. افتح Terminal ونفّذ:

   ~~~bash
   godot --version
   godot --headless --path . --editor --quit
   ~~~

5. عدّل الملفات ثم استخدم Source Control لعمل Commit وPush.

## إدارة الاستهلاك المجاني

تتغير حصة Codespaces وفق نوع الحساب وسياسة GitHub الحالية، وقد تختلف بحسب طريقة الدفع والبلد والميزات المتاحة. لا تعتمد أرقامًا محفوظة في هذا الدليل؛ افتح صفحة الفوترة والاستخدام في حسابك قبل بدء جلسة طويلة، ثم أوقف البيئة عند الانتهاء.

- أوقف Codespace بعد الانتهاء.
- اضبط Idle timeout على قيمة قصيرة.
- لا تترك أكثر من مساحة تعمل دون داعٍ.
- لا تثبت Android SDK كاملًا في Codespaces إلا إذا احتجته؛ GitHub Actions يتولى بناء Android.
- تجنب تنزيل قوالب تصدير ضخمة إلى مساحة التطوير إذا كان البناء في CI.
- راجع Settings ثم Billing and licensing ثم Usage.
- عند نفاد الحصة دون فوترة مدفوعة، قد يتعذر فتح Codespace حتى تجديد الحصة.

## الموارد المجانية المستخدمة

- GitHub Public Repository: استضافة الكود وسجل التعديلات والقضايا.
- GitHub Actions: تحقّق من حدود المشغلات وسياسة الاستخدام الحالية؛ لا تفترض أن كل نوع تشغيل أو مساحة تخزين أو خدمة خارجية مجانية.
- GitHub Pages: استضافة ملفات ثابتة ضمن حدود الاستخدام إذا رغبت بنشر Web.
- Godot: محرك مفتوح المصدر دون رسوم ترخيص للمحرك.
- Codespaces: حصة مجانية محدودة، وليست بيئة تطوير سحابية غير محدودة.

## سير العمل اليومي

1. افتح Codespace فقط وقت العمل.
2. عدّل السكربتات والتوثيق.
3. نفّذ فحص المشروع.
4. راجع التغييرات باستخدام git status.
5. نفّذ git add ثم git commit ثم git push.
6. افتح Actions وتحقق من نجاح البناء.
7. نزّل Artifact لاختبار APK أو نسخة Web.

## أوامر مفيدة

~~~bash
git status
git add .
git commit -m "Describe the change"
git push
godot --headless --path . --editor --quit
~~~

لا تضف مجلد .godot أو ملفات APK أو مفاتيح توقيع إلى Git.
