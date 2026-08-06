# Claude Desktop — Fix für „Malformed Mach-o file" / ASAR-Integritätsfehler (macOS)

🌐 **Diese Datei in einer anderen Sprache lesen:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

Ein Fix samt Erklärung für zwei verwandte Abstürze, die auf **Claude
Desktop für macOS** auftreten können, nachdem `app.asar` (der gepackte
App-Code von Claude Desktop) verändert wurde — egal ob durch einen
Drittanbieter-Patch, ein Plugin, manuelles Herumbasteln oder irgendetwas
anderes, das das App-Bundle neu packt oder bearbeitet.

Dies ist **nicht** spezifisch für einen bestimmten Patcher oder ein
bestimmtes Tool. Jedes Projekt, das die `app.asar` von Claude Desktop
extrahiert, bearbeitet und neu packt, kann eines oder beide dieser Probleme
auslösen, wenn es zwei macOS-/Electron-spezifische Details nicht korrekt
handhabt. Dieses Repo dokumentiert beide Grundursachen und liefert ein
Reparaturskript, das mit einem einzigen Befehl läuft.

---

## Symptom 1 — Der Claude-Code-Tab startet nicht

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

Nur der **Claude-Code-Tab** schlägt fehl. Der Rest von Claude Desktop (Chat
usw.) funktioniert einwandfrei.

## Symptom 2 — Die gesamte App startet nicht

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

Es öffnet sich überhaupt nichts — der Prozess bricht sofort beim Start ab.
Dieser Fehler ist nur sichtbar, wenn man die ausführbare Datei von Claude
Desktop direkt aus einem Terminal startet
(`/Applications/Claude.app/Contents/MacOS/Claude`); ein Doppelklick auf die
App scheitert einfach stillschweigend.

---

## Grundursachen

### 1. Eine native Binärdatei wurde *in* `app.asar` gepackt, statt entpackt auf der Festplatte zu bleiben

Electron-Apps halten bestimmte Dateien — native Module (`*.node`),
dynamische Bibliotheken (`*.dylib`) und andere native Hilfsprogramme —
physisch entpackt auf der Festplatte, neben `app.asar`, in einem
benachbarten Verzeichnis `app.asar.unpacked/`. Alles andere befindet sich
gepackt innerhalb der einzelnen Archivdatei `app.asar`.

Wenn ein Repacking-Skript anhand einer **fest codierten** Liste von
Dateiendungen entscheidet, was entpackt bleiben soll (ein gängiges Muster:
`{*.node,*.dylib,spawn-helper}`), landet jede native Binärdatei, die nicht
dazu passt — zum Beispiel eine Hilfsbinärdatei für den Claude-Code-Tab, die
ohne eine dieser Endungen ausgeliefert wird — stattdessen *innerhalb* des
Archivs. Ein Archiv-Eintrag ist keine echte, eigenständig ausführbare Datei:
Das Betriebssystem kann keinen Byte-Bereich mitten in einer anderen Datei
`exec()`-en und daraus ein gültiges Programm erhalten. Wenn Claude Desktop
versucht, diese Binärdatei zu starten, liest das Betriebssystem einen nicht
dateiausgerichteten Byte-Block und meldet ihn als beschädigte/ungültige
Mach-O-Datei — daher „Malformed Mach-o file".

**Fix:** Die Entpack-Liste nicht fest codieren. Sie stattdessen dynamisch
aus dem berechnen, was bereits *vor* jeder Änderung neben der ursprünglichen
`app.asar` entpackt vorliegt, und dieselbe Menge beim Neupacken verwenden.
Siehe [`lib/unpack.js`](../lib/unpack.js) für eine fertige Implementierung
zum direkten Einsetzen, und nach dem Neupacken überprüfen, dass nichts
fehlt.

### 2. Neusignieren, ohne vorher veraltete verschachtelte Signaturen zu entfernen

Das Ändern von Dateien innerhalb von `app.asar` macht die verschachtelten
Code-Signaturen bereits signierter Sub-Bundles ungültig, die zusammen mit
ihr ausgeliefert werden (`Contents/Frameworks/*.framework`,
`Contents/Frameworks/*.app`-Helfer, `Contents/Helpers/*`, eingebettete
XPC-Dienste usw.) — entfernt diese veralteten Signaturen aber nicht. Wird
danach `codesign --force --deep --sign -` ausgeführt, kann das Bundle in
einem inkonsistenten Zustand zurückbleiben:

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

