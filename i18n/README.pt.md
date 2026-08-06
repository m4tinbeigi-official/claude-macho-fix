# Claude Desktop — Correção para "Malformed Mach-o file" / Integridade do ASAR (macOS)

🌐 **Leia isto em outro idioma:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

Uma correção e explicação para dois travamentos relacionados que podem ocorrer no **Claude
Desktop para macOS** depois que o `app.asar` (o código empacotado do Claude Desktop) foi
modificado — seja por um patch de terceiros, um plugin, alterações manuais,
ou qualquer outra coisa que reempacote ou edite o bundle do aplicativo.

Isto **não** é específico de nenhum patcher ou ferramenta em particular. Qualquer projeto que
extraia, edite e reempacote o `app.asar` do Claude Desktop pode disparar um
ou ambos os problemas se não tratar corretamente dois detalhes específicos de
macOS/Electron. Este repositório documenta ambas as causas-raiz e traz um
script de reparo de um único comando.

---

## Sintoma 1 — A aba do Claude Code não inicia

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

Apenas a **aba do Claude Code** falha. O restante do Claude Desktop (chat, etc.)
funciona normalmente.

## Sintoma 2 — O aplicativo inteiro não abre

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

Nada abre — o processo aborta imediatamente ao ser iniciado. Você só verá
essa mensagem se executar o executável do Claude Desktop diretamente pelo terminal
(`/Applications/Claude.app/Contents/MacOS/Claude`); um duplo clique no aplicativo
simplesmente falha em abrir, silenciosamente.

---

## Causas-raiz

### 1. Um binário nativo foi empacotado *dentro* do `app.asar` em vez de permanecer desempacotado no disco

Aplicativos Electron mantêm certos arquivos — módulos nativos (`*.node`), bibliotecas
dinâmicas (`*.dylib`) e qualquer outro binário auxiliar nativo — fisicamente
desempacotados no disco, ao lado do `app.asar`, em um diretório irmão
`app.asar.unpacked/`. Todo o resto fica empacotado dentro do único arquivo
`app.asar`.

Se um script de reempacotamento decide o que manter desempacotado usando uma lista
**fixa (hardcoded)** de extensões de arquivo (um padrão comum: `{*.node,*.dylib,spawn-helper}`),
qualquer binário nativo que não corresponda — por exemplo, um binário auxiliar da
aba do Claude Code que é distribuído sem uma dessas extensões — acaba sendo empacotado
*dentro* do arquivo. Uma entrada de arquivo dentro do archive não é um arquivo real e
executável de forma independente: o sistema operacional não consegue fazer `exec()` de um
intervalo de bytes no meio de outro arquivo e obter um programa válido a partir disso.
Quando o Claude Desktop tenta executar esse binário, o sistema operacional lê um trecho
de bytes que não está alinhado como arquivo e reporta como um Mach-O corrompido/inválido —
daí o erro "Malformed Mach-o file".

**Correção:** não fixe a lista de desempacotamento. Calcule-a dinamicamente a partir
do que já está desempacotado ao lado do `app.asar` original antes de tocar em qualquer
coisa, e use esse mesmo conjunto ao reempacotar. Veja
[`lib/unpack.js`](../lib/unpack.js) para uma implementação pronta para uso, e verifique
depois do reempacotamento que nada ficou faltando.

### 2. Reassinar sem antes remover as assinaturas aninhadas antigas

Modificar arquivos dentro do `app.asar` invalida as assinaturas de código aninhadas
de sub-bundles já assinados que são distribuídos junto com ele
(`Contents/Frameworks/*.framework`, auxiliares `Contents/Frameworks/*.app`,
`Contents/Helpers/*`, serviços XPC embutidos, etc.) — mas não remove essas
assinaturas antigas. Executar `codesign --force --deep --sign -` por cima delas
pode deixar o bundle em um estado inconsistente:

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

A própria etapa de *assinatura* reporta sucesso ("replacing existing signature") —
a falha só aparece no `--verify`, o que é fácil de não perceber se você não
checar isso explicitamente.

**Correção:** execute `codesign --remove-signature --deep` primeiro para remover
todas as assinaturas aninhadas, *depois* assine do zero. Veja
[`lib/macos.js`](../lib/macos.js).

### 3. O fuse de integridade do ASAR embutido do Electron

Este é o que causa o Sintoma 2 (o aplicativo inteiro não abre). O Electron tem
um "fuse" definido em tempo de build — `EnableEmbeddedAsarIntegrityValidation` — que,
quando ativado, embute o hash SHA-256 esperado do `app.asar` diretamente no
**binário do Electron Framework**
(`Contents/Frameworks/Electron Framework.framework/Electron Framework` no
macOS — *não* o executável principal do aplicativo em `Contents/MacOS/`, e *não*
qualquer chave `ElectronAsarIntegrity` que você possa encontrar no `Info.plist`, que é um
mecanismo legado separado e não relacionado, que algumas ferramentas de build também
costumam escrever).

