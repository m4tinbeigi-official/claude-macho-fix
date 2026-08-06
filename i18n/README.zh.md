# Claude Desktop — "Malformed Mach-o file" / ASAR 完整性修复（macOS）

🌐 **切换语言:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

针对 **macOS 版 Claude Desktop** 上可能出现的两个相关崩溃问题的修复方案和说明。这两个问题会在 `app.asar`（Claude Desktop 打包的应用代码）被修改之后出现——无论是通过第三方补丁、插件、手动修改，还是任何其他会重新打包或编辑该应用包的操作。

这**不是**针对某一个特定补丁工具或程序的问题。任何提取、编辑并重新打包 Claude Desktop 的 `app.asar` 的项目，只要没有正确处理两个 macOS/Electron 特有的细节，都可能触发这两个问题中的一个或全部。本仓库记录了两个问题的根本原因，并提供了一键修复脚本。

---

## 症状 1 —— Claude Code 标签页无法启动

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

只有 **Claude Code 标签页**会失败。Claude Desktop 的其余部分（聊天等功能）都能正常工作。

## 症状 2 —— 整个应用无法启动

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

整个应用完全打不开——进程在启动时立即中止。只有当你在终端中直接运行 Claude Desktop 的可执行文件时（`/Applications/Claude.app/Contents/MacOS/Claude`）才能看到这条报错；直接双击应用图标只会静默地打开失败。

---

## 根本原因

### 1. 一个原生二进制文件被打包*进了* `app.asar`，而不是保持在磁盘上未打包状态

Electron 应用会把某些文件——原生模块（`*.node`）、动态库（`*.dylib`）以及其他原生辅助二进制文件——实际保持在磁盘上未打包状态，与 `app.asar` 放在同级的 `app.asar.unpacked/` 目录中。其余所有文件都打包在单一的 `app.asar` 归档文件内部。

如果重新打包脚本使用**硬编码**的文件扩展名列表（常见模式如 `{*.node,*.dylib,spawn-helper}`）来决定哪些文件应保持未打包状态，那么任何不匹配这个列表的原生二进制文件——例如 Claude Code 标签页所依赖、但没有使用这些扩展名的某个辅助二进制文件——就会被打包*进*归档内部。归档中的一个条目并不是一个真正独立可执行的文件：操作系统无法对另一个文件中间的某段字节范围执行 `exec()` 并得到一个有效的程序。当 Claude Desktop 尝试启动那个二进制文件时，操作系统读取到的是一段未按文件对齐的字节，于是报告其为损坏/无效的 Mach-O 文件——这就是 "Malformed Mach-o file" 报错的由来。

**修复方法：**不要硬编码未打包文件列表。在动手修改任何内容之前，先动态地从原始 `app.asar` 旁边*已经*存在的未打包文件计算出该列表，并在重新打包时使用同一份列表。可参考 [`lib/unpack.js`](../lib/unpack.js) 中的现成实现，并在重新打包后验证没有文件丢失。

### 2. 重新签名之前没有先剥离过期的嵌套签名

修改 `app.asar` 内部的文件会使随其一同发布的、已签名子包（`Contents/Frameworks/*.framework`、`Contents/Frameworks/*.app` 辅助程序、`Contents/Helpers/*`、内嵌的 XPC 服务等）的嵌套代码签名失效——但并不会移除这些过期的签名。此时如果直接在其上运行 `codesign --force --deep --sign -`，可能会让应用包处于不一致的状态：

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

*签名*这一步本身会报告成功（"replacing existing signature"）——只有在执行 `--verify` 时才会暴露出问题，如果你不特意去检查，很容易被忽略。

**修复方法：**先运行 `codesign --remove-signature --deep` 剥离所有嵌套签名，*然后*再从头重新签名。参见 [`lib/macos.js`](../lib/macos.js)。

### 3. Electron 内嵌的 ASAR 完整性熔断开关（fuse）

这是导致症状 2（整个应用无法启动）的原因。Electron 有一个构建期的"熔断开关"——`EnableEmbeddedAsarIntegrityValidation`——启用后，会将 `app.asar` 的预期 SHA-256 哈希值直接烘焙进 **Electron Framework 二进制文件**中（在 macOS 上是 `Contents/Frameworks/Electron Framework.framework/Electron Framework`——*不是* `Contents/MacOS/` 中的主应用可执行文件，也*不是* `Info.plist` 中可能出现的 `ElectronAsarIntegrity` 键，那是一些构建工具也会写入的、另一套独立且不相关的旧机制）。