Der *Signier*-Schritt selbst meldet Erfolg („replacing existing
signature") — der Fehler zeigt sich erst bei `--verify`, was leicht
übersehen wird, wenn man nicht explizit danach prüft.

**Fix:** Zuerst `codesign --remove-signature --deep` ausführen, um jede
verschachtelte Signatur zu entfernen, *dann* von Grund auf neu signieren.
Siehe [`lib/macos.js`](../lib/macos.js).

### 3. Electrons eingebettete ASAR-Integritäts-„Fuse"

Dies ist die Ursache für Symptom 2 (die gesamte App startet nicht).
Electron besitzt eine zur Build-Zeit gesetzte „Fuse" —
`EnableEmbeddedAsarIntegrityValidation` —, die, wenn aktiviert, den
erwarteten SHA-256-Hash von `app.asar` direkt in die **Electron-Framework-
Binärdatei** einbrennt
(`Contents/Frameworks/Electron Framework.framework/Electron Framework`
unter macOS — *nicht* die Haupt-Ausführungsdatei der App in
`Contents/MacOS/`, und *nicht* irgendein `ElectronAsarIntegrity`-Schlüssel,
den man eventuell in der `Info.plist` findet — das ist ein separater,
unabhängiger Legacy-Mechanismus, den manche Build-Tools zufällig ebenfalls
schreiben).

Sobald `app.asar` gepatcht ist, stimmt der eingebettete Hash nicht mehr
überein, und Electron stürzt beim Start hart ab, statt geordnet zu
degradieren.

Diesen eingebetteten Hash von Hand neu zu berechnen und zu patchen ist
nicht praktikabel — er ist Teil eines bestimmten Binärformats („Fuse
Wire") zusammen mit mehreren weiteren Flags. Der unterstützte Fix besteht
darin, die Fuse vollständig mit Electrons eigenem Tooling zu deaktivieren,
[`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses):

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

Dies verändert die Electron-Framework-Binärdatei, wodurch ihre Signatur
ungültig wird — danach muss das gesamte Bundle neu signiert werden (der
Fix zu Grundursache #2 übernimmt das).

---

## Schnelle Reparatur — schon eine defekte Installation?

Wenn nur die bereits vorhandene `Claude.app` repariert werden muss (es
muss nicht bekannt sein, welche der obigen Ursachen zutrifft — dies behebt
beide):

### Ein Klick (kein Terminal)

1. [Dieses Repo herunterladen](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip) und entpacken.
2. Doppelklick auf **`Fix Claude.command`**.
3. Ein Terminalfenster öffnet sich, führt Schritt für Schritt durch den
   Vorgang und bietet am Ende an, Claude Desktop für einen neu zu starten.

macOS warnt beim ersten Mal möglicherweise, dass die Datei von einem nicht
identifizierten Entwickler stammt — mit Rechtsklick auf die Datei und
**Öffnen** wählen, um das einmalig zu umgehen.

### Eine Zeile (Terminal)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

Oder lokal klonen und ausführen:

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

`repair.sh` erkennt automatisch `Claude.app` (oder `Claude Beta.app`) an
den üblichen Installationsorten, beendet sie, falls sie gerade läuft,
geht jeden Reparaturschritt mit klarer Erfolgs-/Fehler-Ausgabe durch,
überprüft das Ergebnis und bietet an, die App danach für einen neu zu
starten. Einen Pfad explizit übergeben, falls die eigene Installation an
einem ungewöhnlichen Ort liegt:

```bash
./repair.sh "/path/to/Claude Beta.app"
```

`repair.sh` verändert **keine** der tatsächlichen Funktionen oder Inhalte
von Claude Desktop — es deaktiviert lediglich die Integritäts-Fuse und
signiert das Bundle neu. Es ist sicher auszuführen, auch wenn unklar ist,
welches Symptom vorliegt, und sicher, es mehrfach auszuführen. Falls es
nicht in das App-Bundle schreiben kann, wird empfohlen, es erneut mit
`sudo` auszuführen.

---

## Für alle, die einen eigenen Patcher bauen

Wer ein Tool schreibt, das `app.asar` patcht (für Lokalisierung, Theming,
Plugins oder irgendetwas anderes), kann diese Fehler von vornherein
vermeiden. Dieses Repo enthält einsatzbereite, dokumentierte Module:

- [`lib/unpack.js`](../lib/unpack.js) — berechnet dynamisch das korrekte
  `unpack`-Glob-Muster für die `createPackageWithOptions`-Funktion von
  `@electron/asar`, ausgehend davon, was bereits entpackt vorliegt. Direkter
  Ersatz für eine fest codierte Liste von Dateiendungen.
- [`lib/macos.js`](../lib/macos.js) — signiert ein macOS-App-Bundle korrekt
  neu (zuerst verschachtelte Signaturen entfernen, dann von Grund auf neu
  signieren, dann verifizieren).
- [`lib/fuses.js`](../lib/fuses.js) — deaktiviert Electrons eingebettete
  ASAR-Integritäts-Fuse mittels `@electron/fuses`.

Alle drei sind reines Node.js, schlank in ihren Abhängigkeiten und
framework-agnostisch — sie treffen keine Annahmen darüber, *wozu* Claude
Desktop gepatcht wird, sondern nur, dass `app.asar` neu gepackt und das
Bundle danach neu signiert wird.

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

## Warum dies kein Fehler von Claude Desktop ist

Zur Klarstellung: Claude Desktop verhält sich hier korrekt. Electrons
ASAR-Integritäts-Fuse und die Code-Signierung von macOS sollen ein
verändertes App-Bundle *absichtlich* zurückweisen — das ist genau ihr
Zweck. Dieses Repo existiert für Menschen, die bewusst entschieden haben,
ihre eigene lokale Kopie von Claude Desktop zu patchen (aus Gründen der
Barrierefreiheit, Lokalisierung oder anderen legitimen persönlichen
Gründen), und die möchten, dass ihr Patch auch die Mechanismen, die ihn
sonst blockieren würden, korrekt deaktiviert bzw. aktualisiert, statt sie
halb kaputt zurückzulassen.

## Mitwirken

Issues und Pull Requests sind willkommen. Wer eine Variante dieses Fehlers
antrifft, die oben nicht abgedeckt ist, sollte bitte Folgendes beilegen:
- Die genaue Fehlermeldung (Absturzprotokoll aus Console.app oder
  Terminal-Ausgabe beim direkten Ausführen von `Contents/MacOS/<AppName>`)
- `codesign -dv --verbose=4 /Applications/Claude.app`
- Welches Tool bzw. welcher Patch verwendet wurde, als der Fehler auftrat

## Lizenz

MIT
