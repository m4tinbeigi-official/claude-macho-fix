const { computeUnpackGlob, collectUnpackedRelativePaths } = require('./unpack');
const { reSignMacApp } = require('./macos');
const { disableAsarIntegrityFuse } = require('./fuses');

module.exports = {
    computeUnpackGlob,
    collectUnpackedRelativePaths,
    reSignMacApp,
    disableAsarIntegrityFuse
};
