# Claude Desktop — رفع خطای «Malformed Mach-o file» / خطای یکپارچگی ASAR (macOS)

🌐 **این فایل را به زبان دیگری بخوانید:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

راه‌حل و توضیحی برای دو خطای مرتبط که ممکن است روی **Claude Desktop برای
macOS** پس از تغییر `app.asar` (کد بسته‌بندی‌شده‌ی برنامه‌ی Claude Desktop) رخ
دهند — چه این تغییر توسط یک پچ شخص ثالث، یک افزونه، دستکاری دستی، یا هر چیز
دیگری که app bundle را دوباره بسته‌بندی یا ویرایش می‌کند، ایجاد شده باشد.

این مشکل مختص هیچ پچر یا ابزار خاصی **نیست**. هر پروژه‌ای که `app.asar` مربوط
به Claude Desktop را استخراج، ویرایش و دوباره بسته‌بندی کند، در صورتی که دو
جزئیات مخصوص macOS/Electron را درست مدیریت نکند، می‌تواند باعث بروز یکی یا هر
دوی این مشکلات شود. این مخزن هر دو علت ریشه‌ای را مستند کرده و یک اسکریپت
تعمیر تک‌دستوری ارائه می‌دهد.

---

## نشانه‌ی ۱ — تب Claude Code اجرا نمی‌شود

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

فقط **تب Claude Code** با خطا مواجه می‌شود. بقیه‌ی بخش‌های Claude Desktop
(چت و غیره) به‌درستی کار می‌کنند.

## نشانه‌ی ۲ — کل برنامه اجرا نمی‌شود

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

هیچ‌چیزی اصلاً باز نمی‌شود — پردازه بلافاصله هنگام اجرا متوقف می‌شود. این
خطا را فقط زمانی می‌بینید که فایل اجرایی Claude Desktop را مستقیماً از
ترمینال اجرا کنید
(`/Applications/Claude.app/Contents/MacOS/Claude`)؛ دابل‌کلیک روی برنامه فقط
به‌صورت بی‌صدا با شکست مواجه می‌شود و باز نمی‌شود.

---

## علت‌های ریشه‌ای

### ۱. یک باینری native به‌جای باقی‌ماندن روی دیسک، داخل `app.asar` بسته‌بندی شده است

برنامه‌های Electron برخی فایل‌ها — ماژول‌های native (`*.node`)، کتابخانه‌های
داینامیک (`*.dylib`)، و هر باینری کمکی native دیگری — را به‌صورت فیزیکی و
باز (unpacked) روی دیسک، در کنار `app.asar`، درون یک پوشه‌ی خواهر به نام
`app.asar.unpacked/` نگه می‌دارند. بقیه‌ی فایل‌ها درون همان یک فایل آرشیو
`app.asar` بسته‌بندی می‌شوند.

اگر یک اسکریپت بازبسته‌بندی (repacking) با استفاده از یک لیست **ثابت و
از‌پیش‌تعیین‌شده** از پسوندهای فایل تصمیم بگیرد چه چیزی باز (unpacked) بماند
(یک الگوی رایج: `{*.node,*.dylib,spawn-helper}`)، هر باینری native که با این
الگو مطابقت نداشته باشد — برای مثال یک باینری کمکی مربوط به تب Claude Code که
بدون یکی از این پسوندها عرضه می‌شود — به‌جای آن، داخل آرشیو بسته‌بندی می‌شود.
یک آیتم درون آرشیو، یک فایل واقعی و مستقل قابل‌اجرا نیست: سیستم‌عامل نمی‌تواند
یک بازه‌ی بایتی وسط یک فایل دیگر را `exec()` کند و از آن یک برنامه‌ی معتبر
بیرون بکشد. وقتی Claude Desktop سعی می‌کند آن باینری را اجرا کند، سیستم‌عامل
یک تکه بایت غیرهم‌تراز با مرز فایل را می‌خواند و آن را به‌عنوان یک فایل
Mach-O خراب/نامعتبر گزارش می‌دهد — از همین‌جا پیام «Malformed Mach-o file»
می‌آید.

**راه‌حل:** لیست unpack را ثابت و از‌پیش‌تعیین‌شده ننویسید. آن را به‌صورت
پویا از روی چیزهایی که پیش از هر تغییری، از قبل کنار `app.asar` اصلی باز
(unpacked) هستند محاسبه کنید، و همان مجموعه را هنگام بازبسته‌بندی استفاده
کنید. برای یک پیاده‌سازی آماده‌ی استفاده، فایل [`lib/unpack.js`](../lib/unpack.js)
را ببینید، و پس از بازبسته‌بندی حتماً بررسی کنید چیزی گم نشده باشد.

