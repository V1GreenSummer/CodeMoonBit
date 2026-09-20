// dom_runtime.js
//
// Host side of the CodeMoonBit wasm module. This module implements the
// `"dom"` wasm import namespace, builds the editor scaffold inside a
// container element and forwards DOM events to the wasm exports.
//
// It is intentionally environment agnostic: the only globals it touches are
// `document/window` (through lazy lookups) so that the same file can run in a
// browser or against the Node shim in `shim_dom.js`.

// ---------------------------------------------------------------------------
// wasm handle
// ---------------------------------------------------------------------------

let wasmExports = null;

/** Remember the instantiated wasm exports. Returns them for convenience. */
export function attachWasm(exports) {
  wasmExports = exports;
  return wasmExports;
}

/** The wasm exports attached with `attachWasm`, or `null`. */
export function getWasm() {
  return wasmExports;
}

function requireWasm() {
  if (!wasmExports) {
    throw new Error("CodeMoonBit: attachWasm(exports) must be called first");
  }
  return wasmExports;
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function doc() {
  const d = globalThis.document;
  if (!d) {
    throw new Error(
      "CodeMoonBit: no document available; use browser.js in a browser or shim_dom.js in Node",
    );
  }
  return d;
}

function createEl(tag) {
  return doc().createElement(tag || "div");
}

function num(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function kebabToCamel(prop) {
  return prop.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
}

function setStyleValue(element, prop, value) {
  if (!element) return;
  if (!element.style) element.style = {};
  const p = prop.indexOf("-") >= 0 ? kebabToCamel(prop) : prop;
  element.style[p] = value;
}

function setStyles(element, styles) {
  for (const key of Object.keys(styles)) {
    setStyleValue(element, key, styles[key]);
  }
}

function preventEvent(event) {
  if (event && typeof event.preventDefault === "function") event.preventDefault();
}

function stopEvent(event) {
  if (!event) return;
  if (typeof event.stopPropagation === "function") event.stopPropagation();
  if (typeof event.preventDefault === "function") event.preventDefault();
}

function isInsidePanel(target, record) {
  let node = target;
  while (node) {
    if (node === record.panel) return true;
    node = node.parentNode || null;
  }
  return false;
}

function closestWithClass(target, className) {
  let node = target;
  while (node) {
    if (node.classList && node.classList.contains(className)) return node;
    node = node.parentNode || null;
  }
  return null;
}

function addListener(record, element, type, handler) {
  if (!element || typeof element.addEventListener !== "function") return;
  element.addEventListener(type, handler);
  record.listeners.push([element, type, handler]);
}

function removeAllListeners(record) {
  for (const [element, type, handler] of record.listeners) {
    if (element && typeof element.removeEventListener === "function") {
      element.removeEventListener(type, handler);
    }
  }
  record.listeners.length = 0;
  removeWindowDrag(record);
}

function callExport(name, ...args) {
  const wasm = wasmExports;
  if (!wasm) return undefined;
  const fn = wasm[name];
  if (typeof fn !== "function") return undefined;
  return fn(...args);
}

let reportedError = null;

function reportError(error) {
  // Only report the first runtime error to avoid flooding the console while
  // still making mistakes visible.
  if (reportedError === null) {
    reportedError = error;
    if (typeof console !== "undefined" && console.error) {
      console.error("CodeMoonBit runtime error:", error);
    }
  }
}

// ---------------------------------------------------------------------------
// string builders
// ---------------------------------------------------------------------------

const builders = new Map();
let nextBuilderHandle = 1;

function codeUnitsToString(units) {
  let out = "";
  const chunk = 8192;
  for (let i = 0; i < units.length; i += chunk) {
    out += String.fromCharCode.apply(null, units.slice(i, i + chunk));
  }
  return out;
}

// ---------------------------------------------------------------------------
// text measurement
// ---------------------------------------------------------------------------

const widthCache = new Map();
let measureContext = null;
let measureContextTried = false;

function estimateWidth(text) {
  let units = 0;
  for (let i = 0; i < text.length; i = i + 1) {
    const code = text.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      units += 1;
      i += 1;
    } else {
      units += 1;
    }
  }
  return units * 8;
}

function measureWidth(font, text) {
  if (!text) return 0;
  const key = String(font) + "\u0000" + text;
  const cached = widthCache.get(key);
  if (cached !== undefined) return cached;
  let width = null;
  try {
    if (!measureContextTried) {
      measureContextTried = true;
      const document = globalThis.document;
      if (document && typeof document.createElement === "function") {
        const canvas = document.createElement("canvas");
        if (canvas && typeof canvas.getContext === "function") {
          const context = canvas.getContext("2d");
          if (context && typeof context.measureText === "function") {
            measureContext = context;
          }
        }
      }
    }
    if (measureContext) {
      measureContext.font = String(font);
      const metrics = measureContext.measureText(text);
      if (metrics && typeof metrics.width === "number") width = metrics.width;
    }
  } catch (error) {
    reportError(error);
  }
  if (width === null || !(width >= 0)) width = estimateWidth(text);
  widthCache.set(key, width);
  return width;
}

// ---------------------------------------------------------------------------
// scaffold
// ---------------------------------------------------------------------------

const editors = new Map();

function buildPanel(panel) {
  const searchInput = createEl("input");
  searchInput.className = "cm-search-input";
  searchInput.setAttribute("placeholder", "Search");
  searchInput.setAttribute("title", "Search (Ctrl/\u2318-F)");

  const prev = createEl("button");
  prev.className = "cm-search-prev";
  prev.setAttribute("type", "button");
  prev.setAttribute("title", "Previous match (Shift-Enter)");
  prev.textContent = "\u2191";

  const next = createEl("button");
  next.className = "cm-search-next";
  next.setAttribute("type", "button");
  next.setAttribute("title", "Next match (Enter)");
  next.textContent = "\u2193";

  const count = createEl("span");
  count.className = "cm-search-count cm-search-count-empty";
  count.textContent = "0 / 0";
  count.setAttribute("title", "Current match / total matches");

  const replaceInput = createEl("input");
  replaceInput.className = "cm-search-replace";
  replaceInput.setAttribute("placeholder", "Replace");
  replaceInput.setAttribute("title", "Replacement text");

  const replaceOne = createEl("button");
  replaceOne.className = "cm-search-replace-one";
  replaceOne.setAttribute("type", "button");
  replaceOne.setAttribute("title", "Replace current match");
  replaceOne.textContent = "Replace";

  const replaceAll = createEl("button");
  replaceAll.className = "cm-search-replace-all";
  replaceAll.setAttribute("type", "button");
  replaceAll.setAttribute("title", "Replace all matches");
  replaceAll.textContent = "Replace All";

  const close = createEl("button");
  close.className = "cm-search-close";
  close.setAttribute("type", "button");
  close.setAttribute("title", "Close (Escape)");
  close.textContent = "\u00d7";

  for (const child of [
    searchInput,
    prev,
    next,
    count,
    replaceInput,
    replaceOne,
    replaceAll,
    close,
  ]) {
    panel.appendChild(child);
  }

  panel.__parts = {
    searchInput,
    prev,
    next,
    count,
    replaceInput,
    replaceOne,
    replaceAll,
    close,
  };
}

function refreshContentSize(content) {
  let maxY = 0;
  const children = content.children || [];
  for (let i = 0; i < children.length; i = i + 1) {
    const child = children[i];
    const style = child.style || {};
    const top = parseFloat(style.top);
    const height = parseFloat(style.height);
    const bottom = (Number.isFinite(top) ? top : 0) + (Number.isFinite(height) ? height : 0);
    if (bottom > maxY) maxY = bottom;
  }
  content.style.height = maxY + "px";
  content.style.minHeight = maxY + "px";
}

function createScaffold(container, editorId) {
  const root = createEl("div");
  root.className = "cm-editor";
  setStyles(root, {
    position: "relative",
    overflow: "hidden",
    display: "flex",
  });

  const gutters = createEl("div");
  gutters.className = "cm-gutters";
  setStyles(gutters, {
    position: "relative",
    overflow: "hidden",
    flex: "0 0 auto",
    userSelect: "none",
    WebkitUserSelect: "none",
  });

  const scroller = createEl("div");
  scroller.className = "cm-scroller";
  setStyles(scroller, {
    position: "relative",
    overflow: "auto",
    flex: "1 1 auto",
    minWidth: "0",
  });

  const content = createEl("div");
  content.className = "cm-content";
  setStyles(content, {
    position: "absolute",
    top: "0",
    left: "4px",
    whiteSpace: "pre",
  });
  content.__cmRole = "content";

  const input = createEl("textarea");
  input.className = "cm-input";
  setStyles(input, {
    position: "absolute",
    opacity: "0.01",
    width: "1px",
    height: "1px",
    left: "0",
    top: "0",
    zIndex: "10",
    border: "none",
    padding: "0",
    margin: "0",
    resize: "none",
    outline: "none",
  });
  input.setAttribute("autocomplete", "off");
  input.setAttribute("autocorrect", "off");
  input.setAttribute("autocapitalize", "off");
  input.setAttribute("spellcheck", "false");
  input.setAttribute("wrap", "off");
  input.wrap = "off";
  input.value = "";

  const panel = createEl("div");
  panel.className = "cm-panel cm-panel-hidden";
  setStyleValue(panel, "display", "none");
  buildPanel(panel);

  const measure = createEl("span");
  measure.className = "cm-measure";
  setStyles(measure, {
    position: "absolute",
    visibility: "hidden",
    pointerEvents: "none",
    whiteSpace: "pre",
    left: "-9999px",
    top: "0",
  });

  root.appendChild(gutters);
  root.appendChild(scroller);
  root.appendChild(panel);
  root.appendChild(measure);
  scroller.appendChild(content);
  scroller.appendChild(input);
  container.appendChild(root);

  const record = {
    container,
    root,
    gutters,
    scroller,
    content,
    input,
    panel,
    measure,
    editorId: editorId == null ? null : editorId,
    listeners: [],
    listenersInstalled: false,
    windowDragInstalled: false,
    dragging: false,
    scrollScheduled: null,
    lineWrapping: false,
  };

  for (const element of [root, gutters, scroller, content, input, panel, measure]) {
    element.__cmRecord = record;
  }
  container.__cm = record;
  return record;
}

function ensureScaffold(container, editorId) {
  if (container.__cm) {
    if (editorId != null) container.__cm.editorId = editorId;
    return container.__cm;
  }
  return createScaffold(container, editorId);
}

// ---------------------------------------------------------------------------
// search panel
// ---------------------------------------------------------------------------

function setPanelVisible(record, visible) {
  if (!record || !record.panel) return;
  if (record.panel.classList) {
    record.panel.classList.toggle("cm-panel-hidden", !visible);
  }
  setStyleValue(record.panel, "display", visible ? "" : "none");
}

function setFocused(record, focused) {
  if (!record || !record.root || !record.root.classList) return;
  record.root.classList.toggle("cm-focused", !!focused);
}

export function syncSearchPanel(id) {
  const record = editors.get(id);
  if (!record) return;
  const state = callExport("cm_get_state", id);
  const open = typeof state === "string" && /(?:^|;)search=1\//.test(state);
  setPanelVisible(record, open);
  const parts = record.panel && record.panel.__parts;
  if (!parts || !parts.count) return;
  let total = 0;
  let current = 0;
  const parsed =
    typeof state === "string"
      ? state.match(/(?:^|;)search=(\d+)\/(\d+)\/(\d+)/)
      : null;
  if (parsed) {
    total = Number(parsed[2]);
    current = Number(parsed[3]);
  }
  if (total > 0 && current >= 0 && current < total) {
    parts.count.textContent = `${current + 1} / ${total}`;
    if (parts.count.classList) parts.count.classList.remove("cm-search-count-empty");
  } else {
    parts.count.textContent = "0 / 0";
    if (parts.count.classList) parts.count.classList.add("cm-search-count-empty");
  }
}

export function showSearchPanel(id) {
  const record = editors.get(id);
  callExport("cm_search_open", id);
  if (!record) return;
  syncSearchPanel(id);
  const parts = record.panel.__parts;
  if (parts && parts.searchInput && typeof parts.searchInput.focus === "function") {
    parts.searchInput.focus();
  }
}

export function hideSearchPanel(id) {
  const record = editors.get(id);
  callExport("cm_search_close", id);
  if (!record) return;
  setPanelVisible(record, false);
  if (record.input && typeof record.input.focus === "function") {
    record.input.focus();
  }
}

/** Forget an editor id (used by the public `destroy()` helper). */
export function forgetEditor(id) {
  const record = editors.get(id);
  if (record) {
    removeAllListeners(record);
    editors.delete(id);
  }
  updateListeners.delete(id);
}

// ---------------------------------------------------------------------------
// host subscriptions
// ---------------------------------------------------------------------------

const updateListeners = new Map();

/**
 * Register `callback` to run after wasm reports a state change for `id`
 * (edits, selection changes, `set_doc`, `set_state`). Returns an unsubscribe
 * function. Exceptions thrown by a listener are reported and do not interrupt
 * the editor or the other listeners.
 */
export function onUpdate(id, callback) {
  if (typeof callback !== "function") return () => {};
  let listeners = updateListeners.get(id);
  if (!listeners) {
    listeners = [];
    updateListeners.set(id, listeners);
  }
  listeners.push(callback);
  return () => {
    const current = updateListeners.get(id);
    if (!current) return;
    const index = current.indexOf(callback);
    if (index >= 0) current.splice(index, 1);
    if (current.length === 0) updateListeners.delete(id);
  };
}

function notifyUpdate(id) {
  const listeners = updateListeners.get(id);
  if (!listeners || listeners.length === 0) return;
  for (const listener of listeners.slice()) {
    try {
      listener();
    } catch (error) {
      reportError(error);
    }
  }
}

/** Apply JS-only side effects of an option (scroller white-space, ...). */
export function applyOptionStyles(id, key, value) {
  const record = editors.get(id);
  if (!record) return;
  const truthy = value === true || value === "true" || value === "1";
  if (key === "lineWrapping") {
    record.lineWrapping = truthy;
    setStyleValue(record.scroller, "whiteSpace", truthy ? "pre-wrap" : "pre");
    setStyleValue(record.content, "whiteSpace", truthy ? "pre-wrap" : "pre");
  } else if (key === "lineNumbers") {
    setStyleValue(record.gutters, "display", truthy ? "" : "none");
  } else if (key === "font") {
    setStyleValue(record.scroller, "font", value);
    setStyleValue(record.content, "font", value);
    setStyleValue(record.measure, "font", value);
  } else if (key === "lineHeight") {
    setStyleValue(record.content, "lineHeight", value + "px");
  } else if (key === "theme") {
    if (record.root.classList) {
      record.root.classList.toggle("cm-theme-dark", value === "dark");
      record.root.classList.toggle("cm-theme-light", value !== "dark");
    }
    record.root.setAttribute("data-theme", value);
  }
}

// ---------------------------------------------------------------------------
// event handlers
// ---------------------------------------------------------------------------

const SCROLL_KEYS = new Set([
  "ArrowUp",
  "ArrowDown",
  "ArrowLeft",
  "ArrowRight",
  "PageUp",
  "PageDown",
  "Home",
  "End",
  " ",
]);

// Platform modifier bit: tells the wasm keymap that `Mod-` bindings should
// match the meta (Cmd) key instead of ctrl. Mirrors `mod_platform` in
// `input/keymap.mbt`.
const PLATFORM_MOD = 16;

let applePlatform = null;

function isApplePlatform() {
  if (applePlatform !== null) return applePlatform;
  applePlatform = false;
  try {
    const nav = globalThis.navigator;
    if (nav) {
      const data = nav.userAgentData;
      if (data && typeof data.platform === "string" && data.platform.length > 0) {
        applePlatform = data.platform.indexOf("Mac") >= 0;
      } else if (typeof nav.platform === "string" && nav.platform.length > 0) {
        applePlatform = nav.platform.indexOf("Mac") === 0;
      } else if (typeof nav.userAgent === "string") {
        applePlatform = nav.userAgent.indexOf("Mac") >= 0;
      }
    }
  } catch (error) {
    reportError(error);
  }
  return applePlatform;
}

function modsFromEvent(event) {
  return (
    (event.shiftKey ? 1 : 0) |
    (event.ctrlKey ? 2 : 0) |
    (event.altKey ? 4 : 0) |
    (event.metaKey ? 8 : 0) |
    (isApplePlatform() ? PLATFORM_MOD : 0)
  );
}

function handleKeyDown(record, event) {
  if (record.editorId == null || !wasmExports) return 0;
  if (isInsidePanel(event.target, record)) {
    if (event.key === "Escape") {
      stopEvent(event);
      hideSearchPanel(record.editorId);
    }
    return 0;
  }
  if (event.isComposing && event.key !== "Escape") return 0;
  let handled = 0;
  try {
    handled = requireWasm().cm_key(
      record.editorId,
      event.key || "",
      event.code || "",
      modsFromEvent(event),
    );
  } catch (error) {
    reportError(error);
  }
  const targetIsInput = event.target === record.input;
  if (handled === 1 || (targetIsInput && SCROLL_KEYS.has(event.key))) {
    preventEvent(event);
  }
  syncSearchPanel(record.editorId);
  return handled;
}

// Coordinates relative to the text origin: content coordinates for y, but x is
// measured from the line box minus its horizontal padding so a click lands on
// the character actually under the pointer.
function eventContentCoords(record, event) {
  const rect = record.content.getBoundingClientRect
    ? record.content.getBoundingClientRect()
    : { left: 0, top: 0 };
  let x = num(event.clientX) - num(rect.left);
  const y = num(event.clientY) - num(rect.top);
  const target = event.target;
  if (target && typeof target.closest === "function") {
    const line = target.closest(".cm-line");
    if (line && typeof line.getBoundingClientRect === "function") {
      const lineRect = line.getBoundingClientRect();
      let padding = 0;
      if (typeof getComputedStyle === "function") {
        padding = parseFloat(getComputedStyle(line).paddingLeft) || 0;
      }
      x = num(event.clientX) - num(lineRect.left) - padding;
    }
  }
  return { x, y };
}

function forwardDrag(record, event, kind) {
  if (record.editorId == null || !wasmExports) return;
  const { x, y } = eventContentCoords(record, event);
  try {
    requireWasm().cm_mouse(record.editorId, kind, x, y, 0, 0);
  } catch (error) {
    reportError(error);
  }
}

function removeWindowDrag(record) {
  stopDragAutoScroll(record);
  if (!record.windowDragInstalled) return;
  const win = globalThis.window || globalThis;
  if (typeof win.removeEventListener === "function") {
    win.removeEventListener("mousemove", record.onWindowMove);
    win.removeEventListener("mouseup", record.onWindowUp);
  }
  record.windowDragInstalled = false;
}

function installWindowDrag(record) {
  if (record.windowDragInstalled) return;
  const win = globalThis.window || globalThis;
  if (typeof win.addEventListener !== "function") return;
  record.onWindowMove = (event) => {
    if (!record.dragging) return;
    record.lastDragEvent = event;
    forwardDrag(record, event, 1);
    preventEvent(event);
  };
  record.onWindowUp = (event) => {
    if (!record.dragging) return;
    record.dragging = false;
    record.lastDragEvent = event;
    forwardDrag(record, event, 2);
    removeWindowDrag(record);
  };
  win.addEventListener("mousemove", record.onWindowMove);
  win.addEventListener("mouseup", record.onWindowUp);
  record.windowDragInstalled = true;
}

// Keeps extending the selection while the pointer is held outside the
// viewport, so dragging past the visible area scrolls the document.
function startDragAutoScroll(record) {
  if (record.dragTimer != null) return;
  if (typeof globalThis.setInterval !== "function") return;
  record.dragTimer = globalThis.setInterval(() => {
    if (!record.dragging || !record.lastDragEvent) {
      stopDragAutoScroll(record);
      return;
    }
    const event = record.lastDragEvent;
    const scroller = record.scroller;
    if (!scroller || typeof scroller.getBoundingClientRect !== "function") return;
    const rect = scroller.getBoundingClientRect();
    const cx = num(event.clientX);
    const cy = num(event.clientY);
    const outside =
      cy < rect.top || cy > rect.bottom || cx < rect.left || cx > rect.right;
    if (outside) {
      forwardDrag(record, event, 1);
    }
  }, 50);
}

function stopDragAutoScroll(record) {
  if (record.dragTimer == null) return;
  if (typeof globalThis.clearInterval === "function") {
    globalThis.clearInterval(record.dragTimer);
  }
  record.dragTimer = null;
}

function handleMouseDown(record, event) {
  if (record.editorId == null || !wasmExports) return;
  if (event.button !== 0 && event.button !== undefined) return;
  if (isInsidePanel(event.target, record)) return;
  const fold = closestWithClass(event.target, "cm-fold");
  if (fold) {
    let line = 0;
    if (typeof fold.getAttribute === "function") {
      line = parseInt(fold.getAttribute("data-line") || "0", 10) || 0;
    }
    try {
      requireWasm().cm_fold_click(record.editorId, line);
    } catch (error) {
      reportError(error);
    }
    preventEvent(event);
    syncSearchPanel(record.editorId);
    return;
  }
  if (record.input && typeof record.input.focus === "function") {
    record.input.focus();
  }
  const { x, y } = eventContentCoords(record, event);
  const detail = event.detail ? event.detail : 1;
  try {
    requireWasm().cm_mouse(record.editorId, 0, x, y, 0, detail);
  } catch (error) {
    reportError(error);
  }
  record.dragging = true;
  record.lastDragEvent = event;
  installWindowDrag(record);
  startDragAutoScroll(record);
  preventEvent(event);
  syncSearchPanel(record.editorId);
}

function handleBeforeInput(record, event) {
  if (record.editorId == null || !wasmExports) return 0;
  const type = event.inputType || "";
  const data = event.data;
  // `insertCompositionText` / `insertFromComposition` are the browser's view
  // of an IME session whose single source of truth is the
  // compositionstart/update/end sequence, so they are never forwarded here.
  if (type === "insertText" && data) {
    preventEvent(event);
    let handled = 0;
    try {
      handled = requireWasm().cm_input(record.editorId, data) | 0;
    } catch (error) {
      reportError(error);
    }
    if (handled === 1) {
      try {
        record.input.value = "";
      } catch (error) {
        reportError(error);
      }
    }
    syncSearchPanel(record.editorId);
    return handled;
  }
  return 0;
}

function clipboardText(event) {
  try {
    if (event.clipboardData && typeof event.clipboardData.getData === "function") {
      return event.clipboardData.getData("text/plain") || "";
    }
  } catch (error) {
    reportError(error);
  }
  return "";
}

function setClipboardText(event, text) {
  try {
    if (event.clipboardData && typeof event.clipboardData.setData === "function") {
      event.clipboardData.setData("text/plain", text);
    }
  } catch (error) {
    reportError(error);
  }
}

function handlePaste(record, event) {
  if (record.editorId == null || !wasmExports) return;
  preventEvent(event);
  const text = clipboardText(event);
  try {
    requireWasm().cm_paste(record.editorId, text);
  } catch (error) {
    reportError(error);
  }
  syncSearchPanel(record.editorId);
}

function selectedTextOf(record) {
  if (record.editorId == null || !wasmExports) return "";
  const text = callExport("cm_selected_text", record.editorId);
  return typeof text === "string" ? text : "";
}

function handleCopy(record, event) {
  if (record.editorId == null || !wasmExports) return;
  preventEvent(event);
  setClipboardText(event, selectedTextOf(record));
}

function handleCut(record, event) {
  if (record.editorId == null || !wasmExports) return;
  preventEvent(event);
  const text = selectedTextOf(record);
  setClipboardText(event, text);
  // `Backspace` deletes the current selection through the keymap; only do it
  // when there is a selection so a cut with a collapsed cursor is a no-op.
  if (text.length > 0) {
    try {
      requireWasm().cm_key(record.editorId, "Backspace", "Backspace", 0);
    } catch (error) {
      reportError(error);
    }
  }
  syncSearchPanel(record.editorId);
}

function handleComposition(record, phase, event) {
  if (record.editorId == null || !wasmExports) return;
  const text = phase === 1 || phase === 2 ? event.data || "" : "";
  try {
    requireWasm().cm_composition(record.editorId, phase, text);
  } catch (error) {
    reportError(error);
  }
  if (phase === 2) {
    try {
      record.input.value = "";
    } catch (error) {
      reportError(error);
    }
  }
}

function applyScroll(record) {
  if (record.editorId == null || !wasmExports) return;
  const top = num(record.scroller.scrollTop);
  const left = num(record.scroller.scrollLeft);
  if (record.gutters) record.gutters.scrollTop = top;
  try {
    requireWasm().cm_scroll(record.editorId, top, left);
  } catch (error) {
    reportError(error);
  }
}

function handleScroll(record) {
  if (record.scrollScheduled != null) return;
  const schedule =
    typeof globalThis.requestAnimationFrame === "function"
      ? globalThis.requestAnimationFrame
      : (callback) => setTimeout(callback, 0);
  record.scrollScheduled = schedule(() => {
    record.scrollScheduled = null;
    applyScroll(record);
  });
}

function installListeners(record) {
  if (record.listenersInstalled) return;
  record.listenersInstalled = true;

  addListener(record, record.root, "keydown", (event) => {
    handleKeyDown(record, event);
  });

  addListener(record, record.root, "mousedown", (event) => {
    handleMouseDown(record, event);
  });

  addListener(record, record.input, "beforeinput", (event) => {
    handleBeforeInput(record, event);
  });

  addListener(record, record.input, "paste", (event) => {
    handlePaste(record, event);
  });

  addListener(record, record.input, "copy", (event) => {
    handleCopy(record, event);
  });

  addListener(record, record.input, "cut", (event) => {
    handleCut(record, event);
  });

  addListener(record, record.input, "focus", () => {
    setFocused(record, true);
    callExport("cm_focus_event", record.editorId, 1);
  });

  addListener(record, record.input, "blur", () => {
    setFocused(record, false);
    callExport("cm_focus_event", record.editorId, 0);
  });

  addListener(record, record.input, "compositionstart", (event) => {
    handleComposition(record, 0, event);
  });

  addListener(record, record.input, "compositionupdate", (event) => {
    handleComposition(record, 1, event);
  });

  addListener(record, record.input, "compositionend", (event) => {
    handleComposition(record, 2, event);
  });

  addListener(record, record.scroller, "scroll", () => {
    handleScroll(record);
  });

  const parts = record.panel.__parts;
  if (parts) {
    addListener(record, parts.searchInput, "input", () => {
      if (record.editorId == null) return;
      callExport("cm_search_query", record.editorId, parts.searchInput.value);
      syncSearchPanel(record.editorId);
    });
    addListener(record, parts.searchInput, "keydown", (event) => {
      if (record.editorId == null) return;
      if (event.key === "Enter") {
        stopEvent(event);
        callExport(
          event.shiftKey ? "cm_search_prev" : "cm_search_next",
          record.editorId,
        );
        syncSearchPanel(record.editorId);
      } else if (event.key === "Escape") {
        stopEvent(event);
        hideSearchPanel(record.editorId);
      }
    });
    addListener(record, parts.prev, "click", (event) => {
      stopEvent(event);
      callExport("cm_search_prev", record.editorId);
      syncSearchPanel(record.editorId);
    });
    addListener(record, parts.next, "click", (event) => {
      stopEvent(event);
      callExport("cm_search_next", record.editorId);
      syncSearchPanel(record.editorId);
    });
    addListener(record, parts.replaceOne, "click", (event) => {
      stopEvent(event);
      callExport("cm_search_replace", record.editorId, parts.replaceInput.value);
      syncSearchPanel(record.editorId);
    });
    addListener(record, parts.replaceAll, "click", (event) => {
      stopEvent(event);
      callExport("cm_search_replace_all", record.editorId, parts.replaceInput.value);
      syncSearchPanel(record.editorId);
    });
    addListener(record, parts.close, "click", (event) => {
      stopEvent(event);
      hideSearchPanel(record.editorId);
    });
  }
}

// ---------------------------------------------------------------------------
// DOM imports (module "dom")
// ---------------------------------------------------------------------------

export function createDomImports() {
  return {
    sb_new() {
      const handle = nextBuilderHandle;
      nextBuilderHandle += 1;
      builders.set(handle, []);
      return handle;
    },
    sb_push(handle, code) {
      const units = builders.get(handle);
      if (units) units.push(code & 0xffff);
    },
    sb_clear(handle) {
      const units = builders.get(handle);
      if (units) units.length = 0;
    },
    sb_finish(handle) {
      const units = builders.get(handle);
      builders.delete(handle);
      return units ? codeUnitsToString(units) : "";
    },
    js_len(value) {
      return typeof value === "string" ? value.length : 0;
    },
    js_char(value, index) {
      if (typeof value !== "string") return 0;
      const code = value.charCodeAt(index);
      return Number.isNaN(code) ? 0 : code;
    },
    create(tag) {
      return createEl(typeof tag === "string" && tag ? tag : "div");
    },
    append(parent, child) {
      if (parent && child && typeof parent.appendChild === "function") {
        parent.appendChild(child);
      }
    },
    set_html(element, html) {
      if (!element) return;
      element.innerHTML = html == null ? "" : html;
      if (element.__cmRole === "content") refreshContentSize(element);
    },
    set_text(element, text) {
      if (!element) return;
      element.textContent = text == null ? "" : text;
    },
    get_text(element) {
      if (!element) return "";
      const text = element.textContent;
      return typeof text === "string" ? text : "";
    },
    get_html(element) {
      if (!element) return "";
      const html = element.innerHTML;
      return typeof html === "string" ? html : "";
    },
    set_class(element, cls) {
      if (!element) return;
      element.className = cls == null ? "" : cls;
    },
    add_class(element, cls) {
      if (element && element.classList && typeof element.classList.add === "function") {
        element.classList.add(cls);
      }
    },
    remove_class(element, cls) {
      if (element && element.classList && typeof element.classList.remove === "function") {
        element.classList.remove(cls);
      }
    },
    set_style(element, prop, value) {
      setStyleValue(element, prop, value);
    },
    set_attr(element, name, value) {
      if (!element) return;
      if (typeof element.setAttribute === "function") {
        element.setAttribute(name, value == null ? "" : value);
      } else {
        element[name] = value;
      }
    },
    remove_attr(element, name) {
      if (!element) return;
      if (typeof element.removeAttribute === "function") {
        element.removeAttribute(name);
      } else {
        delete element[name];
      }
    },
    part(container, name) {
      const record = ensureScaffold(container, null);
      const key = typeof name === "string" ? name : "container";
      switch (key) {
        case "scroller":
          return record.scroller;
        case "content":
          return record.content;
        case "gutter":
        case "gutters":
          return record.gutters;
        case "input":
          return record.input;
        case "measure":
          return record.measure;
        case "panel":
          return record.panel;
        case "container":
        default:
          return record.root;
      }
    },
    set_scroll(element, top, left) {
      setScroll(element, top, left);
    },
    scroll_top(element) {
      return element ? num(element.scrollTop) : 0;
    },
    scroll_left(element) {
      return element ? num(element.scrollLeft) : 0;
    },
    client_width(element) {
      return element ? num(element.clientWidth) : 0;
    },
    client_height(element) {
      return element ? num(element.clientHeight) : 0;
    },
    scroll_height(element) {
      return element ? num(element.scrollHeight) : 0;
    },
    scroll_width(element) {
      return element ? num(element.scrollWidth) : 0;
    },
    focus(element) {
      focusElement(element);
    },
    blur(element) {
      if (element && typeof element.blur === "function") element.blur();
    },
    measure_width(font, text) {
      return measureWidth(font, text == null ? "" : text);
    },
    attach(container, editorId) {
      const record = ensureScaffold(container, editorId);
      record.editorId = editorId;
      editors.set(editorId, record);
      installListeners(record);
    },
    detach(container) {
      const record = container ? container.__cm : null;
      if (!record) return;
      removeAllListeners(record);
      if (record.editorId != null) editors.delete(record.editorId);
      if (record.root.parentNode && typeof record.root.parentNode.removeChild === "function") {
        record.root.parentNode.removeChild(record.root);
      }
      if (container) delete container.__cm;
    },
    request_measure() {
      // Rendered measurements happen lazily inside `set_html`; nothing to do.
    },
    notify_update(editorId) {
      syncSearchPanel(editorId);
      notifyUpdate(editorId);
    },
    log(message) {
      if (typeof console !== "undefined" && console.log) console.log(message);
    },
  };
}

function setScroll(element, top, left) {
  if (!element) return;
  element.scrollTop = num(top);
  element.scrollLeft = num(left);
  const record = element.__cmRecord;
  if (record && record.gutters) record.gutters.scrollTop = num(top);
}

function focusElement(element) {
  if (!element) return;
  const record = element.__cmRecord;
  if (record && record.input && record.input !== element) {
    if (typeof record.input.focus === "function") record.input.focus();
    return;
  }
  if (typeof element.focus === "function") element.focus();
}

// ---------------------------------------------------------------------------
// test forwarding hooks
// ---------------------------------------------------------------------------

function fakeEvent(fields) {
  return Object.assign(
    {
      defaultPrevented: false,
      _stopped: false,
      preventDefault() {
        this.defaultPrevented = true;
      },
      stopPropagation() {
        this._stopped = true;
      },
    },
    fields,
  );
}

/**
 * Entry points used by the Node shim and the e2e suite to drive the same code
 * paths as real DOM listeners without building a full event system.
 */
export const __testForward = {
  key(id, key, code, mods) {
    const record = editors.get(id);
    if (!record) return 0;
    const event = fakeEvent({
      type: "keydown",
      key,
      code,
      shiftKey: !!(mods & 1),
      ctrlKey: !!(mods & 2),
      altKey: !!(mods & 4),
      metaKey: !!(mods & 8),
      isComposing: false,
      target: record.input,
    });
    return handleKeyDown(record, event);
  },
  keyEvent(id, fields) {
    const record = editors.get(id);
    if (!record) return 0;
    const event = fakeEvent(Object.assign({ target: record.input }, fields));
    return handleKeyDown(record, event);
  },
  mouse(id, kind, x, y, detail) {
    const record = editors.get(id);
    if (!record || !wasmExports) return 0;
    if (kind === 0) record.dragging = true;
    let handled = 0;
    try {
      handled = requireWasm().cm_mouse(id, kind, x, y, 0, detail || 0) | 0;
    } catch (error) {
      reportError(error);
    }
    if (kind === 2) record.dragging = false;
    syncSearchPanel(id);
    return handled;
  },
  beforeInput(id, text, inputType) {
    const record = editors.get(id);
    if (!record) return 0;
    const event = fakeEvent({
      type: "beforeinput",
      inputType: inputType || "insertText",
      data: text,
      target: record.input,
    });
    return handleBeforeInput(record, event);
  },
  composition(id, phase, text) {
    const record = editors.get(id);
    if (!record) return;
    const event = fakeEvent({
      type: "composition" + (phase === 0 ? "start" : phase === 1 ? "update" : "end"),
      data: text == null ? "" : text,
      target: record.input,
    });
    handleComposition(record, phase, event);
  },
  paste(id, text) {
    const record = editors.get(id);
    if (!record) return;
    const event = fakeEvent({
      type: "paste",
      target: record.input,
      clipboardData: {
        getData(type) {
          return type === "text/plain" ? text : "";
        },
        setData() {},
      },
    });
    handlePaste(record, event);
  },
  copy(id) {
    const record = editors.get(id);
    if (!record) return "";
    let captured = "";
    const event = fakeEvent({
      type: "copy",
      target: record.input,
      clipboardData: {
        getData() {
          return "";
        },
        setData(type, value) {
          if (type === "text/plain") captured = value;
        },
      },
    });
    handleCopy(record, event);
    return captured;
  },
  cut(id) {
    const record = editors.get(id);
    if (!record) return "";
    let captured = "";
    const event = fakeEvent({
      type: "cut",
      target: record.input,
      clipboardData: {
        getData() {
          return "";
        },
        setData(type, value) {
          if (type === "text/plain") captured = value;
        },
      },
    });
    handleCut(record, event);
    return captured;
  },
  scroll(id, top, left) {
    const record = editors.get(id);
    if (!record) return;
    record.scroller.scrollTop = top;
    record.scroller.scrollLeft = left;
    applyScroll(record);
  },
  focus(id, focused) {
    const record = editors.get(id);
    if (!record) return;
    setFocused(record, focused);
    callExport("cm_focus_event", id, focused ? 1 : 0);
  },
};
