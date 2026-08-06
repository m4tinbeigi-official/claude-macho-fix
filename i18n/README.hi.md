# Claude Desktop — "Malformed Mach-o file" / ASAR Integrity क्रैश फिक्स (macOS)

🌐 **इसे किसी अन्य भाषा में पढ़ें:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

**Claude Desktop for macOS** पर `app.asar` (Claude Desktop का पैक किया गया ऐप कोड) में बदलाव किए जाने के बाद होने वाली दो संबंधित क्रैश समस्याओं का फिक्स और स्पष्टीकरण — चाहे यह बदलाव किसी थर्ड-पार्टी पैच, प्लगइन, मैनुअल छेड़छाड़, या किसी भी ऐसी चीज़ से हुआ हो जो ऐप बंडल को फिर से पैक या एडिट करती है।

यह **किसी एक** पैचर या टूल के लिए विशिष्ट नहीं है। कोई भी प्रोजेक्ट जो Claude Desktop के `app.asar` को एक्सट्रैक्ट, एडिट, और रीपैक करता है, अगर वह दो macOS/Electron-विशिष्ट विवरणों को सही तरीके से हैंडल नहीं करता तो इनमें से एक या दोनों समस्याओं को ट्रिगर कर सकता है। यह रिपॉजिटरी दोनों मूल कारणों का दस्तावेज़ीकरण करती है और एक-कमांड रिपेयर स्क्रिप्ट प्रदान करती है।

---

## लक्षण 1 — Claude Code टैब शुरू नहीं होता

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

केवल **Claude Code टैब** फेल होता है। Claude Desktop का बाकी हिस्सा (चैट, आदि) ठीक तरह से काम करता है।

## लक्षण 2 — पूरा ऐप लॉन्च ही नहीं होता

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

कुछ भी नहीं खुलता — प्रोसेस लॉन्च होते ही तुरंत एबॉर्ट हो जाती है। आपको यह तभी दिखेगा जब आप Claude Desktop के executable को सीधे टर्मिनल से चलाते हैं (`/Applications/Claude.app/Contents/MacOS/Claude`); ऐप पर डबल-क्लिक करने पर यह चुपचाप खुलने में विफल हो जाता है।

---

## मूल कारण

### 1. एक नेटिव बाइनरी डिस्क पर अनपैक्ड रहने की बजाय `app.asar` के *अंदर* पैक हो गई

Electron ऐप्स कुछ फ़ाइलों — नेटिव मॉड्यूल (`*.node`), डायनामिक लाइब्रेरीज़ (`*.dylib`), और अन्य नेटिव हेल्पर बाइनरीज़ — को भौतिक रूप से डिस्क पर `app.asar` के बगल में, एक सहोदर `app.asar.unpacked/` डायरेक्टरी में अनपैक्ड रखते हैं। बाकी सब कुछ एक ही `app.asar` आर्काइव फ़ाइल के अंदर पैक होकर रहता है।

अगर कोई रीपैकिंग स्क्रिप्ट यह तय करने के लिए कि क्या अनपैक्ड रखना है, फ़ाइल एक्सटेंशन की एक **हार्डकोडेड** सूची का उपयोग करती है (एक सामान्य पैटर्न: `{*.node,*.dylib,spawn-helper}`), तो कोई भी नेटिव बाइनरी जो इससे मेल नहीं खाती — उदाहरण के लिए Claude Code टैब के लिए एक हेल्पर बाइनरी जो इनमें से किसी एक्सटेंशन के बिना शिप होती है — उसकी बजाय आर्काइव के *अंदर* बंडल हो जाती है। एक आर्काइव एंट्री एक वास्तविक, स्वतंत्र रूप से एक्ज़ीक्यूटेबल फ़ाइल नहीं होती: OS किसी दूसरी फ़ाइल के बीच में मौजूद बाइट रेंज को `exec()` नहीं कर सकता और उससे एक वैध प्रोग्राम प्राप्त नहीं कर सकता। जब Claude Desktop उस बाइनरी को स्पॉन करने की कोशिश करता है, तो OS बाइट्स का एक ऐसा हिस्सा पढ़ता है जो फ़ाइल-अलाइन्ड नहीं है और इसे एक करप्ट/अमान्य Mach-O के रूप में रिपोर्ट करता है — इसीलिए "Malformed Mach-o file" संदेश आता है।

**फिक्स:** अनपैक सूची को हार्डकोड न करें। कुछ भी छूने से पहले, मूल `app.asar` के बगल में जो पहले से ही अनपैक्ड है उससे इसे डायनामिक रूप से कंप्यूट करें, और रीपैकिंग के समय उसी सेट का उपयोग करें। एक तैयार-इस्तेमाल इम्प्लीमेंटेशन के लिए [`lib/unpack.js`](../lib/unpack.js) देखें, और रीपैकिंग के बाद यह सत्यापित करें कि कुछ भी गायब नहीं हुआ।

