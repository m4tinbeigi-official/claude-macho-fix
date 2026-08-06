# Claude Desktop — إصلاح خطأ "Malformed Mach-o file" / سلامة ASAR (macOS)

🌐 **اقرأ هذا الملف بلغة أخرى:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

إصلاح وشرح لعطلين مترابطين قد يحدثان على **Claude Desktop لنظام macOS**
بعد أن يتم تعديل `app.asar` (شيفرة التطبيق المُعبّأة الخاصة بـ Claude Desktop) —
سواء عبر تعديل من طرف ثالث، أو إضافة (plugin)، أو تعديل يدوي، أو أي شيء آخر
يعيد تعبئة أو تحرير حزمة التطبيق.

هذا الأمر **غير** مقتصر على أداة أو مُعدِّل واحد بعينه. أي مشروع يقوم باستخراج
`app.asar` الخاص بـ Claude Desktop وتعديله وإعادة تعبئته يمكن أن يتسبب في
ظهور إحدى هاتين المشكلتين أو كليهما إن لم يتعامل بشكل صحيح مع تفصيلين خاصين
بنظام macOS/Electron. يوثّق هذا المستودع كلا السببين الجذريين ويوفّر سكربت
إصلاح بأمر واحد.

---

## العرض الأول — تبويب Claude Code لا يبدأ التشغيل

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

يفشل **تبويب Claude Code** فقط. بقية أجزاء Claude Desktop (الدردشة، إلخ)
تعمل بشكل طبيعي.

## العرض الثاني — التطبيق بأكمله لا يفتح

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

لا يفتح أي شيء على الإطلاق — تتوقف العملية فورًا عند التشغيل. لن تشاهد هذه
الرسالة إلا إذا قمت بتشغيل الملف التنفيذي لـ Claude Desktop مباشرة من الطرفية
(`/Applications/Claude.app/Contents/MacOS/Claude`)؛ أما النقر المزدوج على
التطبيق فيؤدي فقط إلى فشل صامت في الفتح.

---

## الأسباب الجذرية

### 1. تم تضمين ملف تنفيذي أصلي (native binary) *داخل* `app.asar` بدلًا من إبقائه غير مُعبّأ على القرص

تحتفظ تطبيقات Electron ببعض الملفات — الوحدات الأصلية (`*.node`)،
المكتبات الديناميكية (`*.dylib`)، وأي ملفات مساعدة تنفيذية أصلية أخرى —
فعليًا خارج التعبئة على القرص، بجانب `app.asar`، داخل مجلد شقيق باسم
`app.asar.unpacked/`. أما كل شيء آخر فيُخزَّن مُعبّأً داخل ملف الأرشيف
الواحد `app.asar`.

إذا كان سكربت إعادة التعبئة يحدد ما يجب إبقاؤه خارج التعبئة باستخدام
قائمة **ثابتة (hardcoded)** من امتدادات الملفات (نمط شائع:
`{*.node,*.dylib,spawn-helper}`)، فإن أي ملف تنفيذي أصلي لا يطابق هذه
القائمة — على سبيل المثال ملف مساعد تنفيذي لتبويب Claude Code يُشحن بدون
أحد هذه الامتدادات — يُضمَّن حينها *داخل* الأرشيف بدلاً من ذلك. إدخال
الأرشيف ليس ملفًا حقيقيًا قابلًا للتنفيذ بشكل مستقل: لا يستطيع نظام
التشغيل تنفيذ (`exec()`) نطاق بايتات في منتصف ملف آخر والحصول على برنامج
صالح منه. عندما يحاول Claude Desktop تشغيل ذلك الملف التنفيذي، يقرأ نظام
التشغيل مجموعة بايتات غير محاذاة لبنية ملف، ويبلّغ عن ذلك كملف Mach-O
تالف/غير صالح — ومن هنا تأتي رسالة "Malformed Mach-o file".

**الإصلاح:** لا تُثبّت قائمة عدم التعبئة (unpack list) بشكل ثابت. احسبها
ديناميكيًا من الملفات غير المُعبّأة *الموجودة بالفعل* بجانب `app.asar`
الأصلي قبل إجراء أي تعديل، واستخدم نفس المجموعة عند إعادة التعبئة. راجع
[`lib/unpack.js`](../lib/unpack.js) للحصول على تنفيذ جاهز للاستخدام
المباشر، وتحقق بعد إعادة التعبئة من عدم فقدان أي شيء.