一旦 `app.asar` 被修改，这个内嵌的哈希值就不再匹配，Electron 会在启动时直接硬崩溃，而不是优雅降级。

手动重新计算并修补那个内嵌哈希值并不现实——它是一种特定的二进制"熔断开关连线"格式的一部分，还牵涉到其他若干个标志位。官方支持的修复方法是使用 Electron 自己的工具 [`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses) 完全禁用该熔断开关：

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

这会修改 Electron Framework 二进制文件，使其签名失效——之后你必须对整个应用包重新签名（根本原因 #2 的修复方法可以处理这一步）。

---

## 快速修复 —— 已经有一个损坏的安装了？

如果你只是需要修复你手头已经损坏的 `Claude.app`（不需要知道自己遇到的是上述哪一种原因——这个方法两种都能修复）：

### 一键操作（无需终端）

1. [下载本仓库](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip) 并解压。
2. 双击 **`Fix Claude.command`**。
3. 会打开一个终端窗口，引导你完成每一步操作，并在完成后提示是否为你重新启动 Claude Desktop。

macOS 可能会在首次运行时警告该文件来自身份不明的开发者——右键点击该文件并选择**打开**即可绕过这一次性警告。

### 一行命令（终端）

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

或者克隆仓库并在本地运行：

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

`repair.sh` 会自动检测常见安装位置中的 `Claude.app`（或 `Claude Beta.app`），如果它正在运行会先将其退出，然后逐步执行每一个修复步骤并给出清晰的成功/失败提示，验证修复结果，并提示是否为你重新启动应用。如果你的应用安装在不常见的位置，可以显式传入路径：

```bash
./repair.sh "/path/to/Claude Beta.app"
```

`repair.sh` **不会**修改 Claude Desktop 的任何实际功能或内容——它只会禁用完整性熔断开关并重新签名应用包。即使你不确定自己遇到的是哪种症状，运行它也是安全的，多次运行同样安全。如果它无法写入应用包，会提示你使用 `sudo` 重新运行。

---

## 如果你正在编写自己的补丁工具

如果你正在编写一个用于修补 `app.asar` 的工具（用于本地化、主题、插件或其他任何目的），你可以从一开始就避免把这些问题带给你的用户。本仓库包含了可直接使用、附带文档的模块：

- [`lib/unpack.js`](../lib/unpack.js) —— 为 `@electron/asar` 的 `createPackageWithOptions` 动态计算正确的 `unpack` glob 模式，根据当前已经处于未打包状态的文件计算得出。可直接替换硬编码的扩展名列表。
- [`lib/macos.js`](../lib/macos.js) —— 正确地为 macOS 应用包重新签名（先剥离嵌套签名，再从头签名，然后验证）。
- [`lib/fuses.js`](../lib/fuses.js) —— 使用 `@electron/fuses` 禁用 Electron 内嵌的 ASAR 完整性熔断开关。

这三个模块都是纯 Node.js 编写、依赖极少、且与具体框架无关——它们不对你*要把* Claude Desktop 修补成什么样做任何假设，只关心你是在重新打包 `app.asar` 并在之后重新签名应用包这件事本身。

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

## 为什么这不是 Claude Desktop 的 bug

需要说明的是：Claude Desktop 在这里的行为是正确的。Electron 的 ASAR 完整性熔断开关和 macOS 代码签名机制*本来就是设计用来*拒绝一个被修改过的应用包的——这正是它们存在的意义。本仓库是为那些出于无障碍访问、本地化或其他合理的个人原因，主动选择修补自己本地那份 Claude Desktop 副本的人准备的，目的是让他们的补丁能够正确地禁用/更新那些原本会阻止补丁生效的机制，而不是让应用处于一种"修了一半"的破损状态。

## 贡献

欢迎提交 Issue 和 PR。如果你遇到了上面未涵盖的这个 bug 的其他变体，请附上以下信息：
- 完整的错误信息（Console.app 的崩溃日志，或直接运行 `Contents/MacOS/<AppName>` 时终端输出的内容）
- `codesign -dv --verbose=4 /Applications/Claude.app` 的输出
- 出问题时你使用的是哪个工具/补丁

## 许可证

MIT
