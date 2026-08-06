# Claude Desktop — Corrección del error "Malformed Mach-o file" / integridad ASAR (macOS)

🌐 **Lee esto en otro idioma:** [English](../README.md) · [فارسی](README.fa.md) · [العربية](README.ar.md) · [中文](README.zh.md) · [Español](README.es.md) · [हिन्दी](README.hi.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

Una corrección y explicación para dos fallos relacionados que pueden ocurrir en
**Claude Desktop para macOS** después de que `app.asar` (el código empaquetado
de la aplicación Claude Desktop) haya sido modificado — ya sea por un parche
de terceros, un plugin, manipulación manual, o cualquier otra cosa que
reempaquete o edite el bundle de la aplicación.

Esto **no** es específico de ningún parcheador o herramienta en particular.
Cualquier proyecto que extraiga, edite y reempaquete el `app.asar` de Claude
Desktop puede desencadenar uno o ambos problemas si no maneja correctamente
dos detalles específicos de macOS/Electron. Este repositorio documenta ambas
causas raíz y ofrece un script de reparación de un solo comando.

---

## Síntoma 1 — La pestaña de Claude Code no arranca

<img src="../assets/error-code-tab-detail.png" alt="Claude Code couldn't start — Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file" width="500">
<img src="../assets/error-code-tab-toast.png" alt="Claude Code couldn't start toast notification" width="500">

```
Claude Code couldn't start
Restarting Claude Desktop may resolve this.

Claude Code process exited with code 127. stderr: Failed to spawn process: Malformed Mach-o file

Failed to spawn process: Malformed Mach-o file
```

Solo falla la **pestaña de Claude Code**. El resto de Claude Desktop (chat,
etc.) funciona con normalidad.

## Síntoma 2 — La aplicación entera no arranca

```
[FATAL:electron/shell/common/asar/asar_util.cc:144] Integrity check failed
for asar archive (139796d9f05e1667a633fdc5dab1f565760ef18a4584202fdcddc9a94717db6a
vs eb74792783f1d924ccdba5e302805b10e95fa1ff0c6dd04794ba452c14ee2d52)
```

No se abre nada en absoluto — el proceso se aborta inmediatamente al
lanzarse. Solo verás esto si ejecutas el ejecutable de Claude Desktop
directamente desde una terminal
(`/Applications/Claude.app/Contents/MacOS/Claude`); al hacer doble clic en
la aplicación simplemente falla en abrirse en silencio.

---

## Causas raíz

### 1. Un binario nativo terminó empaquetado *dentro* de `app.asar` en lugar de permanecer sin empaquetar en disco

Las aplicaciones de Electron mantienen ciertos archivos — módulos nativos
(`*.node`), bibliotecas dinámicas (`*.dylib`), y cualquier otro binario
auxiliar nativo — físicamente sin empaquetar en disco, junto a `app.asar`,
en un directorio hermano `app.asar.unpacked/`. Todo lo demás vive empaquetado
dentro del único archivo `app.asar`.

Si un script de reempaquetado decide qué mantener sin empaquetar usando una
lista **codificada de forma fija** de extensiones de archivo (un patrón
común: `{*.node,*.dylib,spawn-helper}`), cualquier binario nativo que no
coincida — por ejemplo, un binario auxiliar para la pestaña de Claude Code
que se distribuye sin una de esas extensiones — termina empaquetado *dentro*
del archivo en lugar de fuera. Una entrada de archivo dentro de un archive
no es un archivo real, ejecutable de forma independiente: el sistema
operativo no puede hacer `exec()` sobre un rango de bytes en medio de otro
archivo y obtener un programa válido de ahí. Cuando Claude Desktop intenta
lanzar ese binario, el sistema operativo lee un fragmento de bytes que no
está alineado como archivo y lo reporta como un Mach-O corrupto/inválido —
de ahí "Malformed Mach-o file".

**Solución:** no codifiques de forma fija la lista de archivos sin
empaquetar. Calcúlala dinámicamente a partir de lo que ya está sin empaquetar
junto al `app.asar` original antes de tocar nada, y usa ese mismo conjunto al
reempaquetar. Consulta [`lib/unpack.js`](../lib/unpack.js) para una
implementación lista para usar, y verifica después de reempaquetar que no
falte nada.

### 2. Volver a firmar sin eliminar antes las firmas anidadas obsoletas

Modificar archivos dentro de `app.asar` invalida las firmas de código
anidadas de los sub-bundles ya firmados que se distribuyen junto a él
(`Contents/Frameworks/*.framework`, ayudantes `Contents/Frameworks/*.app`,
`Contents/Helpers/*`, servicios XPC embebidos, etc.) — pero no elimina esas
firmas obsoletas. Ejecutar `codesign --force --deep --sign -` sobre ellas
puede dejar el bundle en un estado inconsistente:

```
$ codesign --verify --deep --strict /Applications/Claude.app
/Applications/Claude.app: nested code is modified or invalid
file modified: .../Claude Helper (GPU).app
file modified: .../Electron Framework.framework
...
```

El propio paso de *firma* reporta éxito ("replacing existing signature") —
el fallo solo aparece al hacer `--verify`, algo fácil de pasar por alto si
no lo compruebas explícitamente.

**Solución:** ejecuta primero `codesign --remove-signature --deep` para
eliminar todas las firmas anidadas, *y luego* firma desde cero. Consulta
[`lib/macos.js`](../lib/macos.js).

### 3. El fuse de integridad ASAR embebido de Electron

Este es el que causa el Síntoma 2 (la aplicación entera no arranca).
Electron tiene un "fuse" en tiempo de compilación —
`EnableEmbeddedAsarIntegrityValidation` — que, cuando está habilitado, graba
el hash SHA-256 esperado de `app.asar` directamente en el binario del
**Electron Framework**
(`Contents/Frameworks/Electron Framework.framework/Electron Framework` en
macOS — *no* el ejecutable principal de la aplicación en `Contents/MacOS/`,
y *no* ninguna clave `ElectronAsarIntegrity` que puedas encontrar en
`Info.plist`, que es un mecanismo heredado separado y no relacionado que
algunas herramientas de compilación también suelen escribir).

Una vez que se parchea `app.asar`, el hash embebido ya no coincide, y
Electron se bloquea de forma abrupta al arrancar en lugar de degradarse con
elegancia.

Recalcular y parchear ese hash embebido a mano no es práctico — forma parte
de un formato específico de "fuse wire" binario junto con varias otras
banderas. La solución soportada es deshabilitar el fuse por completo usando
las herramientas propias de Electron,
[`@electron/fuses`](https://www.npmjs.com/package/@electron/fuses):

```bash
npx --yes @electron/fuses write --app /Applications/Claude.app EnableEmbeddedAsarIntegrityValidation=off
```

Esto modifica el binario de Electron Framework, lo cual invalida su firma —
debes volver a firmar todo el bundle después (la solución de la causa raíz
#2 se encarga de esto).

---

## Solución rápida — ¿ya tienes una instalación rota?

Si solo necesitas reparar el `Claude.app` que ya tienes (no necesitas saber
cuál de las causas anteriores te afectó — esto corrige ambas):

### Un clic (sin terminal)

1. [Descarga este repositorio](https://github.com/<your-username>/claude-macho-fix/archive/refs/heads/main.zip) y descomprímelo.
2. Haz doble clic en **`Fix Claude.command`**.
3. Se abre una ventana de terminal, te guía por cada paso, y ofrece volver a
   lanzar Claude Desktop por ti cuando termine.

macOS puede advertir que el archivo proviene de un desarrollador no
identificado la primera vez — haz clic derecho sobre él y elige **Abrir**
para omitir eso una vez.

### Una línea (terminal)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/claude-macho-fix/main/repair.sh | bash
```

O clónalo y ejecútalo localmente:

```bash
git clone https://github.com/<your-username>/claude-macho-fix.git
cd claude-macho-fix
./repair.sh
```

`repair.sh` detecta automáticamente `Claude.app` (o `Claude Beta.app`) en
las ubicaciones de instalación habituales, lo cierra si está en ejecución,
recorre cada paso de la reparación con una salida clara de éxito/fallo,
verifica el resultado, y ofrece volver a lanzar la aplicación por ti. Pasa
una ruta explícita si la tuya está en un lugar inusual:

```bash
./repair.sh "/path/to/Claude Beta.app"
```

`repair.sh` **no** modifica ninguna de las funcionalidades ni el contenido
real de Claude Desktop — solo deshabilita el fuse de integridad y vuelve a
firmar el bundle. Es seguro ejecutarlo aunque no estés seguro de cuál
síntoma tienes, y seguro ejecutarlo varias veces. Si no puede escribir en el
bundle de la aplicación, te indicará que lo vuelvas a ejecutar con `sudo`.

---

## Si estás construyendo tu propio parcheador

Si estás escribiendo una herramienta que parchea `app.asar` (para
localización, temas, plugins, o cualquier otra cosa), puedes evitar
distribuir estos errores a tus usuarios desde el principio. Este
repositorio incluye módulos documentados y listos para usar:

- [`lib/unpack.js`](../lib/unpack.js) — calcula el glob `unpack` correcto
  para `createPackageWithOptions` de `@electron/asar`, de forma dinámica, a
  partir de lo que ya está sin empaquetar. Reemplazo directo para una lista
  de extensiones codificada de forma fija.
- [`lib/macos.js`](../lib/macos.js) — vuelve a firmar un bundle de
  aplicación de macOS correctamente (elimina las firmas anidadas primero,
  luego firma desde cero, luego verifica).
- [`lib/fuses.js`](../lib/fuses.js) — deshabilita el fuse de integridad
  ASAR embebido de Electron usando `@electron/fuses`.

Los tres son Node.js puro, con pocas dependencias y agnósticos al
framework — no asumen nada sobre *qué* estás parcheando en Claude Desktop
para que haga, solo que estás reempaquetando `app.asar` y volviendo a
firmar el bundle después.

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

## Por qué esto no es un error de Claude Desktop

Para que quede claro: Claude Desktop se está comportando correctamente
aquí. El fuse de integridad ASAR de Electron y la firma de código de macOS
están *diseñados* para rechazar un bundle de aplicación modificado — ese es
precisamente su propósito. Este repositorio existe para quienes han elegido
deliberadamente parchear su propia copia local de Claude Desktop (por
accesibilidad, localización, u otras razones personales legítimas) y
quieren que su parche también deshabilite/actualice correctamente los
mecanismos que de otro modo lo bloquearían, en lugar de dejarlos a medio
romper.

## Contribuir

Se aceptan issues y PRs. Si te encuentras con una variante de este error
que no está cubierta arriba, por favor incluye:
- El mensaje de error exacto (registro de fallos de Console.app o salida de
  terminal al ejecutar `Contents/MacOS/<AppName>` directamente)
- `codesign -dv --verbose=4 /Applications/Claude.app`
- Qué herramienta/parche estabas usando cuando ocurrió el fallo

## Licencia

MIT