### 2. إعادة التوقيع دون إزالة التوقيعات المتداخلة القديمة أولاً

تعديل الملفات داخل `app.asar` يُبطل التوقيعات الرقمية المتداخلة للحزم
الفرعية الموقَّعة مسبقًا والتي تُشحن بجانبه
(`Contents/Frameworks/*.framework`، `Contents/Frameworks/*.app` المساعِدة،
`Contents/Helpers/*`، خدمات XPC المضمَّنة، إلخ) — لكنه لا يزيل تلك
التوقيعات القديمة. تشغيل `codesign --force --deep --sign -` فوق هذه
التوقيعات يمكن أن يترك الحزمة في حالة غير متسقة:

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

خطوة *التوقيع* نفسها تُبلّغ بالنجاح ("replacing existing signature") —
والفشل لا يظهر إلا عند تشغيل `--verify`، وهو أمر يسهل تفويته إن لم تتحقق
منه صراحةً.

**الإصلاح:** شغّل `codesign --remove-signature --deep` أولًا لإزالة كل
التوقيعات المتداخلة، *ثم* وقّع من جديد بالكامل. راجع
[`lib/macos.js`](../lib/macos.js).

### 3. آلية Electron المدمجة للتحقق من سلامة ASAR (fuse)

هذا هو السبب الذي يتسبب في العرض الثاني (عدم فتح التطبيق بالكامل). يحتوي
Electron على "فيوز" (fuse) يُضبط وقت البناء — اسمه
`EnableEmbeddedAsarIntegrityValidation` — والذي، عند تفعيله، يُضمِّن قيمة
تجزئة SHA-256 المتوقَّعة لملف `app.asar` مباشرةً داخل **الملف التنفيذي
لإطار عمل Electron (Electron Framework binary)**
(`Contents/Frameworks/Electron Framework.framework/Electron Framework`
على macOS — *وليس* الملف التنفيذي الرئيسي للتطبيق الموجود في
`Contents/MacOS/`، و*ليس* أي مفتاح `ElectronAsarIntegrity` قد تجده في
`Info.plist`، وهو آلية قديمة منفصلة وغير ذات صلة تكتبها بعض أدوات البناء
أيضًا بالمصادفة).

بمجرد تعديل `app.asar`، لن تتطابق قيمة التجزئة المضمَّنة بعد الآن،
ويتعطل Electron فورًا عند التشغيل بدلًا من التعامل مع الأمر بأسلوب أكثر
تدرّجًا.