### ۲. امضای مجدد بدون حذف امضاهای تودرتوی قدیمی (stale) پیش از آن

تغییر فایل‌های داخل `app.asar` امضاهای کد تودرتوی (nested code signatures)
زیر-باندل‌هایی که از قبل امضا شده‌اند و همراه آن عرضه می‌شوند
(`Contents/Frameworks/*.framework`، برنامه‌های کمکی
`Contents/Frameworks/*.app`، `Contents/Helpers/*`، سرویس‌های XPC داخلی و
غیره) را باطل می‌کند — اما آن‌ها را حذف نمی‌کند. اجرای
`codesign --force --deep --sign -` روی این امضاهای قدیمی می‌تواند بسته را
در وضعیتی ناسازگار رها کند:

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

خودِ مرحله‌ی *امضا کردن* موفقیت را گزارش می‌دهد («replacing existing
signature») — و شکست فقط هنگام `--verify` نمایان می‌شود، که اگر آن را به‌طور
صریح بررسی نکنید، به‌راحتی از چشم می‌افتد.

**راه‌حل:** ابتدا `codesign --remove-signature --deep` را اجرا کنید تا هر
امضای تودرتو حذف شود، *سپس* از نو امضا کنید. فایل
[`lib/macos.js`](../lib/macos.js) را ببینید.

### ۳. فیوز یکپارچگی ASAR توکار Electron

این همان علتی است که باعث نشانه‌ی ۲ می‌شود (کل برنامه اجرا نمی‌شود). Electron
یک «فیوز» (fuse) در زمان build دارد —
`EnableEmbeddedAsarIntegrityValidation` — که وقتی فعال باشد، هش SHA-256
مورد انتظار `app.asar` را مستقیماً درون **باینری Electron Framework** جاسازی
می‌کند
(`Contents/Frameworks/Electron Framework.framework/Electron Framework` در
macOS — *نه* فایل اجرایی اصلی برنامه در `Contents/MacOS/`، و *نه* هیچ کلید
`ElectronAsarIntegrity`ای که ممکن است در `Info.plist` پیدا کنید، که یک سازوکار
قدیمی و بی‌ربط جداگانه است و برخی ابزارهای build هم آن را می‌نویسند).

پس از پچ شدن `app.asar`، هش جاسازی‌شده دیگر مطابقت ندارد، و Electron به‌جای
تنزل تدریجی عملکرد (graceful degradation)، هنگام اجرا کاملاً کرش می‌کند.

