# Claude Desktop — "Malformed Mach-o file" / ASAR Integrity Fix (macOS)

A fix and explanation for two related crashes that can happen on **Claude
Desktop for macOS** after `app.asar` (Claude Desktop's packaged app code) has
been modified — whether by a third-party patch, a plugin, manual tinkering,
or anything else that repacks or edits the app bundle.

This is **not** specific to any one patcher or tool. Any project that
extracts, edits, and repacks Claude Desktop's `app.asar` can trigger either
or both of these issues if it doesn't handle two macOS/Electron-specific
details correctly. This repo documents both root causes and ships a
one-command repair script.

---

## Symptom 1 — Claude Code tab won't start

<img src="assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

Only the **Claude Code tab** fails. The rest of Claude Desktop (chat, etc.)
works fine.

## Symptom 2 — The whole app won't launch

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

Nothing opens at all — the process aborts immediately on launch. You'll only
see this if you run Claude Desktop's executable directly from a terminal
(`/Applications/Claude.app/Contents/MacOS/Claude`); double-clicking the app
just silently fails to open.

---

## Root causes

### 1. A native binary got packed *into* `app.asar` instead of staying unpacked on disk

Electron apps keep certain files — native modules (`*.node`), dynamic
libraries (`*.dylib`), and any other native helper binaries — physically
unpacked on disk next to `app.asar`, in a sibling `app.asar.unpacked/`
directory. Everything else lives packed inside the single `app.asar` archive
file.

If a repacking script decides what to keep unpacked using a **hardcoded**
list of file extensions (a common pattern: `{*.node,*.dylib,spawn-helper}`),
any native binary that doesn't match — for example a helper binary for the
Claude Code tab that ships without one of those extensions — gets bundled
*inside* the archive instead. An archive entry is not a real, independently
executable file: the OS can't `exec()` a byte range in the middle of another
file and get a valid program out of it. When Claude Desktop tries to spawn
that binary, the OS reads a non-file-aligned chunk of bytes and reports it as
a corrupt/invalid Mach-O — hence "Malformed Mach-o file".

**Fix:** don't hardcode the unpack list. Compute it dynamically from
whatever is *already* unpacked next to the original `app.asar` before you
touch anything, and use that same set when repacking. See
[`lib/unpack.js`](lib/unpack.js) for a drop-in implementation, and verify
after repacking that nothing went missing.

### 2. Re-signing without stripping stale nested signatures first

Modifying files inside `app.asar` invalidates the nested code signatures of
already-signed sub-bundles that ship alongside it
(`Contents/Frameworks/*.framework`, `Contents/Frameworks/*.app` helpers,
`Contents/Helpers/*`, embedded XPC services, etc.) — but doesn't remove those
stale signatures. Running `codesign --force --deep --sign -` on top of them
can leave the bundle in an inconsistent state:

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

The *sign* step itself reports success ("replacing existing signature") —
the failure only shows up on `--verify`, which is easy to miss if you don't
check for it explicitly.

**Fix:** run `codesign --remove-signature --deep` first to strip every
nested signature, *then* sign from scratch. See
[`lib/macos.js`](lib/macos.js).

### 3. Electron's embedded ASAR integrity fuse

This is the one that causes Symptom 2 (whole app won't launch). Electron has
a build-time "fuse" — `EnableEmbeddedAsarIntegrityValidation` — that, when
enabled, bakes the expected SHA-256 hash of `app.asar` directly into the
**Electron Framework binary**
(`Contents/Frameworks/Electron Framework.framework/Electron Framework` on
macOS — *not* the main app executable in `Contents/MacOS/`, and *not* any
`ElectronAsarIntegrity` key you might find in `Info.plist`, which is a
separate, unrelated legacy mechanism some build tools also happen to write).

Once `app.asar` is patched, the embedded hash no longer matches, and
Electron hard-crashes at launch rather than degrading gracefully.

Recomputing and patching that embedded hash by hand isn't practical — it's
part of a specific binary "fuse wire" format alongside several other flags.
The supported fix is to disable the fuse entirely using Electron's own
tooling, [`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses):

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

This modifies the Electron Framework binary, which invalidates its
signature — you must re-sign the whole bundle afterward (root cause #2's fix
handles this).

---

## Quick fix — already have a broken install?

If you just need to repair the `Claude.app` you already have (you don't need
to know which of the above hit you — this fixes both):

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

Or clone and run it locally:

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

By default it targets `/Applications/Claude.app`. Pass a different path as
an argument if yours lives elsewhere:

```bash
./repair.sh "/Applications/Claude Beta.app"
```

`repair.sh` does **not** modify any of Claude Desktop's actual functionality
or content — it only disables the integrity fuse and re-signs the bundle.
It's safe to run even if you're not sure which symptom you have, and safe to
run multiple times.

---

## If you're building your own patcher

If you're writing a tool that patches `app.asar` (for localization, theming,
plugins, or anything else), you can avoid shipping these bugs to your users
in the first place. This repo includes ready-to-use, documented modules:

- [`lib/unpack.js`](lib/unpack.js) — computes the correct `unpack` glob for
  `@electron/asar`'s `createPackageWithOptions`, dynamically, from whatever
  is already unpacked. Drop-in replacement for a hardcoded extension list.
- [`lib/macos.js`](lib/macos.js) — re-signs a macOS app bundle correctly
  (strip nested signatures first, then sign from scratch, then verify).
- [`lib/fuses.js`](lib/fuses.js) — disables Electron's embedded ASAR
  integrity fuse using `@electron/fuses`.

All three are plain Node.js, dependency-light, and framework-agnostic — they
don't assume anything about *what* you're patching Claude Desktop to do,
only that you're repacking `app.asar` and re-signing the bundle afterward.

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

## Why this isn't a Claude Desktop bug

To be clear: Claude Desktop is behaving correctly here. Electron's ASAR
integrity fuse and macOS code signing are *supposed* to reject a modified
app bundle — that's the whole point of them. This repo exists for people who
have deliberately chosen to patch their own local copy of Claude Desktop
(for accessibility, localization, or other legitimate personal reasons) and
want their patch to also correctly disable/update the mechanisms that would
otherwise block it, rather than leaving them half-broken.

## Contributing

Issues and PRs welcome. If you hit a variant of this bug that isn't covered
above, please include:
- The exact error message (Console.app crash log or terminal output from
  running `Contents/MacOS/<AppName>` directly)
- `codesign -dv --verbose=4 /Applications/Claude.app`
- What tool/patch you were using when it broke

## License

MIT
