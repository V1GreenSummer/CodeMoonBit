# AGENTS.md

CodeMoonBit is a CodeMirror-like code editor written in MoonBit, compiled to
`wasm-gc` and driven from JavaScript through DOM FFI.

## Build & test

- `moon check --target wasm-gc` — type check everything.
- `moon test --target wasm-gc` — run unit tests of pure packages.
- `moon build --target wasm-gc` — build `main` to
  `_build/wasm-gc/debug/build/main/main.wasm`.
- `node js/e2e.mjs` — run the end-to-end integration tests against the built
  wasm module using the Node DOM shim.
- `node js/browser_e2e.mjs` — run the real-browser integration tests by driving
  a locally installed Chromium through the DevTools protocol (no npm deps;
  set `CHROME_PATH` to override the browser executable).
- `moon fmt` and `moon info` before finishing.

## Hard constraints

1. **Pure packages must not import `ffi`.** `moon test` runs wasm through
   `moonrun`, which cannot provide custom wasm imports. Only `view`, `editor`
   and `main` may depend on `ffi`.
2. **Exported wasm functions** (listed in `main/moon.pkg` link exports) may only
   use `Int`, `Bool`, `Double`, and `#external type JsAny` parameters/results.
   `String`, arrays and structs are not callable from JS.
3. **Strings cross the boundary as code units**:
   - MoonBit → JS: `@ffi.JsStringBuilder` (`sb_new`/`sb_push`/`sb_finish`).
   - JS → MoonBit: `@ffi.read_js_string(jsAny)`.
4. Offsets are UTF-16 code units. Use `String::unsafe_get(i)` (returns `UInt16`)
   for code-unit access, never `s[i]` (which may combine surrogate pairs).
5. No `Any` type exists in MoonBit. Heterogeneous state is handled by the
   closure-based `Facet` / `StateField` / `StateEffect` machinery in `state`.
6. Do not use `fail(...)`; use `abort(...)`.

## Package layout

| package     | may import                              | testable with `moon test` |
| ----------- | --------------------------------------- | ------------------------- |
| `core`      | —                                       | yes                       |
| `state`     | `core`                                  | yes                       |
| `highlight` | `core`                                  | yes                       |
| `search`    | `core`, `state`                         | yes                       |
| `input`     | `core`, `state`                         | yes                       |
| `ffi`       | —                                       | no (wasm imports)         |
| `view`      | `core`, `state`, `ffi`, `highlight`     | no                        |
| `editor`    | `core`, `state`, `highlight`, `search`, `input`, `view`, `ffi` | no |
| `main`      | `editor`, `ffi`                         | no                        |

`main` exports the JS-facing entry points declared in `main/moon.pkg`.

## Frozen `core` API (`@core`)

- `Text`: immutable line-based document. `Text::of`, `empty`, `lines`, `line`,
  `line_length`, `length`, `line_start`, `line_end`, `line_at`, `line_col`,
  `pos`, `clip_pos`, `slice`, `line_slice`, `to_string`, `replace`,
  `append`, `eq`, `iter_lines`.
- `Range { from, to }`, `RangeSet`: `RangeSet::of(Array[Range])`,
  `ranges`, `size`, `iter`, `contains`, `between`, `update`, `map`.
- `Change { from, to, text }`, `ChangeSet`: `ChangeSet::of(Array[Change])`,
  `apply(Text)`, `invert(Text)`, `map_pos(pos, assoc)`, `map_range`,
  `changes`, `length`, `is_empty`, `delta`.
- `SelectionRange { anchor, head }`, `EditorSelection`:
  `cursor`, `single`, `create(Array[SelectionRange], main)`, `ranges`,
  `range_count`, `main_index`, `main_range`, `set_main_index`, `eq`,
  `add_range`, `map(ChangeSet, assoc~)`, `normalized`, `is_cursor`.

## Frozen `state` API

- `Facet::new(default~, combine~)`, `facet.of(value) -> Extension`,
  `state.facet(facet)`.
- `StateField::new(init~, update?)`, `field.extension()`,
  `state.field(field)`; `init : (EditorState) -> T`,
  `update : (T, Transaction) -> T`.
- `StateEffect::new()`, `effect.of(value) -> EffectEntry`,
  `tr.effects(effect) -> Array[T]`, `tr.effect(effect) -> T?`.
- `Extension`: `Extension::of(Array[Extension])`, `empty`, `single`,
  `+`, `items`, `fields`, `facet_items`.
- `TransactionSpec::new(changes?, selection?, effects?, annotations?,
  scroll_into_view?)`.
- `EditorState::create(config? : Array[Extension], doc?, selection?)`,
  `update(spec) -> Transaction`, `apply(spec) -> EditorState`, `doc()`,
  `selection()`, `line_count()`, `line(n)`, `length()`, `to_string()`,
  `slice(from, to)`, `facet`, `field`, `extensions`.
- `Transaction`: `start_state`, `changes`, `selection`, `new_doc`,
  `effects`, `effect`, `annotations`, `user_event`, `add_to_history`,
  `is_remote`, `scroll_into_view`, `state()`.
- `Annotation`: `UserEvent(String) | AddToHistory(Bool) | Remote(Bool) |
  ScrollIntoView(Bool)`.
- History: `history_field`, `undo_spec(state)`, `redo_spec(state)`.
  History groups consecutive `input.type` / `input.delete` events when the
  next transaction starts exactly where the previous one ended.

## Frozen `ffi` API (`@ffi`)

`JsAny` is an externref. Imports live in wasm module `"dom"`:
`sb_new`, `sb_push`, `sb_clear`, `sb_finish`, `js_len`, `js_char`, `create`,
`append`, `set_html`, `set_text`, `get_text`, `get_html`, `set_class`,
`add_class`, `remove_class`, `set_style`, `set_attr`, `remove_attr`, `part`,
`set_scroll`, `scroll_top`, `scroll_left`, `client_width`, `client_height`,
`scroll_height`, `scroll_width`, `focus`, `blur`, `measure_width`, `attach`,
`detach`, `request_measure`, `notify_update`, `log`.

Helpers: `push_string`, `push_js_string`, `read_js_string`, `js_string`,
`JsStringBuilder`, `measure_text`, `log_string`.

`get_html(el)` returns the element's current `innerHTML` (used by
`cm_get_html`). `notify_update(editor_id)` is called by the view after
state-changing operations (non-empty changes, selection changes, `set_state`,
`set_doc`), never from `render` or scrolling; the JS host surfaces it as
`handle.onUpdate(callback)` in `js/browser.js` and as `onUpdate(id, callback)`
in `js/dom_runtime.js`.

The DOM part names passed to `@ffi.part(container, name)` are:
`"scroller"`, `"content"`, `"gutter"`, `"input"`, `"measure"`.

## Role contract

Only modify files inside the directory owned by your task. Other directories
belong to other agents working in parallel. If an interface is missing, add it
only in your own package and report it in your final message instead of editing
another package.
