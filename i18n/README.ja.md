# Claude Desktop — 「Malformed Mach-o file」/ ASAR整合性チェックのクラッシュ修正 (macOS)

🌐 **他の言語で読む:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

**Claude Desktop for macOS** で `app.asar`(Claude Desktopのパッケージ化されたアプリコード)が変更された後に発生しうる、関連する2つのクラッシュに対する修正と解説です。サードパーティのパッチ、プラグイン、手動での改変など、アプリバンドルを再パッケージまたは編集する原因が何であっても発生します。

これは特定のパッチャーやツールに固有の問題では**ありません**。Claude Desktopの`app.asar`を展開・編集・再パッケージするプロジェクトであれば、macOS/Electron特有の2つの詳細を正しく扱わない限り、どちらか一方または両方の問題を引き起こす可能性があります。このリポジトリでは両方の根本原因を解説し、ワンコマンドの修復スクリプトを提供します。

---

## 症状1 — Claude Codeタブが起動しない

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

失敗するのは**Claude Codeタブのみ**です。Claude Desktopの他の部分(チャットなど)は正常に動作します。

## 症状2 — アプリ全体が起動しない

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

何も起動しません。プロセスは起動直後に即座に中断します。この症状が見えるのは、Claude Desktopの実行ファイルをターミナルから直接実行した場合のみです(`/Applications/Claude.app/Contents/MacOS/Claude`)。アプリをダブルクリックした場合は、単に無言で起動に失敗します。

---

## 根本原因

### 1. ネイティブバイナリがディスク上に展開されたままにならず、`app.asar`の内部にパックされてしまう

Electronアプリは、ネイティブモジュール(`*.node`)、ダイナミックライブラリ(`*.dylib`)、その他のネイティブヘルパーバイナリといった特定のファイルを、`app.asar`と同じ階層にある兄弟ディレクトリ`app.asar.unpacked/`内に、物理的にディスク上へ展開したまま保持します。それ以外のものはすべて単一の`app.asar`アーカイブファイル内にパックされます。

再パッケージ用スクリプトが、展開したまま残すファイルを**ハードコードされた**拡張子リスト(よくあるパターン: `{*.node,*.dylib,spawn-helper}`)に基づいて決めている場合、それに一致しないネイティブバイナリ — 例えば、これらの拡張子を持たないClaude Codeタブ用のヘルパーバイナリなど — はアーカイブの*内部*にバンドルされてしまいます。アーカイブのエントリは、実際に独立して実行可能なファイルではありません。OSは他のファイルの中間にあるバイト範囲を`exec()`して有効なプログラムを得ることはできません。Claude Desktopがそのバイナリを起動しようとすると、OSはファイル境界に沿っていないバイト列を読み込み、それを壊れた/無効なMach-Oとして報告します。これが「Malformed Mach-o file」の原因です。

**修正方法:** 展開対象リストをハードコードしないことです。何かを変更する前に、元の`app.asar`の隣に*既に*展開されているものから動的にリストを計算し、再パッケージ時にも同じ集合を使用します。すぐに使える実装は[`lib/unpack.js`](../lib/unpack.js)を参照してください。再パッケージ後には、何も欠落していないことを確認してください。

### 2. 古いネストされた署名を取り除かずに再署名してしまう

`app.asar`内のファイルを変更すると、それに付随してすでに署名済みのサブバンドル(`Contents/Frameworks/*.framework`、`Contents/Frameworks/*.app`ヘルパー、`Contents/Helpers/*`、埋め込みXPCサービスなど)のネストされたコード署名が無効になりますが、それらの古い署名自体は削除されません。この状態の上に`codesign --force --deep --sign -`を実行すると、バンドルが不整合な状態のままになることがあります。

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

*署名*ステップ自体は成功したと報告されます(「replacing existing signature」)。失敗は`--verify`を実行して初めて表面化するため、明示的に確認しない限り見落としがちです。

**修正方法:** まず`codesign --remove-signature --deep`を実行してネストされた署名をすべて取り除いてから、改めて署名します。詳細は[`lib/macos.js`](../lib/macos.js)を参照してください。

### 3. ElectronのASAR整合性検証の埋め込みフューズ

これが症状2(アプリ全体が起動しない)の原因です。Electronにはビルド時の「フューズ」(fuse)である`EnableEmbeddedAsarIntegrityValidation`があり、これが有効な場合、`app.asar`の期待されるSHA-256ハッシュが**Electron Frameworkバイナリ**(macOSでは`Contents/Frameworks/Electron Framework.framework/Electron Framework` — `Contents/MacOS/`内のメイン実行ファイルではなく、また`Info.plist`内に見つかることがある`ElectronAsarIntegrity`キーとも別物です。こちらは一部のビルドツールがたまたま書き込む、無関係のレガシーな仕組みです)に直接埋め込まれます。

