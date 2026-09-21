// browser.js
//
// Public browser entry point for CodeMoonBit. Import this from a
// `<script type="module">`:
//
//   import { createEditor } from "./js/browser.js";
//   const editor = await createEditor("#editor", { value: "fn main {}" });
//
// All `document` access happens inside functions, so importing this module in
// Node is safe (the Node e2e suite imports the runtime/shim instead).

import {
  applyOptionStyles,
  attachWasm,
  createDomImports,
  forgetEditor,
  getWasm,
  hideSearchPanel,
  onUpdate as subscribeUpdate,
  showSearchPanel,
} from "./dom_runtime.js";

const DEFAULT_WASM_CANDIDATES = [
  "../_build/wasm-gc/debug/build/main.wasm",
  "../_build/wasm-gc/debug/build/main/main.wasm",
];

const OPTION_KEYS = [
  "lineNumbers",
  "lineWrapping",
  "readOnly",
  "tabSize",
  "language",
  "theme",
  "font",
  "lineHeight",
];

// A single wasm instance is shared by every editor on the page: the wasm
// module keeps its own editor registry, so loading a second instance would
// silently break the first one.
let instancePromise = null;
let nextEditorId = 1;

async function loadInstance(wasmUrl) {
  if (instancePromise) return instancePromise;
  const attempt = (async () => {
    const response = await fetch(wasmUrl);
    if (!response.ok) {
      throw new Error(
        `CodeMoonBit: failed to load wasm from ${wasmUrl} (${response.status})`,
      );
    }
    const bytes = await response.arrayBuffer();
    const imports = {
      dom: createDomImports(),
      spectest: { print_char() {} },
    };
    const { instance } = await WebAssembly.instantiate(bytes, imports);
    if (typeof instance.exports._start === "function") {
      instance.exports._start();
    }
    return instance;
  })();
  instancePromise = attempt;
  try {
    return await attempt;
  } catch (error) {
    if (instancePromise === attempt) instancePromise = null;
    throw error;
  }
}

async function resolveInstance(wasmUrl) {
  if (wasmUrl) {
    return loadInstance(new URL(wasmUrl, import.meta.url).href);
  }
  let lastError = null;
  for (const candidate of DEFAULT_WASM_CANDIDATES) {
    const url = new URL(candidate, import.meta.url).href;
    try {
      return await loadInstance(url);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("CodeMoonBit: unable to locate main.wasm");
}

function resolveContainer(container) {
  if (typeof container === "string") {
    const found = globalThis.document
      ? globalThis.document.querySelector(container)
      : null;
    if (!found) {
      throw new Error(`CodeMoonBit: container selector not found: ${container}`);
    }
    return found;
  }
  if (!container || typeof container.appendChild !== "function") {
    throw new TypeError("CodeMoonBit: createEditor(container) needs an element");
  }
  return container;
}

/**
 * Create an editor inside `container`.
 *
 * @param {Element|string} container
 * @param {object} [options]
 * @returns {Promise<object>} editor handle
 */
export async function createEditor(container, options = {}) {
  const element = resolveContainer(container);
  const instance = await resolveInstance(options.wasmUrl);
  attachWasm(instance.exports);
  const wasm = getWasm();
  const id = nextEditorId;
  nextEditorId += 1;

  wasm.cm_create(element, id);

  const initialDoc = options.doc !== undefined ? options.doc : options.value;
  if (initialDoc !== undefined && initialDoc !== null) {
    wasm.cm_set_doc(id, String(initialDoc));
  }
  for (const key of OPTION_KEYS) {
    if (options[key] === undefined || options[key] === null) continue;
    const value = String(options[key]);
    wasm.cm_set_option(id, key, value);
    applyOptionStyles(id, key, value);
  }

  return {
    id,
    focus() {
      wasm.cm_focus(id);
    },
    destroy() {
      wasm.cm_destroy(id);
      forgetEditor(id);
    },
    getDoc() {
      return wasm.cm_get_doc(id);
    },
    setDoc(text) {
      wasm.cm_set_doc(id, String(text));
    },
    setSelection(anchor, head = anchor) {
      wasm.cm_set_selection(id, anchor | 0, head | 0);
    },
    getHTML() {
      return wasm.cm_get_html(id);
    },
    getSelection() {
      return JSON.parse(wasm.cm_get_selection(id));
    },
    getState() {
      return wasm.cm_get_state(id);
    },
    /**
     * Subscribe to document/selection updates. The callback is invoked once
     * asynchronously after the editor is created, then after every
     * state-changing operation (edits, selection changes, `setDoc`,
     * `setOption`). Returns an unsubscribe function.
     */
    onUpdate(callback) {
      if (typeof callback !== "function") return () => {};
      let notified = false;
      const unsubscribe = subscribeUpdate(id, () => {
        notified = true;
        callback();
      });
      Promise.resolve().then(() => {
        if (notified) return;
        notified = true;
        try {
          callback();
        } catch (error) {
          console.error("CodeMoonBit update listener error:", error);
        }
      });
      return unsubscribe;
    },
    openSearch() {
      showSearchPanel(id);
    },
    closeSearch() {
      hideSearchPanel(id);
    },
    searchNext() {
      wasm.cm_search_next(id);
    },
    searchPrev() {
      wasm.cm_search_prev(id);
    },
    replace(value) {
      wasm.cm_search_replace(id, String(value));
    },
    replaceAll(value) {
      wasm.cm_search_replace_all(id, String(value));
    },
    undo() {
      wasm.cm_undo(id);
    },
    redo() {
      wasm.cm_redo(id);
    },
    foldAll() {
      wasm.cm_fold_all(id);
    },
    unfoldAll() {
      wasm.cm_unfold_all(id);
    },
    foldClick(line) {
      wasm.cm_fold_click(id, line | 0);
    },
    key(key, code, mods) {
      return wasm.cm_key(id, String(key), String(code), mods | 0);
    },
    mouse(kind, x, y, detail, button) {
      return wasm.cm_mouse(id, kind | 0, x, y, button | 0, detail | 0);
    },
    paste(text) {
      wasm.cm_paste(id, String(text));
    },
    selectedText() {
      return wasm.cm_selected_text(id);
    },
    setDiagnostics(json) {
      wasm.cm_set_diagnostics(id, String(json));
    },
    setOption(key, value) {
      const encoded = String(value);
      wasm.cm_set_option(id, key, encoded);
      applyOptionStyles(id, key, encoded);
    },
  };
}

export default createEditor;