إعادة حساب تلك التجزئة المضمَّنة وتعديلها يدويًا أمر غير عملي — فهي جزء
من تنسيق "أسلاك الفيوز" (fuse wire) خاص بالملف الثنائي، إلى جانب عدة
أعلام أخرى. الحل المدعوم هو تعطيل الفيوز بالكامل باستخدام أداة Electron
الرسمية، [`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses):

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

هذا يُعدِّل الملف التنفيذي لإطار عمل Electron، مما يُبطل توقيعه — يجب
عليك إعادة توقيع الحزمة بأكملها بعد ذلك (إصلاح السبب الجذري رقم 2 يتكفل
بهذا).

---

## إصلاح سريع — لديك تثبيت معطوب بالفعل؟

إذا كنت بحاجة فقط إلى إصلاح `Claude.app` الذي لديك بالفعل (لست بحاجة
لمعرفة أي من الأسباب أعلاه هو المسبب — هذا يُصلح كليهما):

### نقرة واحدة (بدون طرفية)

1. [نزّل هذا المستودع](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip) وفُك ضغطه.
2. انقر نقرًا مزدوجًا على **`Fix Claude.command`**.
3. ستفتح نافذة طرفية، وترشدك عبر كل خطوة، وتعرض عليك إعادة تشغيل
   Claude Desktop نيابةً عنك عند الانتهاء.

قد يُحذّر macOS من أن الملف صادر عن مطوّر غير معروف في المرة الأولى —
انقر بزر الفأرة الأيمن عليه واختر **Open** لتجاوز ذلك مرة واحدة.

### سطر واحد (طرفية)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

أو استنسخ المستودع وشغّله محليًا:

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

يكتشف `repair.sh` تلقائيًا `Claude.app` (أو `Claude Beta.app`) في مواقع
التثبيت المعتادة، ويُغلقه إن كان قيد التشغيل، ويمرّ عبر كل خطوة إصلاح مع
مخرجات واضحة للنجاح/الفشل، ويتحقق من النتيجة، ويعرض عليك إعادة تشغيل
التطبيق. مرّر مسارًا صريحًا إن كان تطبيقك موجودًا في مكان غير اعتيادي:

```bash
./repair.sh "/path/to/Claude Beta.app"
```

لا يقوم `repair.sh` **بأي تعديل** على وظائف Claude Desktop الفعلية أو
محتواه — فهو فقط يعطّل فيوز سلامة الأرشيف ويعيد توقيع الحزمة. من الآمن
تشغيله حتى لو لم تكن متأكدًا من أي عرض تعاني منه، ومن الآمن تشغيله عدة
مرات. إن لم يستطع الكتابة إلى حزمة التطبيق، سيُطالبك بإعادة تشغيله باستخدام
`sudo`.

---

## إذا كنت تبني مُعدِّلًا (patcher) خاصًا بك

إذا كنت تكتب أداة تُعدِّل `app.asar` (لأغراض الترجمة، أو التخصيص المظهري،
أو الإضافات، أو أي شيء آخر)، يمكنك تجنّب شحن هذه الأخطاء لمستخدميك من
البداية. يتضمن هذا المستودع وحدات جاهزة للاستخدام وموثّقة:

- [`lib/unpack.js`](../lib/unpack.js) — يحسب نمط (glob) الـ `unpack`
  الصحيح لدالة `createPackageWithOptions` الخاصة بـ `@electron/asar`،
  ديناميكيًا، من الملفات غير المُعبّأة الموجودة بالفعل. بديل جاهز
  للاستخدام المباشر لقائمة امتدادات ثابتة.
- [`lib/macos.js`](../lib/macos.js) — يعيد توقيع حزمة تطبيق macOS
  بالشكل الصحيح (إزالة التوقيعات المتداخلة أولًا، ثم التوقيع من جديد
  بالكامل، ثم التحقق).
- [`lib/fuses.js`](../lib/fuses.js) — يعطّل فيوز Electron المدمج للتحقق
  من سلامة ASAR باستخدام `@electron/fuses`.

الوحدات الثلاث جميعها مكتوبة بلغة Node.js عادية، خفيفة الاعتماديات،
ومستقلة عن أي إطار عمل — فهي لا تفترض شيئًا عن *ماهية* التعديل الذي تجريه
على Claude Desktop، بل فقط أنك تعيد تعبئة `app.asar` وتعيد توقيع الحزمة
بعد ذلك.

```js
const { computeUnpackGlob, collectUnpackedRelativePaths } = require('./lib/unpack');
const { reSignMacApp } = require('./lib/macos');
const { disableAsarIntegrityFuse } = require('./lib/fuses');

// 1. Before extracting/patching, snapshot what's currently unpacked:
const unpackGlob = computeUnpackGlob(asarPath);

// 2. ...extract, patch, repack app.asar using `unpackGlob` for the `unpack` option...

// 3. Disable the integrity fuse and re-sign the whole bundle:
await disableAsarIntegrityFuse(appPath);
reSignMacApp(appPath);
```

---

## لماذا لا تُعد هذه علة في Claude Desktop

لتوضيح الأمر: يتصرف Claude Desktop بشكل صحيح هنا. فيوز سلامة ASAR الخاص
بـ Electron وتوقيع الشيفرة في macOS *مصمَّمان* لرفض أي حزمة تطبيق مُعدَّلة
— وهذا هو جوهر الغرض منهما بالكامل. يوجد هذا المستودع من أجل الأشخاص
الذين اختاروا عن قصد تعديل نسختهم المحلية الخاصة من Claude Desktop
(لأغراض إمكانية الوصول، أو الترجمة، أو أسباب شخصية مشروعة أخرى) ويريدون
أن يقوم تعديلهم أيضًا بتعطيل/تحديث الآليات التي قد تمنعه بشكل صحيح، بدلًا
من تركها في حالة معطوبة جزئيًا.

## المساهمة

المشكلات (Issues) وطلبات السحب (PRs) مرحّب بها. إذا واجهت نسخة مختلفة من
هذه العلة غير موثقة أعلاه، يُرجى تضمين:
- رسالة الخطأ الدقيقة (سجل تعطل من Console.app أو مخرجات الطرفية من
  تشغيل `Contents/MacOS/<AppName>` مباشرةً)
- ناتج `codesign -dv --verbose=4 /Applications/Claude.app`
- الأداة/التعديل الذي كنت تستخدمه عند حدوث العطل

## الترخيص

MIT