`app.asar`がパッチされると、埋め込まれたハッシュが一致しなくなり、Electronは緩やかに機能を制限するのではなく、起動時にハードクラッシュします。

この埋め込みハッシュを手動で再計算してパッチすることは現実的ではありません。これは他のいくつかのフラグとともに、特定のバイナリの「フューズワイヤ」形式の一部だからです。サポートされている修正方法は、Electron公式ツールである[`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses)を使って、このフューズを完全に無効化することです。

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

これによりElectron Frameworkバイナリが変更され、署名が無効になります。そのため、この後にバンドル全体を再署名する必要があります(根本原因2の修正方法で対応します)。

---

## 手っ取り早い修正 — すでに壊れたインストールがある場合

すでに手元にある壊れた`Claude.app`を修復したいだけであれば(上記のどちらの原因に当てはまるか把握している必要はありません。この方法は両方に対応します):

### ワンクリック(ターミナル不要)

1. [このリポジトリをダウンロード](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip)して解凍します。
2. **`Fix Claude.command`**をダブルクリックします。
3. ターミナルウィンドウが開き、各手順を案内してくれます。完了すると、Claude Desktopを再起動するかどうかを尋ねられます。

macOSは初回、「開発元が未確認」という警告を表示する場合があります。その場合は右クリックして**開く**を選択すれば、その回だけ回避できます。

### ワンライン(ターミナル)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

またはクローンしてローカルで実行することもできます。

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

`repair.sh`は、通常のインストール場所にある`Claude.app`(または`Claude Beta.app`)を自動検出し、実行中であれば終了させ、明確な成功/失敗の表示とともにすべての修復手順を実行し、結果を検証したうえで、アプリを再起動するかどうかを尋ねます。アプリが特殊な場所にある場合は、パスを明示的に指定してください。

```bash
./repair.sh "/path/to/Claude Beta.app"
```

`repair.sh`はClaude Desktopの実際の機能やコンテンツを一切変更**しません**。整合性フューズを無効化し、バンドルを再署名するだけです。どちらの症状に該当するか分からなくても安全に実行でき、何度実行しても問題ありません。アプリバンドルへの書き込み権限がない場合は、`sudo`を付けて再実行するよう案内が表示されます。

---

## 自作のパッチャーを作っている場合

ローカライズ、テーマ、プラグインなど、何らかの目的で`app.asar`にパッチを当てるツールを作成している場合、これらのバグをユーザーに送り届けてしまう事態はあらかじめ避けられます。このリポジトリには、すぐに使えるドキュメント付きモジュールが含まれています。

- [`lib/unpack.js`](../lib/unpack.js) — `@electron/asar`の`createPackageWithOptions`向けに、正しい`unpack`用globパターンを、既に展開済みのものから動的に計算します。ハードコードされた拡張子リストの代わりにそのまま差し替えて使えます。
- [`lib/macos.js`](../lib/macos.js) — macOSアプリバンドルを正しく再署名します(まずネストされた署名を取り除き、次にゼロから署名し、最後に検証します)。
- [`lib/fuses.js`](../lib/fuses.js) — `@electron/fuses`を使って、Electronの埋め込みASAR整合性フューズを無効化します。

これら3つはすべてプレーンなNode.jsで書かれており、依存関係が少なく、フレームワークに依存しません。Claude Desktopを*何のために*パッチしているかについては一切の前提を置かず、`app.asar`を再パッケージし、その後バンドルを再署名するという点にのみ依拠しています。

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

## これがClaude Desktopのバグではない理由

念のため明確にしておくと、Claude Desktopはここで正しく動作しています。ElectronのASAR整合性フューズとmacOSのコード署名は、変更されたアプリバンドルを拒否することが*本来の目的*です。それこそがこれらの仕組みの存在意義です。このリポジトリは、自分のローカル環境にあるClaude Desktopのコピーに意図的にパッチを当てることを選んだ人たち(アクセシビリティ、ローカライズ、その他正当な個人的理由のため)のために存在し、パッチが本来ブロックするはずの仕組みを、中途半端に壊れた状態のまま放置するのではなく、正しく無効化・更新できるようにすることを目的としています。

## コントリビュート

Issueおよびプルリクエストを歓迎します。上記でカバーされていない亜種のバグに遭遇した場合は、次の情報を含めてください。

- 正確なエラーメッセージ(Console.appのクラッシュログ、または`Contents/MacOS/<AppName>`を直接実行したときのターミナル出力)
- `codesign -dv --verbose=4 /Applications/Claude.app`の出力
- 問題が発生した際に使用していたツール/パッチ

## ライセンス

MIT
