const { flipFuses, FuseVersion, FuseV1Options } = require('@electron/fuses');

// Electron's "Embedded ASAR Integrity Validation" fuse hashes the whole
// app.asar file and bakes the expected hash into the fuse wire embedded in
// the Electron Framework binary at build time (on macOS specifically:
// Contents/Frameworks/Electron Framework.framework/Electron Framework — NOT
// the main app executable in Contents/MacOS). This is separate from, and
// unrelated to, any `ElectronAsarIntegrity` key some Info.plist files also
// carry (a different, legacy mechanism). Once app.asar is patched, the
// embedded fuse hash no longer matches the file on disk, and Electron
// hard-crashes at launch with:
//   [FATAL:...asar_util.cc] Integrity check failed for asar archive (X vs Y)
//
// The embedded hash isn't practical to recompute and patch by hand, so the
// supported fix is to flip this fuse off entirely via Electron's own
// tooling. Pass the .app bundle path directly — @electron/fuses resolves
// the correct fuse-bearing binary internally (see its `pathToFuseFile`).
async function disableAsarIntegrityFuse(appPath) {
    await flipFuses(appPath, {
        version: FuseVersion.V1,
        [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: false,
        // We re-sign the whole bundle ourselves right after this, via
        // reSignMacApp (which strips all stale nested signatures first) —
        // no need for flipFuses' own built-in ad-hoc re-sign here, that
        // would just sign twice.
        resetAdHocDarwinSignature: false
    });
}

module.exports = { disableAsarIntegrityFuse };
