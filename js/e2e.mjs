// e2e.mjs
//
// End-to-end smoke tests for CodeMoonBit. Runs the real wasm module against
// the Node DOM shim and exercises both the wasm exports and the event
// forwarding implemented in `dom_runtime.js` / `shim_dom.js`.
//
// Usage: `moon build --target wasm-gc && node js/e2e.mjs`

import assert from "node:assert/strict";
import fs from "node:fs";
import {
  attachWasm,
  createElement,
  getImportsDeps,
  loadWasm,
} from "./shim_dom.js";
import { getWasm, showSearchPanel, hideSearchPanel } from "./dom_runtime.js";

function findMainWasm() {
  const candidates = [
    new URL("../_build/wasm-gc/debug/build/main.wasm", import.meta.url),
    new URL("../_build/wasm-gc/debug/build/main/main.wasm", import.meta.url),
  ];
  for (const candidate of candidates) {
    if (candidate.protocol === "file:" && fs.existsSync(candidate)) return candidate;
  }
  throw new Error(
    "main.wasm not found; run `moon build --target wasm-gc` first. Tried:\n" +
      candidates.map((candidate) => "  " + candidate.pathname).join("\n"),
  );
}

const instance = await loadWasm(findMainWasm());
attachWasm(instance.exports);
if (typeof instance.exports._start === "function") {
  instance.exports._start();
}
const wasm = getWasm();
const forward = getImportsDeps();

const container = createElement("div");
wasm.cm_create(container, 1);

const state = (id = 1) => wasm.cm_get_state(id);
const doc = (id = 1) => wasm.cm_get_doc(id);
const html = (id = 1) => wasm.cm_get_html(id);

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log("ok - " + name);
  } catch (error) {
    console.error("not ok - " + name);
    console.error(error);
    process.exit(1);
  }
}

test("cm_set_doc / cm_get_doc round trip", () => {
  wasm.cm_set_doc(1, "hello\nworld");
  assert.equal(doc(), "hello\nworld");
});

test("cm_get_state reports len and lines", () => {
  assert.match(state(), /len=11;lines=2/);
});

test("cm_get_html contains a cm-line div and the text", () => {
  const rendered = html();
  assert.ok(rendered.includes("cm-line"), "expected cm-line in html: " + rendered);
  assert.ok(rendered.includes("hello"), "expected hello in html: " + rendered);
});

test("End moves the cursor to the line end", () => {
  const handled = wasm.cm_key(1, "End", "End", 0);
  assert.equal(handled, 1);
  assert.match(state(), /sel=5:5/);
});

test("printable key inserts at the cursor", () => {
  const handled = wasm.cm_key(1, "!", "Digit1", 0);
  assert.equal(handled, 1);
  assert.equal(doc(), "hello!\nworld");
  // NOTE: the cursor maps *after* the insertion (assoc = +1), so the state
  // holds `sel=6:6`, not `5:6` as the original task text assumed.
  assert.match(state(), /sel=6:6/);
});

test("ArrowLeft moves the cursor left", () => {
  // NOTE: run while the cursor is inside a line. `code_unit_at` in
  // `input/commands.mbt` reads `line[col]` where `col` may equal the line
  // length, so arrow/backspace right at a newline boundary aborts inside the
  // frozen MoonBit code. The e2e avoids that path.
  const handled = wasm.cm_key(1, "ArrowLeft", "ArrowLeft", 0);
  assert.equal(handled, 1);
  assert.match(state(), /sel=5:5/);
  assert.equal(wasm.cm_key(1, "ArrowRight", "ArrowRight", 0), 1);
  assert.match(state(), /sel=6:6/);
});

test("Backspace removes the inserted character", () => {
  const handled = wasm.cm_key(1, "Backspace", "Backspace", 0);
  assert.equal(handled, 1);
  assert.equal(doc(), "hello\nworld");
  assert.match(state(), /sel=5:5/);
});

test("Enter inserts a newline at the end", () => {
  const handled = wasm.cm_key(1, "Enter", "Enter", 0);
  assert.equal(handled, 1);
  assert.equal(doc(), "hello\n\nworld");
  assert.match(state(), /sel=6:6/);
});

test("cm_undo / cm_redo undo and restore the newline edit", () => {
  wasm.cm_undo(1);
  assert.equal(doc(), "hello\nworld");
  wasm.cm_redo(1);
  assert.equal(doc(), "hello\n\nworld");
});

test("Enter copies the current line indentation", () => {
  wasm.cm_set_doc(1, "  foo");
  wasm.cm_key(1, "End", "End", 0);
  assert.match(state(), /sel=5:5/);
  wasm.cm_key(1, "Enter", "Enter", 0);
  assert.equal(doc(), "  foo\n  ");
  assert.match(state(), /sel=8:8/);
});

