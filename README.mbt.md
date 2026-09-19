# CodeMoonBit

A CodeMirror-like code editor written entirely in [MoonBit](https://www.moonbitlang.com/),
compiled to `wasm-gc` and driven from JavaScript through a thin DOM FFI layer.

The editor logic — document model, transactions, extension system, syntax
highlighting, search/replace, folding, keymaps, multi-cursor editing, undo/redo
and rendering — lives in MoonBit. JavaScript only provides DOM primitives,
measurement and event plumbing.

## Features

- **Document model**: immutable line-based text, UTF-16 code-unit offsets,
  position/line mapping, `Range`/`RangeSet`, `Change`/`ChangeSet` with inverted
  changes and position mapping.
- **State and transactions**: CodeMirror-style `Facet`, `StateField`,
  `StateEffect`, `Extension`, `Transaction`, `EditorState` with typed,
  closure-based heterogeneous state (no `Any` needed).
- **Editing**: insert/delete, auto-indent on Enter, tab stops, line/word
  deletion, indentation, line comment toggling, multi-cursor
  (`Alt-ArrowUp/Down`, `Mod-d`), selections, word/line double/triple click.
- **History**: grouped typing/delete undos with redo, bounded by group count.
- **Syntax highlighting**: incremental, line-state based tokenizers for
  MoonBit, JavaScript, JSON and Markdown, with a per-line cache and
  invalidation on edits.
- **Search and replace**: literal and a small regex subset (`^ $ . * + ? [] |`
  `\d \w \s \b`), match highlighting, next/previous, replace and replace all.
- **Code folding**: bracket and indentation based folds, fold widgets, fold
  all/unfold all.
- **Rendering**: viewport-based virtual rendering with full-document scroll
  height, gutter line numbers, active
  line, selections, cursors, bracket matching, optional soft wrapping,
  light/dark themes, read-only mode.
- **Input**: extensible keymap facet with a CodeMirror-like default keymap,
  IME composition forwarding, clipboard copy/cut/paste, mouse selection and
  dragging, scroll forwarding.

## Layout

| directory   | contents                                                       |
| ----------- | -------------------------------------------------------------- |
| `core/`     | text, ranges, changes, selections (pure, unit tested)          |
| `state/`    | facets, fields, effects, transactions, history (pure)          |
| `highlight/`| incremental tokenizers and line cache (pure)                   |
| `search/`   | search/replace, folding, bracket matching (pure)               |
| `input/`    | keymap, commands, multi-cursor (pure)                          |
| `ffi/`      | wasm DOM imports and code-unit string marshalling              |
| `view/`     | layout, geometry, rendering, mouse/scroll dispatch             |
| `editor/`   | assembled editor: extensions, options, event entry points      |
| `main/`     | wasm exports (`cm_*`) and the editor registry                  |
| `js/`       | DOM runtime, Node DOM shim, e2e tests, browser loader          |
| `demo/`     | static demo page                                               |

## Build and test

```sh
moon check --target wasm-gc          # type check
moon test --target wasm-gc           # 100 unit tests (pure packages)
moon build --target wasm-gc          # _build/wasm-gc/debug/build/main/main.wasm
node js/e2e.mjs                      # 30 end-to-end tests through a DOM shim
node js/browser_e2e.mjs              # 32 real-browser tests (Chromium over CDP)
moon fmt && moon info
```

## Using it in a browser

```sh
python3 -m http.server 8000
# open http://localhost:8000/demo/
```

```html
<div id="editor" style="height: 400px"></div>
<script type="module">
  import { createEditor } from "./js/browser.js";

  const editor = await createEditor(document.getElementById("editor"), {
    value: "fn main {\n  println(\"hello\")\n}\n",
    language: "moonbit",
    lineNumbers: true,
    theme: "light",
  });

  editor.focus();
</script>
```

The returned handle exposes `getDoc`, `setDoc`, `getHTML`, `getState`, `focus`,
`destroy`, `openSearch`, `searchNext`, `searchPrev`, `replace`, `replaceAll`,
`undo`, `redo`, `foldAll`, `unfoldAll`, `foldClick`, `key`, `mouse`, `paste`,
`selectedText`, `setOption`.

## How the FFI works

- JS calls exported wasm functions declared in `main/moon.pkg`; they use only
  `Int`, `Bool`, `Double` and `#external type JsAny` (externref) parameters.
- MoonBit builds JS strings with `sb_new`/`sb_push`/`sb_finish`; JS passes
  strings to MoonBit as externref and MoonBit reads them with
  `js_len`/`js_char`. All offsets are UTF-16 code units.
- Events are wired in `js/dom_runtime.js`: DOM listeners forward to `cm_key`,
  `cm_mouse`, `cm_scroll`, `cm_paste`, `cm_composition`, and so on. MoonBit
  renders by computing an HTML string for the visible viewport and assigning it
  through `set_html`.

## Limitations

- Rendering rebuilds the visible viewport HTML on each transaction instead of
  doing incremental DOM diffing.
- Soft wrapping is approximated from measured character widths.
- Shift-click selection extension is not wired (mousedown carries no modifier).
- The regex engine used by search is a small subset, not a full regex engine.