محاسبه و پچ کردن دستی آن هش جاسازی‌شده عملی نیست — این هش بخشی از یک قالب
باینری خاص به نام «fuse wire» است که در کنار چند پرچم دیگر قرار دارد.
راه‌حل پشتیبانی‌شده این است که این فیوز را کاملاً با استفاده از ابزار خودِ
Electron یعنی [`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses)
غیرفعال کنید:

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

این کار باینری Electron Framework را تغییر می‌دهد که امضای آن را باطل
می‌کند — پس از آن باید کل بسته را دوباره امضا کنید (راه‌حل علت ریشه‌ای شماره
۲ این کار را انجام می‌دهد).

---

## راه‌حل سریع — نصب خراب‌شده دارید؟

اگر فقط می‌خواهید `Claude.app` خراب‌شده‌ی فعلی خود را تعمیر کنید (نیازی
نیست بدانید کدام‌یک از موارد بالا مشکل شماست — این روش هر دو را برطرف
می‌کند):

### تک‌کلیک (بدون ترمینال)

۱. [این مخزن را دانلود کنید](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip)
   و از حالت فشرده خارج کنید.
۲. روی **`Fix Claude.command`** دابل‌کلیک کنید.
۳. یک پنجره‌ی ترمینال باز می‌شود، شما را مرحله‌به‌مرحله راهنمایی می‌کند، و در
   پایان پیشنهاد می‌دهد که Claude Desktop را برایتان دوباره اجرا کند.

ممکن است macOS بار اول هشدار دهد که این فایل از یک توسعه‌دهنده‌ی ناشناس
است — برای دور زدن این هشدار (فقط یک‌بار)، روی فایل راست‌کلیک کرده و
**Open** را انتخاب کنید.

### تک‌خط (ترمینال)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

یا این‌که مخزن را کلون کرده و به‌صورت محلی اجرا کنید:

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

`repair.sh` به‌صورت خودکار `Claude.app` (یا `Claude Beta.app`) را در محل‌های
رایج نصب پیدا می‌کند، در صورت در حال اجرا بودن آن را می‌بندد، تمام مراحل
تعمیر را با خروجی واضح موفق/ناموفق طی می‌کند، نتیجه را بررسی می‌کند، و در
پایان پیشنهاد می‌دهد برنامه را برایتان دوباره اجرا کند. اگر برنامه‌ی شما در
مسیر غیرمعمولی قرار دارد، مسیر را به‌صورت صریح وارد کنید:

```bash
./repair.sh "/path/to/Claude Beta.app"
```

`repair.sh` هیچ‌کدام از عملکردها یا محتوای واقعی Claude Desktop را تغییر
**نمی‌دهد** — فقط فیوز یکپارچگی را غیرفعال کرده و بسته را دوباره امضا
می‌کند. اجرای آن حتی اگر مطمئن نیستید کدام نشانه را دارید بی‌خطر است، و
اجرای چندباره‌ی آن هم بی‌خطر است. اگر امکان نوشتن روی app bundle وجود نداشته
باشد، به شما می‌گوید که آن را با `sudo` دوباره اجرا کنید.

---

## اگر در حال ساخت پچر خودتان هستید

اگر در حال نوشتن ابزاری هستید که `app.asar` را پچ می‌کند (برای بومی‌سازی،
تم‌بندی، افزونه، یا هر منظور دیگری)، می‌توانید از همان ابتدا از عرضه‌ی این
باگ‌ها به کاربرانتان جلوگیری کنید. این مخزن شامل ماژول‌های آماده و مستندسازی‌شده
است:

- [`lib/unpack.js`](../lib/unpack.js) — الگوی (glob) صحیح `unpack` را برای
  گزینه‌ی `createPackageWithOptions` در `@electron/asar`، به‌صورت پویا و از
  روی چیزهایی که از قبل باز (unpacked) هستند، محاسبه می‌کند. جایگزینی آماده
  برای یک لیست ثابت از پسوندها.
- [`lib/macos.js`](../lib/macos.js) — یک app bundle در macOS را به‌درستی
  دوباره امضا می‌کند (ابتدا حذف امضاهای تودرتو، سپس امضای از نو، سپس بررسی).
- [`lib/fuses.js`](../lib/fuses.js) — فیوز یکپارچگی جاسازی‌شده‌ی ASAR در
  Electron را با استفاده از `@electron/fuses` غیرفعال می‌کند.

هر سه‌ی این‌ها Node.js خالص، با وابستگی کم، و مستقل از فریم‌ورک هستند —
هیچ فرضی درباره‌ی *اینکه* شما Claude Desktop را برای چه کاری پچ می‌کنید
ندارند، فقط فرض می‌کنند شما در حال بازبسته‌بندی `app.asar` و امضای مجدد
بسته پس از آن هستید.

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

## چرا این یک باگ در Claude Desktop نیست

برای شفاف‌سازی: رفتار Claude Desktop در این‌جا کاملاً درست است. فیوز
یکپارچگی ASAR در Electron و امضای کد در macOS *قرار است* یک app bundle
تغییریافته را رد کنند — کل هدف وجودشان همین است. این مخزن برای کسانی وجود
دارد که آگاهانه تصمیم گرفته‌اند نسخه‌ی محلی خودشان از Claude Desktop را پچ
کنند (به دلایل دسترسی‌پذیری، بومی‌سازی، یا سایر دلایل شخصی مشروع) و
می‌خواهند پچ آن‌ها، سازوکارهایی را هم که در غیر این صورت جلوی آن را می‌گیرند
به‌درستی غیرفعال/به‌روزرسانی کند، به‌جای اینکه آن‌ها را در وضعیتی نیمه‌خراب
رها کند.

## مشارکت

از issue و pull request استقبال می‌شود. اگر با نوعی از این باگ مواجه شدید که
در بالا پوشش داده نشده، لطفاً موارد زیر را ضمیمه کنید:
- پیام دقیق خطا (گزارش کرش از Console.app یا خروجی ترمینال از اجرای مستقیم
  `Contents/MacOS/<AppName>`)
- خروجی `codesign -dv --verbose=4 /Applications/Claude.app`
- اینکه هنگام بروز مشکل، از چه ابزار/پچی استفاده می‌کردید

## مجوز

MIT
</content>