### 2. पुराने नेस्टेड सिग्नेचर हटाए बिना दोबारा साइन करना

`app.asar` के अंदर फ़ाइलों को बदलना, इसके साथ शिप होने वाले पहले से साइन किए गए सब-बंडल्स
(`Contents/Frameworks/*.framework`, `Contents/Frameworks/*.app` हेल्पर्स,
`Contents/Helpers/*`, एम्बेडेड XPC सर्विसेज़, आदि) के नेस्टेड कोड सिग्नेचर को अमान्य कर देता है — लेकिन उन पुराने सिग्नेचर को हटाता नहीं है। इनके ऊपर `codesign --force --deep --sign -` चलाने से बंडल एक असंगत स्थिति में रह सकता है:

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

*साइन* स्टेप स्वयं सफलता की रिपोर्ट करता है ("replacing existing signature") — विफलता केवल `--verify` पर सामने आती है, जिसे अगर आप स्पष्ट रूप से जाँच न करें तो चूकना आसान है।

**फिक्स:** पहले `codesign --remove-signature --deep` चलाकर हर नेस्टेड सिग्नेचर हटाएँ, *फिर* शुरू से साइन करें। देखें [`lib/macos.js`](../lib/macos.js)।

### 3. Electron का एम्बेडेड ASAR इंटीग्रिटी फ़्यूज़

यही वह कारण है जो लक्षण 2 (पूरा ऐप लॉन्च न होना) पैदा करता है। Electron में एक बिल्ड-टाइम "फ़्यूज़" होता है — `EnableEmbeddedAsarIntegrityValidation` — जो, जब सक्षम होता है, तो `app.asar` के अपेक्षित SHA-256 हैश को सीधे **Electron Framework बाइनरी** में बेक कर देता है
(macOS पर `Contents/Frameworks/Electron Framework.framework/Electron Framework` — *न कि* `Contents/MacOS/` में मुख्य ऐप executable, और *न ही* `Info.plist` में मिलने वाली कोई `ElectronAsarIntegrity` की — यह एक अलग, असंबंधित लीगेसी मैकेनिज़्म है जिसे कुछ बिल्ड टूल्स भी लिख देते हैं)।

एक बार `app.asar` पैच हो जाने पर, एम्बेडेड हैश अब मेल नहीं खाता, और Electron ग्रेसफुली डिग्रेड होने की बजाय लॉन्च के समय हार्ड-क्रैश हो जाता है।

