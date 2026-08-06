const { execFileSync } = require('child_process');

function reSignMacApp(appPath, execFile = execFileSync) {
    execFile('xattr', ['-cr', appPath], { stdio: 'pipe' });

    // Strip every nested code signature first. Patching files inside
    // app.asar invalidates the nested seals of already-signed sub-bundles
    // (Frameworks, Helper.app, XPCServices, etc.) without removing them —
    // a single `--force --deep --sign -` on top of stale nested signatures
    // can leave the bundle in an inconsistent state where `codesign
    // --verify` reports "nested code is modified or invalid" even though
    // the sign step itself reports success. Ignore failures here: some
    // items may not have had a signature to remove.
    try {
        execFile('codesign', ['--remove-signature', '--deep', appPath], { stdio: 'pipe' });
    } catch (e) {
        // non-fatal
    }

    execFile('codesign', [
        '--force',
        '--deep',
        '--sign',
        '-',
        appPath
    ], { stdio: 'pipe' });
    execFile('codesign', ['--verify', '--deep', '--strict', '--verbose=2', appPath], {
        stdio: 'pipe'
    });
}

module.exports = { reSignMacApp };
