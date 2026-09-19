// shim_dom.js
//
// Minimal fake DOM for running `dom_runtime.js` (and therefore the
// CodeMoonBit wasm module) under Node. It is *not* a browser polyfill: it only
// implements the small surface the runtime touches, plus enough `innerHTML`
// parsing for the e2e assertions.
//
// Node-only: this module imports `node:fs` and `node:url`.

import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { createDomImports, attachWasm, __testForward, onUpdate } from "./dom_runtime.js";

const VOID_TAGS = new Set([
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "param",
  "source",
  "track",
  "wbr",
]);

const DEFAULT_RECT = { left: 0, top: 0, width: 800, height: 400, right: 800, bottom: 400 };

class FakeClassList {
  constructor(element) {
    this.element = element;
  }
  _set() {
    return this.element._classes;
  }
  _sync() {
    this.element._className = Array.from(this._set()).join(" ");
  }
  add(...names) {
    for (const name of names) {
      if (name) this._set().add(String(name));
    }
    this._sync();
  }
  remove(...names) {
    for (const name of names) this._set().delete(String(name));
    this._sync();
  }
  contains(name) {
    return this._set().has(String(name));
  }
  toggle(name, force) {
    const value = force === undefined ? !this.contains(name) : !!force;
    if (value) this.add(name);
    else this.remove(name);
    return value;
  }
  get value() {
    return this.element._className;
  }
  toString() {
    return this.element._className;
  }
}

function unescapeHtml(text) {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, "\u00a0")
    .replace(/&amp;/g, "&");
}

function escapeHtml(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function stripTags(html) {
  return unescapeHtml(String(html).replace(/<!--[\s\S]*?-->/g, "").replace(/<[^>]*>/g, ""));
}

function parseStyleAttribute(value) {
  const style = {};
  for (const declaration of String(value).split(";")) {
    const index = declaration.indexOf(":");
    if (index < 0) continue;
    const prop = declaration.slice(0, index).trim();
    const val = declaration.slice(index + 1).trim();
    if (!prop) continue;
    const camel = prop.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    style[camel] = val;
  }
  return style;
}

function parseAttributes(source) {
  const attributes = {};
  const re = /([^\s/>=]+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+))?/g;
  let match;
  while ((match = re.exec(source || "")) !== null) {
    const name = match[1];
    let value = match[2] === undefined ? "" : match[2];
    if (value.startsWith('"') || value.startsWith("'")) {
      value = value.slice(1, -1);
    }
    attributes[name] = unescapeHtml(value);
  }
  return attributes;
}

class FakeElement {
  constructor(ownerDocument, tagName) {
    this.ownerDocument = ownerDocument;
    this.nodeType = 1;
    this.tagName = String(tagName || "div").toUpperCase();
    this.nodeName = this.tagName;
    this.childNodes = [];
    this.parentNode = null;
    this.attributes = {};
    this.style = {};
    this._className = "";
    this._classes = new Set();
    this._listeners = Object.create(null);
    this._value = "";
    this._textContent = null;
    this._rawHTML = null;
    this._rect = null;
    this.clientWidth = 800;
    this.clientHeight = 400;
    this.scrollWidth = 0;
    this.scrollHeight = 0;
    this.scrollTop = 0;
    this.scrollLeft = 0;
    this.classList = new FakeClassList(this);
  }

  get children() {
    return this.childNodes.filter((node) => node.nodeType === 1);
  }

  get firstChild() {
    return this.childNodes[0] || null;
  }

  get className() {
    return this._className;
  }

  set className(value) {
    this._className = value == null ? "" : String(value);
    this._classes = new Set(this._className.split(/\s+/).filter(Boolean));
  }

  get innerHTML() {
    if (this._rawHTML !== null) return this._rawHTML;
    return this.childNodes.map((node) => serializeNode(node)).join("");
  }

  set innerHTML(value) {
    const html = value == null ? "" : String(value);
    this._rawHTML = html;
    this._textContent = stripTags(html);
    this.childNodes = parseHTML(html, this.ownerDocument);
    for (const child of this.childNodes) child.parentNode = this;
  }

  get textContent() {
    if (this._textContent !== null) return this._textContent;
    return this.childNodes.map((node) => node.textContent || "").join("");
  }

  set textContent(value) {
    this._textContent = value == null ? "" : String(value);
    this._rawHTML = null;
    this.childNodes = [];
  }

  get value() {
    return this._value;
  }

  set value(value) {
    this._value = value == null ? "" : String(value);
  }

  appendChild(child) {
    if (!child) throw new TypeError("appendChild: child is required");
    if (child.parentNode && typeof child.parentNode.removeChild === "function") {
      child.parentNode.removeChild(child);
    }
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }

  removeChild(child) {
    const index = this.childNodes.indexOf(child);
    if (index >= 0) {
      this.childNodes.splice(index, 1);
      child.parentNode = null;
    }
    return child;
  }

  insertBefore(child, reference) {
    const index = reference ? this.childNodes.indexOf(reference) : -1;
    if (index < 0) return this.appendChild(child);
    child.parentNode = this;
    this.childNodes.splice(index, 0, child);
    return child;
  }