उस एम्बेडेड हैश को हाथ से दोबारा कंप्यूट और पैच करना व्यावहारिक नहीं है — यह कई अन्य फ़्लैग्स के साथ एक विशिष्ट बाइनरी "फ़्यूज़ वायर" फ़ॉर्मैट का हिस्सा है। समर्थित फिक्स यह है कि Electron के अपने टूलिंग, [`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses), का उपयोग करके इस फ़्यूज़ को पूरी तरह से अक्षम कर दिया जाए:

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

यह Electron Framework बाइनरी को संशोधित करता है, जो इसके सिग्नेचर को अमान्य कर देता है — इसके बाद आपको पूरे बंडल को दोबारा साइन करना होगा (मूल कारण #2 का फिक्स इसे संभालता है)।

---

## त्वरित फिक्स — पहले से ही एक खराब इंस्टॉल है?

अगर आपको सिर्फ अपने मौजूदा `Claude.app` को ठीक करना है (आपको यह जानने की ज़रूरत नहीं है कि ऊपर बताए गए में से किसने आपको प्रभावित किया — यह दोनों को ठीक करता है):

### एक क्लिक (बिना टर्मिनल)

1. [यह रिपॉजिटरी डाउनलोड करें](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip) और उसे अनज़िप करें।
2. **`Fix Claude.command`** पर डबल-क्लिक करें।
3. एक टर्मिनल विंडो खुलती है, जो आपको हर स्टेप के ज़रिए ले जाती है, और पूरा होने पर आपके लिए Claude Desktop को फिर से लॉन्च करने का प्रस्ताव देती है।

macOS पहली बार यह चेतावनी दे सकता है कि फ़ाइल किसी अज्ञात डेवलपर की है — इसे एक बार बायपास करने के लिए राइट-क्लिक करें और **Open** चुनें।

### एक लाइन (टर्मिनल)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

या इसे क्लोन करके स्थानीय रूप से चलाएँ:

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

`repair.sh` सामान्य इंस्टॉल लोकेशन में `Claude.app` (या `Claude Beta.app`) को स्वतः पहचान लेता है, अगर वह चल रहा हो तो उसे बंद करता है, स्पष्ट पास/फेल आउटपुट के साथ हर रिपेयर स्टेप से गुज़रता है, परिणाम को सत्यापित करता है, और आपके लिए ऐप को फिर से लॉन्च करने का प्रस्ताव देता है। अगर आपका ऐप किसी असामान्य जगह पर स्थित है तो स्पष्ट रूप से एक पाथ पास करें:

```bash
./repair.sh "/path/to/Claude Beta.app"
```

`repair.sh` Claude Desktop की किसी भी वास्तविक कार्यक्षमता या सामग्री को **संशोधित नहीं** करता — यह केवल इंटीग्रिटी फ़्यूज़ को अक्षम करता है और बंडल को दोबारा साइन करता है। इसे तब भी चलाना सुरक्षित है जब आप निश्चित न हों कि आपको कौन सा लक्षण है, और इसे कई बार चलाना भी सुरक्षित है। अगर यह ऐप बंडल में नहीं लिख पाता, तो यह आपको इसे `sudo` के साथ फिर से चलाने के लिए कहेगा।

---

## अगर आप अपना खुद का पैचर बना रहे हैं

अगर आप एक ऐसा टूल लिख रहे हैं जो `app.asar` को पैच करता है (लोकलाइज़ेशन, थीमिंग, प्लगइन्स, या किसी और चीज़ के लिए), तो आप इन बग्स को अपने यूज़र्स तक पहुँचाने से शुरू में ही बच सकते हैं। इस रिपॉजिटरी में तैयार-इस्तेमाल, दस्तावेज़ीकृत मॉड्यूल शामिल हैं:

- [`lib/unpack.js`](../lib/unpack.js) — `@electron/asar` के `createPackageWithOptions` के लिए सही `unpack` ग्लोब को, जो पहले से अनपैक्ड है उससे डायनामिक रूप से कंप्यूट करता है। यह एक हार्डकोडेड एक्सटेंशन सूची का ड्रॉप-इन रिप्लेसमेंट है।
- [`lib/macos.js`](../lib/macos.js) — एक macOS ऐप बंडल को सही तरीके से दोबारा साइन करता है (पहले नेस्टेड सिग्नेचर हटाएँ, फिर शुरू से साइन करें, फिर सत्यापित करें)।
- [`lib/fuses.js`](../lib/fuses.js) — `@electron/fuses` का उपयोग करके Electron के एम्बेडेड ASAR इंटीग्रिटी फ़्यूज़ को अक्षम करता है।

ये तीनों सादे Node.js में हैं, कम डिपेंडेंसी वाले, और फ्रेमवर्क-एग्नॉस्टिक हैं — ये इस बारे में कोई धारणा नहीं बनाते कि आप Claude Desktop को *किस चीज़* के लिए पैच कर रहे हैं, सिर्फ यह कि आप `app.asar` को रीपैक कर रहे हैं और उसके बाद बंडल को दोबारा साइन कर रहे हैं।

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

## यह Claude Desktop का बग क्यों नहीं है

स्पष्ट करने के लिए: Claude Desktop यहाँ सही तरीके से व्यवहार कर रहा है। Electron का ASAR इंटीग्रिटी फ़्यूज़ और macOS कोड साइनिंग *जानबूझकर* एक संशोधित ऐप बंडल को अस्वीकार करने के लिए बनाए गए हैं — यही इनका पूरा उद्देश्य है। यह रिपॉजिटरी उन लोगों के लिए है जिन्होंने जानबूझकर Claude Desktop की अपनी स्थानीय कॉपी को पैच करने का फैसला किया है (एक्सेसिबिलिटी, लोकलाइज़ेशन, या अन्य वैध व्यक्तिगत कारणों से) और चाहते हैं कि उनका पैच उन मैकेनिज़्म को भी सही तरीके से अक्षम/अपडेट करे जो अन्यथा इसे रोक देंगे, बजाय इसके कि उन्हें आधे-टूटे हालत में छोड़ दिया जाए।

## योगदान (Contributing)

इश्यूज़ और PR का स्वागत है। अगर आपको इस बग का कोई ऐसा वेरिएंट मिलता है जो ऊपर कवर नहीं किया गया है, तो कृपया शामिल करें:
- सटीक एरर मैसेज (Console.app क्रैश लॉग या `Contents/MacOS/<AppName>` को सीधे चलाने से मिला टर्मिनल आउटपुट)
- `codesign -dv --verbose=4 /Applications/Claude.app`
- आप कौन सा टूल/पैच उपयोग कर रहे थे जब यह टूटा

## लाइसेंस

MIT
