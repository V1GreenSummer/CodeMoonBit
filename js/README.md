# CodeMoonBit JS host

JavaScript side of CodeMoonBit. The MoonBit module is compiled to `wasm-gc`
and driven from JS through the `"dom"` wasm import namespace.

```
js/dom_runtime.js   implements the wasm "dom" imports, builds the editor
                    scaffold and forwards DOM events to the wasm exports
js/browser.js       `createEditor(container, options)` public browser API
js/codemoonbit.css  distributable editor stylesheet scoped to `.cm-editor`
js/shim_dom.js      minimal fake DOM + wasm loader for Node
js/e2e.mjs          Node end-to-end tests (`node js/e2e.mjs`)
js/browser_e2e.mjs  real-browser tests over the DevTools protocol
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
<link rel="stylesheet" href="./js/codemoonbit.css" />
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
  const selection = editor.getSelection(); // { main, ranges: [{anchor, head}] }
</script>
```

The container needs a definite height (for example `#editor { height: 70vh }`);
`.cm-editor` fills it. `js/codemoonbit.css` is scoped to `.cm-editor`, so any
container works and several editors can coexist on one page.

`createEditor` returns a handle:

```
{ id, focus(), destroy(), getDoc(), setDoc(text), getHTML(), getSelection(),
  getState(), onUpdate(callback), openSearch(), closeSearch(), searchNext(),
  searchPrev(), replace(v), replaceAll(v), undo(), redo(), foldAll(),
  unfoldAll(), foldClick(line), key(key, code, mods), mouse(kind,x,y,detail),
  paste(text), selectedText(), setOption(k,v) }
```

`handle.onUpdate(callback)` subscribes to document/selection changes. It fires
once asynchronously right after creation and then after every state-changing
operation (edits, selection changes, `setDoc`, `setOption`). It returns an
unsubscribe function; exceptions thrown by a listener are reported and do not
break the editor.

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
`dispatchScroll`, `dispatchFocus`, `onUpdate`. They run the same handlers
registered by the real DOM listeners (via `__testForward` from
`dom_runtime.js`); `onUpdate` subscribes to the `notify_update` wasm import.

## Runtime notes and limitations

- **Scaffold.** `attach(container, id)` creates
  `.cm-editor > [.cm-gutters, .cm-scroller > (.cm-content, textarea.cm-input),
  .cm-panel, .cm-measure]`. `part(container, name)` lazily creates it too.
  After every `set_html` of `.cm-content` the runtime computes
  `max(top+height)` over the rendered children and sets the content
  height/minHeight so the scroller can scroll.
- **Search panel.** `cm_search_open` (the `openSearch()` method, or `Ctrl-f`
  handled by the MoonBit keymap) shows `.cm-panel`; the panel's controls call
  `cm_search_query/next/prev/replace/replace_all/close`. Visibility and the
  `.cm-search-count` readout (`` `${current + 1} / ${total}` ``, or `0 / 0`
  with `.cm-search-count-empty`) are synced from `cm_get_state`
  (`search=1/<total>/<current>`) after forwarded events and after every
  `notify_update`, so `Ctrl-f` also opens the panel. The prev/next/replace
  buttons carry shortcut `title` hints. Opening focuses the search input;
  closing focuses the textarea.
- **Focus state.** The textarea's `focus`/`blur` events toggle `cm-focused` on
  the `.cm-editor` root (and forward to `cm_focus_event`), which the
  stylesheet uses to show the focus ring and to hide the cursor while
  unfocused.
- **Gutter markers.** The view renders one `.cm-fold` span per foldable line
  in the gutter: `.cm-fold.cm-fold-foldable` (`▾`, dim) when the block can be
  folded and `.cm-fold.cm-fold-folded` (`▸`, bright) when it is folded (plus
  the inline `.cm-fold-ellipsis`). Both carry `data-line`, and a click is
  turned into `cm_fold_click` by the runtime. The cursor line's gutter number
  gets `.cm-active-gutter`.
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
- **Update notifications.** The view calls the wasm import
  `notify_update(editor_id)` after state-changing operations (non-empty
  changesets, selection changes, `set_state`, `set_doc`), never from `render`
  or `dispatch_scroll`. Host listeners registered through
  `handle.onUpdate(callback)` run synchronously and their exceptions are
  reported without interrupting the editor.
- **Approximate wrapping.** With `lineWrapping` the view splits a line into one
  `.cm-line` div per measured segment (`.cm-line { overflow: hidden }`); the
  split points come from per-character width measurement, so they can differ
  slightly from the browser's own line breaking.
- **Viewport HTML rebuild.** Every render rebuilds the `.cm-content` and
  `.cm-gutters` HTML for the visible range only; off-screen lines do not exist
  in the DOM, so DOM-based selection/anchor APIs do not see them.
- The shim's `innerHTML` parser only understands simple tags/text; the raw
  string is always preserved for `get_html`, so `cm_get_html` assertions are
  exact.