  replaceChild(next, previous) {
    const index = this.childNodes.indexOf(previous);
    if (index >= 0) this.childNodes[index] = next;
    next.parentNode = this;
    previous.parentNode = null;
    return previous;
  }

  setAttribute(name, value) {
    const key = String(name);
    this.attributes[key] = value == null ? "" : String(value);
    if (key === "class") this.className = this.attributes[key];
    else if (key === "style") this.style = parseStyleAttribute(this.attributes[key]);
    else if (key === "value") this._value = this.attributes[key];
  }

  getAttribute(name) {
    const key = String(name);
    return Object.prototype.hasOwnProperty.call(this.attributes, key)
      ? this.attributes[key]
      : null;
  }

  removeAttribute(name) {
    delete this.attributes[String(name)];
  }

  hasAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attributes, String(name));
  }

  addEventListener(type, handler) {
    if (typeof handler !== "function") return;
    const key = String(type);
    (this._listeners[key] || (this._listeners[key] = [])).push(handler);
  }

  removeEventListener(type, handler) {
    const list = this._listeners[String(type)];
    if (!list) return;
    const index = list.indexOf(handler);
    if (index >= 0) list.splice(index, 1);
  }

  dispatchEvent(event) {
    if (!event || !event.type) return true;
    if (!event.target) event.target = this;
    let node = this;
    while (node) {
      const list = node._listeners && node._listeners[event.type];
      if (list) {
        for (const handler of list.slice()) {
          event.currentTarget = node;
          handler.call(node, event);
          if (event._stopped || event.cancelBubble) break;
        }
      }
      if (event._stopped || event.cancelBubble) break;
      node = node.parentNode;
    }
    return !event.defaultPrevented;
  }

  getBoundingClientRect() {
    return this._rect || Object.assign({}, DEFAULT_RECT);
  }

  /** Test helper: override the rect returned by getBoundingClientRect. */
  setRect(rect) {
    this._rect = Object.assign({}, DEFAULT_RECT, rect || {});
    return this;
  }

  focus() {
    const doc = this.ownerDocument;
    if (doc && doc.activeElement !== this) {
      if (doc.activeElement && typeof doc.activeElement.blur === "function") {
        doc.activeElement.blur();
      }
      doc.activeElement = this;
    }
    this.dispatchEvent(makeEvent("focus", this));
  }

  blur() {
    const doc = this.ownerDocument;
    if (doc && doc.activeElement === this) doc.activeElement = null;
    this.dispatchEvent(makeEvent("blur", this));
  }

  click() {
    this.dispatchEvent(makeEvent("click", this));
  }

  select() {}

  setSelectionRange() {}

  scrollIntoView() {}

  closest(selector) {
    let node = this;
    const match = (element) => {
      if (selector.startsWith(".")) return element.classList && element.classList.contains(selector.slice(1));
      if (selector.startsWith("#")) return element.getAttribute("id") === selector.slice(1);
      return element.tagName && element.tagName.toLowerCase() === selector.toLowerCase();
    };
    while (node) {
      if (node.nodeType === 1 && match(node)) return node;
      node = node.parentNode;
    }
    return null;
  }
}

class FakeTextNode {
  constructor(ownerDocument, text) {
    this.ownerDocument = ownerDocument;
    this.nodeType = 3;
    this.nodeName = "#text";
    this.textContent = text == null ? "" : String(text);
    this.parentNode = null;
  }
}

function serializeNode(node) {
  if (node.nodeType === 3) return escapeHtml(node.textContent);
  const tag = node.tagName.toLowerCase();
  let out = "<" + tag;
  for (const [name, value] of Object.entries(node.attributes)) {
    out += ` ${name}="${escapeHtml(value)}"`;
  }
  if (VOID_TAGS.has(tag)) return out + ">";
  out += ">";
  for (const child of node.childNodes) out += serializeNode(child);
  return out + `</${tag}>`;
}