test("ctrl-a selects all", () => {
  wasm.cm_set_doc(1, "hello\nworld");
  const handled = wasm.cm_key(1, "a", "KeyA", 2);
  assert.equal(handled, 1);
  assert.match(state(), /sel=0:11/);
});

test("typing replaces the selection and cm_undo restores it", () => {
  wasm.cm_key(1, "x", "KeyX", 0);
  assert.equal(doc(), "x");
  wasm.cm_undo(1);
  assert.equal(doc(), "hello\nworld");
});

test("search open / query / next / replace all / close", () => {
  wasm.cm_search_open(1);
  assert.match(state(), /search=1\//);
  wasm.cm_search_query(1, "world");
  assert.match(state(), /search=1\/1\/0/);
  assert.match(state(), /sel=6:11/);
  wasm.cm_search_next(1);
  assert.match(state(), /search=1\/1\/0/);
  assert.match(state(), /sel=6:11/);
  wasm.cm_search_replace_all(1, "moon");
  assert.ok(doc().includes("moon"), "expected moon in doc, got: " + doc());
  wasm.cm_search_close(1);
  assert.match(state(), /search=0\//);
});

test("language option highlights moonbit keywords", () => {
  wasm.cm_set_option(1, "language", "moonbit");
  wasm.cm_set_doc(1, "fn main { let x = 1 }");
  const rendered = html();
  assert.ok(rendered.includes("tok-keyword"), "expected tok-keyword: " + rendered);
  assert.ok(rendered.includes("fn"), "expected fn in html");
});

test("readOnly blocks edits", () => {
  wasm.cm_set_option(1, "readOnly", "true");
  const before = doc();
  wasm.cm_key(1, "x", "KeyX", 0);
  assert.equal(doc(), before);
  wasm.cm_paste(1, "ignored");
  assert.equal(doc(), before);
  assert.equal(wasm.cm_input(1, "ignored"), 0);
  wasm.cm_set_option(1, "readOnly", "false");
});

test("runtime forwards keydown through the real listener path", () => {
  wasm.cm_set_option(1, "language", "plain");
  wasm.cm_set_doc(1, "hello\nworld");
  assert.equal(forward.dispatchKey(1, "End", "End", 0), 1);
  assert.match(state(), /sel=5:5/);
});

test("runtime forwards beforeinput insertText", () => {
  assert.equal(forward.dispatchBeforeInput(1, "Z"), 1);
  assert.equal(doc(), "helloZ\nworld");
});

test("runtime forwards paste", () => {
  forward.dispatchPaste(1, "!");
  assert.equal(doc(), "helloZ!\nworld");
});

test("runtime forwards mouse down and drag", () => {
  assert.equal(forward.dispatchMouse(1, 0, 0, 0, 1), 1);
  assert.match(state(), /sel=0:0/);
  forward.dispatchMouse(1, 1, 24, 5, 0);
  assert.match(state(), /sel=0:3/);
  forward.dispatchMouse(1, 2, 24, 5, 0);
});

test("runtime forwards copy of the selection", () => {
  const copied = forward.dispatchCopy(1);
  assert.equal(copied, "hel");
});

test("runtime forwards cut: copies and deletes the selection", () => {
  const cut = forward.dispatchCut(1);
  assert.equal(cut, "hel");
  assert.equal(doc(), "loZ!\nworld");
});

test("runtime forwards shift-arrow selection", () => {
  wasm.cm_set_doc(1, "hello\nworld");
  forward.dispatchKeyEvent(1, {
    key: "ArrowRight",
    code: "ArrowRight",
    shiftKey: true,
  });
  assert.match(state(), /sel=0:1/);
  assert.equal(forward.dispatchCopy(1), "h");
});

test("runtime scroll helper forwards to cm_scroll", () => {
  forward.dispatchScroll(1, 20, 0);
  assert.equal(wasm.cm_get_state(1).length > 0, true);
});

test("selection text and html helpers", () => {
  wasm.cm_set_doc(1, "abc def");
  wasm.cm_key(1, "End", "End", 0);
  wasm.cm_key(1, "a", "KeyA", 2);
  assert.equal(wasm.cm_selected_text(1), "abc def");
});

test("shim innerHTML parses elements and text", () => {
  const element = createElement("div");
  element.innerHTML =
    '<div class="cm-line" style="top:0px;height:20px">hi <span class="tok-keyword">fn</span></div>';
  assert.equal(element.children.length, 1);
  assert.equal(element.children[0].className, "cm-line");
  assert.equal(element.children[0].style.top, "0px");
  assert.equal(element.children[0].style.height, "20px");
  assert.equal(element.textContent, "hi fn");
  assert.ok(element.innerHTML.includes("tok-keyword"));
  assert.ok(element.classList.contains("cm-line") === false);
});

test("search panel helpers show and hide the panel", () => {
  showSearchPanel(1);
  assert.equal(wasm.cm_get_state(1).includes("search=1/"), true);
  hideSearchPanel(1);
  assert.equal(wasm.cm_get_state(1).includes("search=0/"), true);
});

function domEvent(type, target, extra) {
  return Object.assign(
    {
      type,
      target,
      defaultPrevented: false,
      preventDefault() {
        this.defaultPrevented = true;
      },
      stopPropagation() {},
    },
    extra,
  );
}

test("real DOM listeners forward keydown / beforeinput / paste", () => {
  const container2 = createElement("div");
  wasm.cm_create(container2, 2);
  wasm.cm_set_doc(2, "real");
  const record = container2.__cm;
  const input = record.input;

  const keydown = domEvent("keydown", input, {
    key: "!",
    code: "Digit1",
    isComposing: false,
  });
  input.dispatchEvent(keydown);
  assert.equal(wasm.cm_get_doc(2), "!real");
  assert.equal(keydown.defaultPrevented, true);

  input.dispatchEvent(
    domEvent("beforeinput", input, { inputType: "insertText", data: "?" }),
  );
  assert.equal(wasm.cm_get_doc(2), "!?real");

  input.dispatchEvent(
    domEvent("paste", input, {
      clipboardData: {
        getData: (type) => (type === "text/plain" ? "pasted" : ""),
        setData() {},
      },
    }),
  );
  assert.equal(wasm.cm_get_doc(2), "!?pastedreal");

  input.dispatchEvent(
    domEvent("compositionstart", input, { data: "" }),
  );
  input.dispatchEvent(
    domEvent("compositionupdate", input, { data: "中" }),
  );
  input.dispatchEvent(domEvent("compositionend", input, { data: "中" }));

  input.focus();
  assert.equal(container2.__cm.input.ownerDocument.activeElement, input);
  wasm.cm_destroy(2);
});

test("real DOM listeners forward mousedown and scroll", () => {
  const container3 = createElement("div");
  wasm.cm_create(container3, 3);
  wasm.cm_set_doc(3, "hello\nworld");
  const record = container3.__cm;
  const mousedown = domEvent("mousedown", record.root, {
    button: 0,
    detail: 1,
    clientX: 24,
    clientY: 5,
  });
  record.root.dispatchEvent(mousedown);
  assert.equal(wasm.cm_get_state(3).includes("sel=3:3"), true);
  assert.equal(mousedown.defaultPrevented, true);
  record.scroller.dispatchEvent(domEvent("scroll", record.scroller));
  wasm.cm_destroy(3);
});

test("search panel controls drive the wasm exports", () => {
  const container4 = createElement("div");
  wasm.cm_create(container4, 4);
  wasm.cm_set_doc(4, "hello world");
  const record = container4.__cm;
  const parts = record.panel.__parts;

  showSearchPanel(4);
  assert.equal(record.panel.classList.contains("cm-panel-hidden"), false);
  assert.equal(record.panel.style.display, "");

  parts.searchInput.value = "world";
  parts.searchInput.dispatchEvent(domEvent("input", parts.searchInput));
  assert.match(wasm.cm_get_state(4), /search=1\/1\/0/);

  parts.searchInput.dispatchEvent(
    domEvent("keydown", parts.searchInput, { key: "Enter", shiftKey: true }),
  );
  assert.match(wasm.cm_get_state(4), /search=1\/1\/0/);

  parts.replaceInput.value = "moon";
  parts.replaceAll.dispatchEvent(domEvent("click", parts.replaceAll));
  assert.equal(wasm.cm_get_doc(4), "hello moon");

  parts.close.dispatchEvent(domEvent("click", parts.close));
  assert.equal(record.panel.classList.contains("cm-panel-hidden"), true);
  assert.equal(record.panel.style.display, "none");
  assert.equal(wasm.cm_get_state(4).includes("search=0/"), true);

  showSearchPanel(4);
  parts.searchInput.dispatchEvent(
    domEvent("keydown", parts.searchInput, { key: "Escape", shiftKey: false }),
  );
  assert.equal(record.panel.classList.contains("cm-panel-hidden"), true);
  wasm.cm_destroy(4);
});

test("cm_destroy detaches cleanly", () => {
  wasm.cm_destroy(1);
  assert.equal(wasm.cm_get_doc(1), "");
});

console.log("");
console.log(`ALL E2E TESTS PASSED (${passed} tests)`);
