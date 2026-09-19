# CodeMoonBit JS host

JavaScript side of CodeMoonBit. The MoonBit module is compiled to `wasm-gc`
and driven from JS through the `"dom"` wasm import namespace.

```
js/dom_runtime.js   implements the wasm "dom" imports, builds the editor
                    scaffold and forwards DOM events to the wasm exports
js/browser.js       `createEditor(container, options)` public browser API
js/shim_dom.js      minimal fake DOM + wasm loader for Node
js/e2e.mjs          Node end-to-end tests (`node js/e2e.mjs`)
```

## Build & test

```sh
moon build --target wasm-gc
node js/e2e.mjs
```

`moon build` writes `_build/wasm-gc/debug/build/main/main.wasm`; the e2e
script (and browser.js) probe both that path and the documented
`_build/wasm-gc/debug/build/main.wasm`.

## Browser usage

```html
<script type="module">
  import { createEditor } from "./js/browser.js";

  const editor = await createEditor("#editor", {
    value: "fn main {\n  println(\"hi\")\n}",
    language: "moonbit",
    lineNumbers: true,
  });

  editor.focus();
  editor.openSearch();
  editor.setDoc("new text");
</script>
```

`createEditor` returns a handle:

```
{ id, focus(), destroy(), getDoc(), setDoc(text), getHTML(), getState(),
  openSearch(), closeSearch(), searchNext(), searchPrev(), replace(v),
  replaceAll(v), undo(), redo(), foldAll(), unfoldAll(), foldClick(line),
  key(key, code, mods), mouse(kind,x,y,detail), paste(text), selectedText(),
  setOption(k,v) }
```

Options: `doc`/`value`, `lineNumbers`, `lineWrapping`, `readOnly`,
`tabSize`, `language`, `theme`, `font`, `lineHeight`, plus `wasmUrl`.

## Node shim

`shim_dom.js` implements just enough DOM for the runtime: elements with
`className`/`classList`/`style`/attributes, a regex-based `innerHTML`
parser, events with bubbling, `getBoundingClientRect`, scroll metrics and
`focus`/`blur`. `loadWasm(url)` reads `file:` URLs with `node:fs` and
instantiates with `createImports()`.

`getImportsDeps()` exposes the event forwarding helpers used by the e2e
tests: `dispatchKey`, `dispatchKeyEvent`, `dispatchMouse`,
`dispatchBeforeInput`, `dispatchPaste`, `dispatchCopy`, `dispatchCut`,
`dispatchScroll`, `dispatchFocus`. They run the same handlers registered by
the real DOM listeners (via `__testForward` from `dom_runtime.js`).

## Runtime notes and limitations

- **Scaffold.** `attach(container, id)` creates
  `.cm-editor > [.cm-gutters, .cm-scroller > (.cm-content, textarea.cm-input),
  .cm-panel, .cm-measure]`. `part(container, name)` lazily creates it too.
  After every `set_html` of `.cm-content` the runtime computes
  `max(top+height)` over the rendered children and sets the content
  height/minHeight so the scroller can scroll.
- **Search panel.** `cm_search_open` (the `openSearch()` method, or `Ctrl-f`
  handled by the MoonBit keymap) shows `.cm-panel`; the panel's controls call
  `cm_search_query/next/prev/replace/replace_all/close`. Visibility is synced
  from `cm_get_state` (`search=1/...`) after forwarded events, so `Ctrl-f`
  also opens the panel. Opening focuses the search input; closing focuses
  the textarea.
- **Shift-click** cannot extend the selection: `cm_mouse` receives no
  modifier bits and the MoonBit view always creates a fresh selection on
  mousedown. Double/triple click work through `e.detail`.
- **Cut** copies `cm_selected_text` and then sends `Backspace` through
  `cm_key`, which deletes a non-empty selection. A cut with a collapsed
  cursor is a no-op.
- **Measuring.** `measure_width` uses a canvas 2D context in browsers; the
  Node shim has no canvas, so it falls back to 8px per code unit. Empty text
  measures 0.
- **Scroll.** Scroll events are coalesced with `requestAnimationFrame` before
  calling `cm_scroll`; the gutter's `scrollTop` is kept in sync.
- **Upstream bug.** `input/commands.mbt`'s `code_unit_at` reads
  `line[col]` even when `col` is the line length, so `ArrowLeft`/`Backspace`
  exactly at a newline boundary aborts inside the frozen MoonBit code. The
  e2e suite exercises those keys mid-line instead.
- The shim's `innerHTML` parser only understands simple tags/text; the raw
  string is always preserved for `get_html`, so `cm_get_html` assertions are
  exact.