Uma vez que o `app.asar` é modificado, o hash embutido deixa de corresponder,
e o Electron trava de forma irrecuperável ao iniciar, em vez de degradar graciosamente.

Recalcular e corrigir esse hash embutido manualmente não é prático — ele faz parte
de um formato específico de "fuse wire" binário, junto com várias outras flags.
A correção suportada é desabilitar o fuse por completo usando a própria ferramenta
do Electron, [`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses):

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

Isso modifica o binário do Electron Framework, o que invalida sua assinatura —
você precisa reassinar o bundle inteiro depois disso (a correção da causa-raiz nº 2
cuida disso).

---

## Correção rápida — já tem uma instalação quebrada?

Se você só precisa reparar o `Claude.app` que já tem instalado (não precisa saber
qual dos problemas acima te atingiu — isto corrige ambos):

### Um clique (sem terminal)

1. [Baixe este repositório](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip) e descompacte.
2. Dê um duplo clique em **`Fix Claude.command`**.
3. Uma janela de terminal se abre, guia você por cada etapa e oferece
   reiniciar o Claude Desktop para você quando terminar.

O macOS pode avisar que o arquivo é de um desenvolvedor não identificado na primeira
vez — clique com o botão direito nele e escolha **Abrir** para contornar isso uma vez.

### Uma linha (terminal)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

Ou clone e execute localmente:

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

O `repair.sh` detecta automaticamente o `Claude.app` (ou `Claude Beta.app`) nos
locais de instalação usuais, encerra-o caso esteja em execução, percorre cada
etapa de reparo com saída clara de sucesso/falha, verifica o resultado e oferece
reiniciar o aplicativo para você. Passe um caminho explicitamente se o seu estiver
em algum lugar incomum:

```bash
./repair.sh "/path/to/Claude Beta.app"
```

O `repair.sh` **não** modifica nenhuma funcionalidade ou conteúdo real do Claude
Desktop — ele apenas desativa o fuse de integridade e reassina o bundle.
É seguro executá-lo mesmo se você não tiver certeza de qual sintoma está enfrentando,
e seguro executá-lo várias vezes. Se ele não conseguir escrever no bundle do
aplicativo, vai indicar que você deve executá-lo novamente com `sudo`.

---

## Se você está construindo seu próprio patcher

Se você está escrevendo uma ferramenta que modifica o `app.asar` (para localização,
temas, plugins, ou qualquer outra coisa), pode evitar distribuir esses bugs aos
seus usuários desde já. Este repositório inclui módulos prontos para uso e
documentados:

- [`lib/unpack.js`](../lib/unpack.js) — calcula o glob correto de `unpack` para o
  `createPackageWithOptions` do `@electron/asar`, dinamicamente, a partir do que
  já está desempacotado. Substituto direto para uma lista fixa de extensões.
- [`lib/macos.js`](../lib/macos.js) — reassina corretamente um bundle de aplicativo
  macOS (remove as assinaturas aninhadas primeiro, depois assina do zero, depois verifica).
- [`lib/fuses.js`](../lib/fuses.js) — desativa o fuse de integridade do ASAR embutido
  do Electron usando `@electron/fuses`.

Os três são Node.js puro, com poucas dependências e independentes de framework —
eles não fazem nenhuma suposição sobre *o que* você está modificando no Claude
Desktop, apenas que você está reempacotando o `app.asar` e reassinando o bundle
depois.

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

## Por que isto não é um bug do Claude Desktop

Para deixar claro: o Claude Desktop está se comportando corretamente aqui. O fuse
de integridade do ASAR do Electron e a assinatura de código do macOS *deveriam*
rejeitar um bundle de aplicativo modificado — esse é exatamente o objetivo deles.
Este repositório existe para pessoas que optaram deliberadamente por modificar sua
própria cópia local do Claude Desktop (por acessibilidade, localização, ou outros
motivos pessoais legítimos) e querem que seu patch também desative/atualize
corretamente os mecanismos que, do contrário, o bloqueariam, em vez de deixá-lo
parcialmente quebrado.

## Contribuindo

Issues e PRs são bem-vindos. Se você encontrar uma variante deste bug que não
esteja coberta acima, por favor inclua:
- A mensagem de erro exata (log de crash do Console.app ou saída do terminal ao
  executar `Contents/MacOS/<AppName>` diretamente)
- `codesign -dv --verbose=4 /Applications/Claude.app`
- Qual ferramenta/patch você estava usando quando o problema ocorreu

## Licença

MIT