const TOKEN_RE = /<!--[\s\S]*?-->|<\/?([a-zA-Z][^\s/>]*)((?:"[^"]*"|'[^']*'|[^>"'])*)\/?>/g;

function parseHTML(html, ownerDocument) {
  const roots = [];
  const stack = [];
  let lastIndex = 0;
  let match;
  TOKEN_RE.lastIndex = 0;

  const push = (node) => {
    const parent = stack[stack.length - 1];
    if (parent) parent.childNodes.push(node);
    else roots.push(node);
  };

  while ((match = TOKEN_RE.exec(html)) !== null) {
    const text = html.slice(lastIndex, match.index);
    if (text) push(new FakeTextNode(ownerDocument, unescapeHtml(text)));
    lastIndex = match.index + match[0].length;

    const full = match[0];
    if (full.startsWith("<!--")) continue;

    const tag = match[1];
    if (full.startsWith("</")) {
      for (let i = stack.length - 1; i >= 0; i = i - 1) {
        if (stack[i].tagName.toLowerCase() === tag.toLowerCase()) {
          stack.length = i;
          break;
        }
      }
      continue;
    }

    const element = new FakeElement(ownerDocument, tag);
    const attributes = parseAttributes(match[2] || "");
    for (const [name, value] of Object.entries(attributes)) {
      element.setAttribute(name, value);
    }
    push(element);
    if (!full.endsWith("/>") && !VOID_TAGS.has(tag.toLowerCase())) {
      stack.push(element);
    }
  }

  const tail = html.slice(lastIndex);
  if (tail) push(new FakeTextNode(ownerDocument, unescapeHtml(tail)));
  return roots;
}

function makeEvent(type, target, extra) {
  return Object.assign(
    {
      type,
      target: target || null,
      currentTarget: null,
      defaultPrevented: false,
      cancelBubble: false,
      _stopped: false,
      preventDefault() {
        this.defaultPrevented = true;
      },
      stopPropagation() {
        this._stopped = true;
        this.cancelBubble = true;
      },
    },
    extra || {},
  );
}

function createFakeWindow(document) {
  const listeners = Object.create(null);
  const window = {
    document,
    __cmFake: true,
    addEventListener(type, handler) {
      if (typeof handler !== "function") return;
      (listeners[String(type)] || (listeners[String(type)] = [])).push(handler);
    },
    removeEventListener(type, handler) {
      const list = listeners[String(type)];
      if (!list) return;
      const index = list.indexOf(handler);
      if (index >= 0) list.splice(index, 1);
    },
    dispatchEvent(event) {
      const list = listeners[event.type];
      if (list) for (const handler of list.slice()) handler.call(window, event);
      return !event.defaultPrevented;
    },
  };
  return window;
}

/** Create a standalone fake document. */
export function createDocument() {
  const document = {
    __cmFake: true,
    nodeType: 9,
    activeElement: null,
    createElement(tag) {
      return new FakeElement(document, tag);
    },
    createTextNode(text) {
      return new FakeTextNode(document, text);
    },
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() {
      return true;
    },
  };
  document.body = document.createElement("body");
  document.documentElement = document.createElement("html");
  document.body.ownerDocument = document;
  document.documentElement.ownerDocument = document;
  return document;
}

/**
 * Install `globalThis.document`, `globalThis.window` and
 * `requestAnimationFrame` if they are missing. Idempotent.
 */
export function installFakeDom() {
  if (globalThis.document && globalThis.document.__cmFake) {
    return { document: globalThis.document, window: globalThis.window };
  }
  const document = createDocument();
  const window = createFakeWindow(document);
  globalThis.document = document;
  globalThis.window = window;
  if (typeof globalThis.requestAnimationFrame !== "function") {
    globalThis.requestAnimationFrame = (callback) =>
      setTimeout(() => callback(Date.now()), 0);
    globalThis.cancelAnimationFrame = (handle) => clearTimeout(handle);
  }
  return { document, window };
}

/** Convenience: create an element using the installed fake document. */
export function createElement(tag) {
  const { document } = installFakeDom();
  return document.createElement(tag);
}

/** The full wasm import object: `{ dom, spectest }`. */
export function createImports() {
  installFakeDom();
  return {
    dom: createDomImports(),
    spectest: {
      print_char() {},
    },
  };
}

function toUrl(url) {
  if (url instanceof URL) return url;
  if (typeof url === "string") {
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(url)) return new URL(url);
    return new URL(url, pathToFileURL(process.cwd() + "/"));
  }
  throw new TypeError("loadWasm: expected a URL or path string");
}

/**
 * Load and instantiate the wasm module. `file:` URLs are read with
 * `node:fs`; anything else goes through `fetch`.
 */
export async function loadWasm(url, imports = createImports()) {
  const resolved = toUrl(url);
  let bytes;
  if (resolved.protocol === "file:") {
    bytes = await readFile(resolved);
  } else {
    const response = await fetch(resolved);
    if (!response.ok) {
      throw new Error(`loadWasm: failed to fetch ${resolved}: ${response.status}`);
    }
    bytes = new Uint8Array(await response.arrayBuffer());
  }
  const { instance } = await WebAssembly.instantiate(bytes, imports);
  return instance;
}

/**
 * Event forwarding helpers used by the e2e tests. They push fake events
 * through the exact handlers registered by the runtime.
 */
export function getImportsDeps() {
  installFakeDom();
  return {
    dispatchKey: (id, key, code, mods) => __testForward.key(id, key, code, mods),
    dispatchKeyEvent: (id, fields) => __testForward.keyEvent(id, fields),
    dispatchMouse: (id, kind, x, y, detail) =>
      __testForward.mouse(id, kind, x, y, detail),
    dispatchBeforeInput: (id, text) => __testForward.beforeInput(id, text),
    dispatchPaste: (id, text) => __testForward.paste(id, text),
    dispatchCopy: (id) => __testForward.copy(id),
    dispatchCut: (id) => __testForward.cut(id),
    dispatchScroll: (id, top, left) => __testForward.scroll(id, top, left),
    dispatchFocus: (id, focused) => __testForward.focus(id, focused),
    onUpdate: (id, callback) => onUpdate(id, callback),
  };
}

export { attachWasm, __testForward };
