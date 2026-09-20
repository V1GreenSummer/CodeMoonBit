// Real-browser end-to-end tests for CodeMoonBit.
//
// Drives a locally installed Chromium through the DevTools protocol (no npm
// dependencies) and exercises the editor with genuine keyboard, mouse and
// input events, then asserts against the live DOM and the wasm editor state.
//
//   node js/browser_e2e.mjs
//
// Environment:
//   CHROME_PATH   explicit browser executable
//   CM_PORT       http server port (default: random free port)

import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function findChrome() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const home = os.homedir();
  const candidates = [];
  const playwright = path.join(home, ".cache", "ms-playwright");
  if (fs.existsSync(playwright)) {
    for (const entry of fs.readdirSync(playwright)) {
      if (entry.startsWith("chromium-")) {
        candidates.push(path.join(playwright, entry, "chrome-linux64", "chrome"));
        candidates.push(path.join(playwright, entry, "chrome-linux", "chrome"));
      }
      if (entry.startsWith("chromium_headless_shell-")) {
        candidates.push(
          path.join(playwright, entry, "chrome-headless-shell-linux64", "chrome-headless-shell"),
        );
      }
    }
  }
  for (const name of ["google-chrome", "chromium", "chromium-browser"]) {
    for (const dir of (process.env.PATH || "").split(":")) {
      candidates.push(path.join(dir, name));
    }
  }
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error("no Chromium/Chrome found; set CHROME_PATH");
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

async function waitForHttp(url, timeoutMs = 20000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch {
      // retry
    }
    await sleep(150);
  }
  throw new Error(`timeout waiting for ${url}`);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

class CDP {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    ws.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.id !== undefined) {
        const pending = this.pending.get(message.id);
        if (pending) {
          this.pending.delete(message.id);
          if (message.error) pending.reject(new Error(message.error.message));
          else pending.resolve(message.result);
        }
      } else if (message.method) {
        const handlers = this.listeners.get(message.method) || [];
        for (const handler of handlers) handler(message.params);
      }
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  once(method) {
    return new Promise((resolve) => {
      const handler = (params) => {
        const handlers = this.listeners.get(method) || [];
        this.listeners.set(
          method,
          handlers.filter((h) => h !== handler),
        );
        resolve(params);
      };
      this.listeners.set(method, [...(this.listeners.get(method) || []), handler]);
    });
  }

  close() {
    this.ws.close();
  }
}

class TestRunner {
  constructor() {
    this.passed = 0;
    this.failed = 0;
  }

  ok(name) {
    this.passed += 1;
    console.log(`ok - ${name}`);
  }

  fail(name, message) {
    this.failed += 1;
    console.log(`not ok - ${name}`);
    console.log(`    ${message}`);
  }

  check(name, condition, detail = "") {
    if (condition) this.ok(name);
    else this.fail(name, detail || "assertion failed");
  }
}

async function main() {
  const chromePath = findChrome();
  const port = process.env.CM_PORT ? Number(process.env.CM_PORT) : await freePort();
  const debugPort = await freePort();
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "cm-chrome-"));
  const origin = `http://127.0.0.1:${port}`;

  console.log(`browser: ${chromePath}`);
  console.log(`serving ${ROOT} on ${origin}`);

  const http = spawn("python3", ["-m", "http.server", String(port), "--bind", "127.0.0.1"], {
    cwd: ROOT,
    stdio: "ignore",
  });
  const chrome = spawn(
    chromePath,
    [
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--hide-scrollbars",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-dev-shm-usage",
      `--user-data-dir=${userDataDir}`,
      `--remote-debugging-port=${debugPort}`,
      "about:blank",
    ],
    { stdio: "ignore" },
  );

  const cleanup = () => {
    try {
      chrome.kill("SIGKILL");
    } catch {}
    try {
      http.kill("SIGKILL");
    } catch {}
    try {
      fs.rmSync(userDataDir, { recursive: true, force: true });
    } catch {}
  };

  let cdp;
  try {
    await waitForHttp(`${origin}/demo/browser-test.html`);
    await waitForHttp(`http://127.0.0.1:${debugPort}/json/version`);

    let target;
    const targetStarted = Date.now();
    while (Date.now() - targetStarted < 15000) {
      const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
      target = targets.find((t) => t.type === "page");
      if (target) break;
      await sleep(150);
    }
    if (!target) throw new Error("no page target");

    const ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      ws.addEventListener("open", resolve, { once: true });
      ws.addEventListener("error", reject, { once: true });
    });
    cdp = new CDP(ws);
    await cdp.send("Page.enable");
    await cdp.send("Runtime.enable");
    // Headless Chrome reports `document.hasFocus() === false` unless focus
    // emulation is enabled, which suppresses focus/blur events on the hidden
    // textarea. The editor's `cm-focused` state depends on those events.
    await cdp.send("Emulation.setFocusEmulationEnabled", { enabled: true });

    // Capture every uncaught exception and console error for the whole
    // session, including after the navigation to the demo shell at the end.
    const pageErrors = [];
    cdp.listeners.set("Runtime.exceptionThrown", [
      (params) => {
        const details = params && params.exceptionDetails;
        pageErrors.push(
          (details && details.exception && details.exception.description) ||
            (details && details.text) ||
            "uncaught exception",
        );
      },
    ]);
    cdp.listeners.set("Runtime.consoleAPICalled", [
      (params) => {
        if (!params || params.type !== "error") return;
        const text = (params.args || [])
          .map((arg) => arg.value || arg.description || arg.type || "")
          .join(" ");
        pageErrors.push(text || "console.error");
      },
    ]);

    const loaded = cdp.once("Page.loadEventFired");
    await cdp.send("Page.navigate", { url: `${origin}/demo/browser-test.html` });
    await loaded;

    const evaluate = async (expression) => {
      const result = await cdp.send("Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      });
      if (result.exceptionDetails) {
        throw new Error(result.exceptionDetails.text || "evaluation failed");
      }
      return result.result.value;
    };

    const editorCall = (call) => evaluate(`window.editor.${call}`);

    const keyInfo = {
      ArrowLeft: { key: "ArrowLeft", code: "ArrowLeft", vk: 37 },
      ArrowRight: { key: "ArrowRight", code: "ArrowRight", vk: 39 },
      ArrowUp: { key: "ArrowUp", code: "ArrowUp", vk: 38 },
      ArrowDown: { key: "ArrowDown", code: "ArrowDown", vk: 40 },
      Home: { key: "Home", code: "Home", vk: 36 },
      End: { key: "End", code: "End", vk: 35 },
      Enter: { key: "Enter", code: "Enter", vk: 13 },
      Backspace: { key: "Backspace", code: "Backspace", vk: 8 },
      Delete: { key: "Delete", code: "Delete", vk: 46 },
      Escape: { key: "Escape", code: "Escape", vk: 27 },
    };

    const MOD_ALT = 1;
    const MOD_CTRL = 2;
    const MOD_SHIFT = 8;

    const press = async (name, modifiers = 0) => {
      const info = keyInfo[name];
      const params = {
        key: info.key,
        code: info.code,
        windowsVirtualKeyCode: info.vk,
        nativeVirtualKeyCode: info.vk,
        modifiers,
      };
      await cdp.send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...params });
      await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", ...params });
    };

    const typeChar = async (char) => {
      const code = char.toUpperCase() === char ? `Key${char}` : `Key${char.toUpperCase()}`;
      const isUpper = char >= "A" && char <= "Z";
      let vk = char.toUpperCase().charCodeAt(0);
      if (char === " ") vk = 32;
      const modifiers = isUpper ? MOD_SHIFT : 0;
      const normalized = isUpper ? char.toLowerCase() : char;
      const params = {
        key: char,
        code,
        windowsVirtualKeyCode: vk,
        nativeVirtualKeyCode: vk,
        modifiers,
        text: char,
        unmodifiedText: normalized,
      };
      await cdp.send("Input.dispatchKeyEvent", { type: "keyDown", ...params });
      await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", ...params });
    };

    const type = async (text) => {
      for (const char of text) await typeChar(char);
    };

    const pressCtrl = async (letter) => {
      const vk = letter.toUpperCase().charCodeAt(0);
      const params = {
        key: letter,
        code: `Key${letter.toUpperCase()}`,
        windowsVirtualKeyCode: vk,
        nativeVirtualKeyCode: vk,
        modifiers: MOD_CTRL,
      };
      await cdp.send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...params });
      await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", ...params });
    };

    const waitFor = async (expression, timeoutMs = 5000) => {
      const started = Date.now();
      while (Date.now() - started < timeoutMs) {
        if (await evaluate(expression)) return true;
        await sleep(50);
      }
      return false;
    };

    const runner = new TestRunner();

    // 1. boot
    const ready = await waitFor("window.ready === true || window.errors.length > 0");
    runner.check("editor boots in a real browser", ready, "timed out waiting for window.ready");
    if (!ready) {
      console.log("errors:", await evaluate("window.errors"));
      throw new Error("editor failed to boot");
    }
    runner.check(
      "no uncaught errors during boot",
      (await evaluate("window.errors.length")) === 0,
      JSON.stringify(await evaluate("window.errors")),
    );
    runner.check(
      "wasm doc loaded through browser.js",
      (await editorCall("getDoc()")) === 'fn main {\n  println("hi")\n}\n',
      await editorCall("getDoc()"),
    );

    // 2. real DOM rendering
    runner.check(
      "gutter renders line numbers",
      (await evaluate('window.count(".cm-gutter-line")')) >= 4,
      `got ${await evaluate('window.count(".cm-gutter-line")')}`,
    );
    runner.check(
      "syntax highlighting emits keyword tokens",
      (await evaluate('window.tokenCount("keyword")')) >= 1,
      `got ${await evaluate('window.tokenCount("keyword")')}`,
    );
    runner.check(
      "syntax highlighting emits string tokens",
      (await evaluate('window.tokenCount("string")')) >= 1,
    );

    // 2b. focus state, cursor visibility and the active gutter marker
    await editorCall("focus()");
    await waitFor('document.querySelector("#editor .cm-editor").classList.contains("cm-focused")');
    runner.check(
      "focusing the editor adds cm-focused",
      await evaluate('document.querySelector("#editor .cm-editor").classList.contains("cm-focused")'),
    );
    runner.check(
      "the cursor is visible while focused",
      (await evaluate(
        'getComputedStyle(document.querySelector("#editor .cm-cursor")).display',
      )) !== "none",
    );
    runner.check(
      "the cursor line is marked in the gutter",
      (await evaluate('window.count(".cm-gutter-line.cm-active-gutter")')) === 1 &&
        (await evaluate(
          'document.querySelector("#editor .cm-active-gutter").textContent',
        )).includes("1"),
      await evaluate('document.querySelector("#editor .cm-active-gutter").textContent'),
    );
    await evaluate('document.querySelector("#editor .cm-input").blur()');
    await waitFor('!document.querySelector("#editor .cm-editor").classList.contains("cm-focused")');
    runner.check(
      "blurring the editor removes cm-focused",
      !(await evaluate('document.querySelector("#editor .cm-editor").classList.contains("cm-focused")')),
    );
    const blurredCursorDisplay = await evaluate(
      '(() => { const cursor = document.querySelector("#editor .cm-cursor"); return cursor ? getComputedStyle(cursor).display : "missing"; })()',
    );
    runner.check(
      "the cursor is hidden while blurred",
      blurredCursorDisplay === "none" || blurredCursorDisplay === "missing",
      blurredCursorDisplay,
    );
    await editorCall("focus()");
    await press("ArrowDown");
    await waitFor(
      'document.querySelector("#editor .cm-active-gutter") && document.querySelector("#editor .cm-active-gutter").textContent === "2"',
    );
    runner.check(
      "the active gutter marker follows the cursor",
      (await evaluate(
        'document.querySelector("#editor .cm-active-gutter").textContent',
      )) === "2",
    );
    await press("ArrowUp");

    // 3. typing / deleting through real key events
    await editorCall("focus()");
    await press("End", MOD_CTRL);
    await typeChar("!");
    await waitFor("window.editor.getDoc().endsWith('}\\n!')");
    runner.check(
      "printable key inserts at the cursor",
      (await editorCall("getDoc()")).endsWith("}\n!"),
      await editorCall("getDoc()"),
    );
    await press("Backspace");
    runner.check(
      "backspace deletes the inserted character",
      !(await editorCall("getDoc()")).endsWith("!"),
    );
    await press("Enter");
    await typeChar("x");
    runner.check(
      "enter inserts a newline",
      (await editorCall("getDoc()")).endsWith("}\n\nx"),
      await editorCall("getDoc()"),
    );

    // 4. undo / redo through real shortcuts
    await pressCtrl("z");
    runner.check("ctrl-z undoes typing", !(await editorCall("getDoc()")).includes("x"), await editorCall("getDoc()"));
    await pressCtrl("y");
    runner.check("ctrl-y redoes typing", (await editorCall("getDoc()")).includes("x"), await editorCall("getDoc()"));

    // 5. select all then replace
    await editorCall("setDoc('hello world')");
    await editorCall("focus()");
    await pressCtrl("a");
    runner.check(
      "ctrl-a selects the whole document",
      (await editorCall("getState()")).includes("sel=0:11"),
      await editorCall("getState()"),
    );
    await typeChar("a");
    runner.check("typing replaces the selection", (await editorCall("getDoc()")) === "a", await editorCall("getDoc()"));
    await pressCtrl("z");
    runner.check("undo restores the replaced document", (await editorCall("getDoc()")).length > 5);

    // 5b. structured selection API
    await editorCall("setDoc('hello world')");
    await editorCall("focus()");
    await pressCtrl("a");
    const selectAllSelection = await editorCall("getSelection()");
    runner.check(
      "getSelection reports the select-all range",
      selectAllSelection !== null &&
        selectAllSelection.main === 0 &&
        selectAllSelection.ranges.length === 1 &&
        selectAllSelection.ranges[0].anchor === 0 &&
        selectAllSelection.ranges[0].head === 11,
      JSON.stringify(selectAllSelection),
    );
    const clickPoint = await evaluate(`(() => {
      const scroller = document.querySelector(".cm-scroller");
      const r = scroller.getBoundingClientRect();
      return { x: r.left + 40, y: r.top + 14 };
    })()`);
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: clickPoint.x,
      y: clickPoint.y,
      button: "left",
      clickCount: 1,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: clickPoint.x,
      y: clickPoint.y,
      button: "left",
      clickCount: 1,
    });
    await sleep(50);
    const clickSelection = await editorCall("getSelection()");
    runner.check(
      "getSelection reports a collapsed cursor after a plain click",
      clickSelection !== null &&
        clickSelection.ranges.length === 1 &&
        clickSelection.ranges[0].anchor === clickSelection.ranges[0].head,
      JSON.stringify(clickSelection),
    );

    // 6. auto indent
    await editorCall("setDoc('  foo')");
    await press("End", MOD_CTRL);
    await press("Enter");
    await typeChar("b");
    runner.check(
      "enter copies the leading indentation",
      (await editorCall("getDoc()")) === "  foo\n  b",
      JSON.stringify(await editorCall("getDoc()")),
    );

    // 7. multi cursor
    await editorCall("setDoc('a\\nb')");
    await press("ArrowDown", MOD_ALT);
    await typeChar("x");
    const multi = await editorCall("getDoc()");
    runner.check("alt-arrow adds a second cursor", multi === "xa\nxb", JSON.stringify(multi));

    // 8. language switching
    await editorCall('setOption("language", "json")');
    await editorCall('setDoc(\'{"a": 1}\')');
    await waitFor('window.tokenCount("property") > 0');
    runner.check("json property tokens render", (await evaluate('window.tokenCount("property")')) >= 1);
    runner.check("json number tokens render", (await evaluate('window.tokenCount("number")')) >= 1);

    // 9. search panel driven through the real UI
    await editorCall('setOption("language", "moonbit")');
    await editorCall("setDoc('foo bar foo')");
    await editorCall("focus()");
    await pressCtrl("f");
    await waitFor('!document.querySelector(".cm-panel").classList.contains("cm-panel-hidden")');
    runner.check(
      "ctrl-f opens the search panel",
      await evaluate('!document.querySelector(".cm-panel").classList.contains("cm-panel-hidden")'),
    );
    runner.check(
      "search buttons carry keyboard hints",
      (await evaluate('document.querySelector(".cm-search-next").title')) === "Next match (Enter)" &&
        (await evaluate('document.querySelector(".cm-search-prev").title')) === "Previous match (Shift-Enter)",
    );
    runner.check(
      "the search counter starts empty",
      (await evaluate('document.querySelector(".cm-search-count").textContent')) === "0 / 0" &&
        (await evaluate(
          'document.querySelector(".cm-search-count").classList.contains("cm-search-count-empty")',
        )),
    );
    await evaluate('document.querySelector(".cm-search-input").focus()');
    await cdp.send("Input.insertText", { text: "foo" });
    await waitFor('window.count(".cm-search-match") === 2');
    runner.check(
      "typing in the panel highlights all matches",
      (await evaluate('window.count(".cm-search-match")')) === 2,
      `got ${await evaluate('window.count(".cm-search-match")')}`,
    );
    await waitFor("window.editor.getState().includes('sel=0:3')");
    runner.check(
      "setting a query selects the first match",
      (await editorCall("getState()")).includes("sel=0:3"),
      await editorCall("getState()"),
    );
    runner.check(
      "the search counter shows the current match",
      (await evaluate('document.querySelector(".cm-search-count").textContent')) === "1 / 2",
      await evaluate('document.querySelector(".cm-search-count").textContent'),
    );
    await evaluate('document.querySelector(".cm-search-next").click()');
    await waitFor("window.editor.getState().includes('sel=8:11')");
    runner.check(
      "search next selects the following match",
      (await editorCall("getState()")).includes("sel=8:11"),
      await editorCall("getState()"),
    );
    runner.check(
      "the search counter follows next",
      (await evaluate('document.querySelector(".cm-search-count").textContent')) === "2 / 2",
      await evaluate('document.querySelector(".cm-search-count").textContent'),
    );
    await evaluate('document.querySelector(".cm-search-prev").click()');
    await waitFor("window.editor.getState().includes('sel=0:3')");
    runner.check(
      "the search counter follows prev",
      (await evaluate('document.querySelector(".cm-search-count").textContent')) === "1 / 2",
      await evaluate('document.querySelector(".cm-search-count").textContent'),
    );
    await evaluate('document.querySelector(".cm-search-replace").focus()');
    await cdp.send("Input.insertText", { text: "moon" });
    await evaluate('document.querySelector(".cm-search-replace-all").click()');
    runner.check(
      "replace all rewrites the document",
      (await editorCall("getDoc()")) === "moon bar moon",
      await editorCall("getDoc()"),
    );
    await evaluate('document.querySelector(".cm-search-input").focus()');
    await press("Escape");
    await waitFor('document.querySelector(".cm-panel").classList.contains("cm-panel-hidden")');
    runner.check(
      "escape closes the search panel",
      await evaluate('document.querySelector(".cm-panel").classList.contains("cm-panel-hidden")'),
    );

    // 10. read only
    await editorCall('setOption("readOnly", "true")');
    await editorCall("setDoc('locked')");
    await press("End", MOD_CTRL);
    await typeChar("z");
    runner.check("read-only blocks typing", (await editorCall("getDoc()")) === "locked", await editorCall("getDoc()"));
    await editorCall('setOption("readOnly", "false")');

    // 11. selection rendering
    await editorCall("setDoc('select me')");
    await pressCtrl("a");
    await waitFor('window.count(".cm-selection") > 0');
    runner.check(
      "selection is painted in the DOM",
      (await evaluate('window.count(".cm-selection")')) >= 1,
      `got ${await evaluate('window.count(".cm-selection")')}`,
    );

    // 12. fold discoverability and folding through the gutter markers
    await editorCall('setOption("language", "moonbit")');
    await editorCall("setDoc('fn a() {\\n  x\\n}\\n')");
    await waitFor('window.count(".cm-fold") > 0');
    runner.check(
      "a foldable but unfolded line shows a marker before folding",
      (await evaluate('window.count(".cm-fold.cm-fold-foldable")')) >= 1,
      `markers=${await evaluate('window.count(".cm-fold")')}`,
    );
    runner.check(
      "the unfolded marker uses the dim glyph",
      (await evaluate('document.querySelector("#editor .cm-fold-foldable").textContent')) === "\u25BE",
      await evaluate('document.querySelector("#editor .cm-fold-foldable").textContent'),
    );
    runner.check(
      "no ellipsis is shown before folding",
      (await evaluate('window.count(".cm-fold-ellipsis")')) === 0,
    );
    const clickMarker = async (selector) => {
      const point = await evaluate(`(() => {
        const marker = document.querySelector(${JSON.stringify(selector)});
        const r = marker.getBoundingClientRect();
        return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
      })()`);
      await cdp.send("Input.dispatchMouseEvent", {
        type: "mousePressed",
        x: point.x,
        y: point.y,
        button: "left",
        clickCount: 1,
      });
      await cdp.send("Input.dispatchMouseEvent", {
        type: "mouseReleased",
        x: point.x,
        y: point.y,
        button: "left",
        clickCount: 1,
      });
    };
    await clickMarker("#editor .cm-fold-foldable");
    await waitFor('window.count(".cm-fold-ellipsis") > 0');
    runner.check(
      "clicking a foldable marker folds the block",
      (await evaluate('window.count(".cm-fold-ellipsis")')) >= 1 &&
        (await evaluate('window.count(".cm-fold")')) === 1,
      `${await editorCall("getState()")} markers=${await evaluate('window.count(".cm-fold")')}`,
    );
    runner.check(
      "a folded line shows exactly one bright marker",
      (await evaluate('window.count(".cm-fold.cm-fold-folded")')) === 1 &&
        (await evaluate('document.querySelector("#editor .cm-fold-folded").textContent')) === "\u25B8",
      await evaluate('document.querySelector("#editor .cm-fold-folded") && document.querySelector("#editor .cm-fold-folded").textContent'),
    );
    await clickMarker("#editor .cm-fold-folded");
    await waitFor('window.count(".cm-fold-ellipsis") === 0');
    runner.check(
      "clicking the folded marker unfolds the block",
      (await evaluate('window.count(".cm-fold-ellipsis")')) === 0 &&
        (await evaluate('window.count(".cm-fold.cm-fold-foldable")')) >= 1,
      `${await editorCall("getState()")}`,
    );

    // 12b. folding through the public API
    await evaluate("window.editor.foldAll()");
    await waitFor('window.count(".cm-fold-ellipsis") > 0');
    runner.check("fold all renders fold widgets", (await evaluate('window.count(".cm-fold")')) >= 1);
    runner.check(
      "folded lines show an ellipsis",
      (await evaluate('window.count(".cm-fold-ellipsis")')) >= 1,
    );
    const gutterBefore = await evaluate('window.count(".cm-gutter-line")');
    await evaluate("window.editor.unfoldAll()");
    await sleep(100);
    runner.check("unfold all restores hidden lines", (await evaluate('window.count(".cm-gutter-line")')) >= gutterBefore);

    // 13. mouse hit testing
    await editorCall("setDoc('first line\\nsecond line\\nthird line')");
    const rect = await evaluate(`(() => {
      const scroller = document.querySelector(".cm-scroller");
      const r = scroller.getBoundingClientRect();
      return { x: r.left + 30, y: r.top + 14 };
    })()`);
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: rect.x,
      y: rect.y,
      button: "left",
      clickCount: 1,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: rect.x,
      y: rect.y,
      button: "left",
      clickCount: 1,
    });
    const mouseState = await editorCall("getState()");
    runner.check(
      "mouse click positions the cursor",
      /sel=\d+:\d+/.test(mouseState) && !mouseState.includes("sel=0:0"),
      mouseState,
    );

    // 14. scrolling updates the rendered viewport
    await editorCall("setDoc(Array.from({ length: 400 }, (_, i) => 'line ' + i).join('\\n'))");
    runner.check(
      "large document renders only a viewport",
      (await evaluate('window.count(".cm-line")')) > 0 && (await evaluate('window.count(".cm-line")')) < 60,
      `rendered ${await evaluate('window.count(".cm-line")')} lines for 400 document lines`,
    );
    await evaluate(`(() => {
      const scroller = document.querySelector(".cm-scroller");
      scroller.scrollTop = 2000;
      scroller.dispatchEvent(new Event("scroll"));
    })()`);
    await sleep(200);
    const firstRendered = await evaluate(
      'document.querySelector(".cm-line") ? document.querySelector(".cm-line").textContent : ""',
    );
    runner.check(
      "scrolling virtualizes the viewport",
      (await evaluate('window.count(".cm-line")')) > 0 &&
        (await evaluate('window.count(".cm-line")')) < 60 &&
        firstRendered !== "line 0",
      `first rendered line: ${JSON.stringify(firstRendered)}`,
    );

    // 15. IME composition through the real DevTools IME API
    await editorCall("setDoc('')");
    await editorCall("focus()");
    let imeSupported = true;
    try {
      await cdp.send("Input.imeSetComposition", {
        selectionStart: 0,
        selectionEnd: 0,
        text: "ni",
        replacementStart: 0,
        replacementEnd: 0,
      });
      await cdp.send("Input.imeSetComposition", {
        selectionStart: 1,
        selectionEnd: 1,
        text: "你",
        replacementStart: 0,
        replacementEnd: 2,
      });
      await cdp.send("Input.insertText", { text: "你" });
    } catch (error) {
      imeSupported = false;
    }
    if (!imeSupported) {
      await editorCall("setDoc('')");
      await evaluate(`(() => {
        const input = document.querySelector(".cm-input");
        const fire = (type, data) => input.dispatchEvent(new CompositionEvent(type, { data }));
        fire("compositionstart", "");
        fire("compositionupdate", "ni");
        fire("compositionupdate", "你");
        fire("compositionend", "你");
      })()`);
    }
    await waitFor("window.editor.getDoc() === '你'");
    runner.check(
      "IME composition commits the composed text",
      (await editorCall("getDoc()")) === "你",
      JSON.stringify(await editorCall("getDoc()")),
    );
    await editorCall("undo()");
    await waitFor("window.editor.getDoc() === ''");
    runner.check(
      "one undo removes the whole composition",
      (await editorCall("getDoc()")) === "",
      JSON.stringify(await editorCall("getDoc()")),
    );

    // 16. arbitrary container and independent editor instances
    const secondId = await evaluate(`(async () => {
      const container = document.createElement("div");
      container.style.height = "240px";
      container.style.width = "640px";
      document.body.appendChild(container);
      const editor2 = await window.createEditor(container, {
        value: "x".repeat(400),
        language: "plain",
        lineWrapping: true,
      });
      window.editor2 = editor2;
      window.editor2Container = container;
      window.updateCount = 0;
      editor2.onUpdate(() => { window.updateCount += 1; });
      await new Promise((resolve) => setTimeout(resolve, 0));
      return editor2.id;
    })()`);
    runner.check(
      "a second editor is created in a plain container",
      typeof secondId === "number" && secondId !== 1,
      `id=${secondId}`,
    );
    const containerMetrics = await evaluate(`(() => {
      const container = window.editor2Container;
      return {
        frame: container.querySelector(".cm-editor").getBoundingClientRect().height,
        scroller: container.querySelector(".cm-scroller").getBoundingClientRect().height,
      };
    })()`);
    runner.check(
      "the editor fills an arbitrary fixed-height container",
      Math.abs(containerMetrics.frame - 240) < 2 &&
        Math.abs(containerMetrics.scroller - 240) < 2,
      JSON.stringify(containerMetrics),
    );
    const segmentCount = await evaluate(
      'window.editor2Container.querySelectorAll(".cm-line").length',
    );
    runner.check(
      "wrapping in a plain container renders one segment per div",
      segmentCount >= 2,
      `segments=${segmentCount}`,
    );
    const lineOverflow = await evaluate(
      'getComputedStyle(window.editor2Container.querySelector(".cm-line")).overflow',
    );
    runner.check("line segments clip their overflow", lineOverflow === "hidden", lineOverflow);
    runner.check(
      "onUpdate fires once right after creation",
      (await evaluate("window.updateCount")) === 1,
      `count=${await evaluate("window.updateCount")}`,
    );

    await editorCall("setDoc('first only')");
    await editorCall("focus()");
    await press("End", MOD_CTRL);
    await typeChar("?");
    await waitFor("window.editor.getDoc() === 'first only?'");
    runner.check(
      "typing in one editor updates only that editor",
      (await evaluate("window.editor2.getDoc()")) === "x".repeat(400),
      (await evaluate("window.editor2.getDoc()")).slice(0, 24),
    );
    const firstCounts = await evaluate(`(() => {
      const container = document.getElementById("editor");
      return {
        gutters: container.querySelectorAll(".cm-gutter-line").length,
        lines: container.querySelectorAll(".cm-line").length,
      };
    })()`);
    const secondCounts = await evaluate(`(() => {
      const container = window.editor2Container;
      return {
        gutters: container.querySelectorAll(".cm-gutter-line").length,
        lines: container.querySelectorAll(".cm-line").length,
      };
    })()`);
    runner.check(
      "both editors keep their own gutter/line DOM",
      firstCounts.gutters >= 1 &&
        firstCounts.lines >= 1 &&
        secondCounts.gutters >= 1 &&
        secondCounts.lines >= 2 &&
        (await evaluate('document.querySelectorAll(".cm-editor").length')) === 2,
      JSON.stringify({ firstCounts, secondCounts }),
    );

    // 17. Unicode boundary safety for mouse and word selection
    await editorCall("setDoc('\\u{1F600}b')");
    await editorCall("focus()");
    await sleep(150);
    const emojiRect = await evaluate(`(() => {
      const line = document.querySelector("#editor .cm-line");
      const r = line.getBoundingClientRect();
      return { left: r.left, mid: r.top + r.height / 2 };
    })()`);
    const clickAt = async (x, count = 1) => {
      await cdp.send("Input.dispatchMouseEvent", {
        type: "mousePressed",
        x,
        y: emojiRect.mid,
        button: "left",
        clickCount: count,
      });
      await cdp.send("Input.dispatchMouseEvent", {
        type: "mouseReleased",
        x,
        y: emojiRect.mid,
        button: "left",
        clickCount: count,
      });
    };
    await clickAt(emojiRect.left + 6);
    await sleep(100);
    const leftState = await editorCall("getState()");
    runner.check(
      "click inside an emoji never selects half a surrogate pair",
      /sel=[02]:[02]/.test(leftState) && !leftState.includes("sel=1:1"),
      leftState,
    );
    await clickAt(emojiRect.left + 6, 2);
    await sleep(100);
    const selectionJson = await editorCall("getSelection()");
    runner.check(
      "double click selects the whole emoji",
      selectionJson &&
        selectionJson.main === 0 &&
        selectionJson.ranges &&
        selectionJson.ranges[0] &&
        selectionJson.ranges[0].anchor === 0 &&
        selectionJson.ranges[0].head === 2,
      JSON.stringify(selectionJson),
    );
    runner.check(
      "copying an emoji selection is safe",
      (await editorCall("selectedText()")) === "\u{1F600}",
      await editorCall("selectedText()"),
    );
    await press("Backspace");
    await sleep(100);
    runner.check(
      "backspace after an emoji selection is safe",
      (await editorCall("getDoc()")) === "b",
      await editorCall("getDoc()"),
    );

    // 17b. click column accuracy (padding must not shift the hit test)
    await editorCall("setDoc('abcdefghij')");
    await editorCall("focus()");
    await press("End", MOD_CTRL);
    await sleep(120);
    const charWidth = await evaluate(
      'parseFloat(document.querySelector("#editor .cm-cursor").style.left) / 10',
    );
    const lineBox = await evaluate(`(() => {
      const line = document.querySelector("#editor .cm-line");
      const r = line.getBoundingClientRect();
      return { left: r.left, paddingLeft: parseFloat(getComputedStyle(line).paddingLeft), mid: r.top + r.height / 2 };
    })()`);
    const exactX = lineBox.left + lineBox.paddingLeft + 3 * charWidth + charWidth / 2;
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: exactX,
      y: lineBox.mid,
      button: "left",
      clickCount: 1,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: exactX,
      y: lineBox.mid,
      button: "left",
      clickCount: 1,
    });
    await sleep(120);
    const clickState = await editorCall("getState()");
    runner.check(
      "clicking the center of a character places the cursor there",
      clickState.includes("sel=3:3"),
      `${clickState} charWidth=${charWidth}`,
    );

    // 17c. the caret must sit after the last character, not on top of it
    await editorCall('setOption("language", "plain")');
    await editorCall("setDoc('hello')");
    await editorCall("focus()");
    await press("End", MOD_CTRL);
    await sleep(150);
    const caretAlignment = await evaluate(`(() => {
      const line = document.querySelector("#editor .cm-line");
      let node = line.firstChild;
      while (node && node.nodeType !== 3) node = node.firstChild;
      if (!node) return { ok: false, reason: "no text node" };
      const range = document.createRange();
      range.setStart(node, node.length - 1);
      range.setEnd(node, node.length);
      const charRect = range.getBoundingClientRect();
      const cursor = document.querySelector("#editor .cm-cursor");
      const cursorRect = cursor.getBoundingClientRect();
      return { charRight: charRect.right, cursorLeft: cursorRect.left, diff: Math.abs(charRect.right - cursorRect.left) };
    })()`);
    runner.check(
      "the caret is drawn after the last character, not over it",
      caretAlignment.ok !== false && caretAlignment.diff <= 2,
      JSON.stringify(caretAlignment),
    );

    // 17d. clicking the empty area below the text still places the caret
    await editorCall("setDoc('abc')");
    await editorCall("focus()");
    await sleep(120);
    const emptySpot = await evaluate(`(() => {
      const lines = document.querySelectorAll("#editor .cm-line");
      const last = lines[lines.length - 1].getBoundingClientRect();
      const viewportBottom = window.innerHeight - 10;
      return {
        x: last.left + 100,
        y: Math.min(viewportBottom, last.bottom + 40),
      };
    })()`);
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: emptySpot.x,
      y: emptySpot.y,
      button: "left",
      clickCount: 1,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: emptySpot.x,
      y: emptySpot.y,
      button: "left",
      clickCount: 1,
    });
    await sleep(120);
    const emptyState = await editorCall("getState()");
    const emptyFocused = await evaluate(
      'document.activeElement === document.querySelector("#editor .cm-input")',
    );
    runner.check(
      "clicking below the text focuses the editor and moves the caret to the end",
      emptyFocused && emptyState.includes("sel=3:3"),
      `${emptyState} focused=${emptyFocused}`,
    );

    // 18. font changes re-measure character widths
    await editorCall("setDoc('mmmm')");
    await editorCall("focus()");
    await press("End", MOD_CTRL);
    await sleep(100);
    const cursorBefore = await evaluate(
      'parseFloat(document.querySelector("#editor .cm-cursor").style.left)',
    );
    await editorCall('setOption("font", "28px monospace")');
    await sleep(200);
    const cursorAfter = await evaluate(
      'parseFloat(document.querySelector("#editor .cm-cursor").style.left)',
    );
    runner.check(
      "changing the font re-measures character widths",
      cursorAfter > cursorBefore * 1.5,
      `before=${cursorBefore} after=${cursorAfter}`,
    );
    await editorCall(
      'setOption("font", "14px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace")',
    );
    await sleep(100);

    // 19. drag selection stays visible and auto-scrolls past the viewport
    await editorCall("setDoc('alpha bravo charlie delta echo')");
    await editorCall("focus()");
    await sleep(150);
    const dragRect = await evaluate(`(() => {
      const line = document.querySelector("#editor .cm-line");
      const r = line.getBoundingClientRect();
      return { left: r.left, mid: r.top + r.height / 2 };
    })()`);
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: dragRect.left + 4 + 2 * 8.4,
      y: dragRect.mid,
      button: "left",
      clickCount: 1,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved",
      x: dragRect.left + 4 + 20 * 8.4,
      y: dragRect.mid,
      button: "left",
      buttons: 1,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: dragRect.left + 4 + 20 * 8.4,
      y: dragRect.mid,
      button: "left",
      clickCount: 1,
    });
    await sleep(100);
    const dragOverlay = await evaluate(`(() => {
      const el = document.querySelector("#editor .cm-selection");
      if (!el) return null;
      const cs = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      const line = document.querySelector("#editor .cm-line");
      return {
        zIndex: cs.zIndex,
        background: cs.backgroundColor,
        width: r.width,
        lineIndex: Array.from(document.querySelector("#editor .cm-content").children).indexOf(el),
        lineOrder: Array.from(document.querySelector("#editor .cm-content").children).indexOf(line),
      };
    })()`);
    runner.check(
      "drag selection is painted above the line background",
      dragOverlay &&
        dragOverlay.zIndex === "auto" &&
        !dragOverlay.background.includes("rgba(0, 0, 0, 0)") &&
        dragOverlay.width > 50 &&
        dragOverlay.lineIndex > dragOverlay.lineOrder,
      JSON.stringify(dragOverlay),
    );

    await editorCall("setDoc(Array.from({ length: 300 }, (_, i) => 'line ' + i).join('\\n'))");
    await editorCall("focus()");
    await sleep(200);
    const viewRect = await evaluate(`(() => {
      const r = document.getElementById("editor").getBoundingClientRect();
      return { left: r.left, top: r.top, bottom: r.bottom };
    })()`);
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: viewRect.left + 60,
      y: viewRect.top + 20,
      button: "left",
      clickCount: 1,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved",
      x: viewRect.left + 80,
      y: viewRect.bottom + 80,
      button: "left",
      buttons: 1,
    });
    await sleep(400);
    const autoScroll = await evaluate(`(() => {
      const scroller = document.querySelector("#editor .cm-scroller");
      return { scrollTop: scroller.scrollTop };
    })()`);
    const autoState = await editorCall("getState()");
    const autoEnd = Number((autoState.match(/sel=\d+:(\d+)/) || [0, "0"])[1]);
    runner.check(
      "holding the drag below the viewport keeps scrolling",
      autoScroll.scrollTop > 150 && autoEnd > 200,
      `scrollTop=${autoScroll.scrollTop} selectionEnd=${autoEnd}`,
    );
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: viewRect.left + 80,
      y: viewRect.bottom + 80,
      button: "left",
      clickCount: 1,
    });
    await sleep(150);
    const settledTop = await evaluate(
      'document.querySelector("#editor .cm-scroller").scrollTop',
    );
    await sleep(250);
    const laterTop = await evaluate(
      'document.querySelector("#editor .cm-scroller").scrollTop',
    );
    runner.check(
      "auto-scroll stops on mouse release",
      settledTop === laterTop,
      `settled=${settledTop} later=${laterTop}`,
    );

    // 20. light and dark screenshots for visual inspection
    const heroDoc = [
      "// CodeMoonBit — rendered by the MoonBit wasm module.",
      "fn greet(name : String) -> String {",
      '  "Hello, " + name + "!"',
      "}",
      "",
      'test "greet" {',
      '  inspect(greet("MoonBit"), content="Hello, MoonBit!")',
      "}",
      "",
    ].join("\n");
    await editorCall(`setDoc(${JSON.stringify(heroDoc)})`);
    await editorCall('setOption("language", "moonbit")');
    await editorCall("focus()");
    await press("ArrowDown");
    await editorCall('setOption("theme", "light")');
    await sleep(150);
    const shot = await cdp.send("Page.captureScreenshot", { format: "png" });
    const shotPath = process.env.CM_SCREENSHOT || path.join(ROOT, "_build", "browser-e2e.png");
    fs.mkdirSync(path.dirname(shotPath), { recursive: true });
    fs.writeFileSync(shotPath, Buffer.from(shot.data, "base64"));
    console.log(`screenshot written to ${shotPath}`);
    await editorCall('setOption("theme", "dark")');
    await sleep(150);
    const darkShot = await cdp.send("Page.captureScreenshot", { format: "png" });
    const darkPath =
      process.env.CM_SCREENSHOT_DARK || path.join(ROOT, "_build", "browser-e2e-dark.png");
    fs.writeFileSync(darkPath, Buffer.from(darkShot.data, "base64"));
    console.log(`dark screenshot written to ${darkPath}`);
    await editorCall('setOption("theme", "light")');
    await sleep(100);

    runner.check(
      "no uncaught errors during the whole session",
      (await evaluate("window.errors.length")) === 0,
      JSON.stringify(await evaluate("window.errors")),
    );

    // 21. demo application shell (status bar, theme syncing, loading state)
    const demoLoaded = cdp.once("Page.loadEventFired");
    await cdp.send("Page.navigate", { url: `${origin}/demo/` });
    await demoLoaded;
    const demoReady = await waitFor(
      "!!window.editor && !!document.getElementById('status') && /Ln \\d+, Col \\d+/.test(document.getElementById('status').textContent)",
      10000,
    );
    runner.check(
      "the demo page boots an editor with a status readout",
      demoReady,
      await evaluate(
        "document.getElementById('status') ? document.getElementById('status').textContent : 'no status element'",
      ),
    );
    const demoStatus = await evaluate("document.getElementById('status').textContent");
    runner.check(
      "the status bar starts at Ln 1, Col 1",
      /Ln 1, Col 1/.test(demoStatus),
      demoStatus,
    );
    runner.check(
      "the status bar shows the line count and language",
      /\d+ lines/.test(demoStatus) && /MoonBit/.test(demoStatus),
      demoStatus,
    );
    runner.check("the status bar shows the theme", /Light/.test(demoStatus), demoStatus);
    await evaluate('window.editor.key("ArrowDown", "ArrowDown", 4)');
    await waitFor("/2 cursors/.test(document.getElementById('status').textContent)");
    runner.check(
      "the status bar reports multiple cursors",
      /2 cursors/.test(await evaluate("document.getElementById('status').textContent")),
      await evaluate("document.getElementById('status').textContent"),
    );
    await evaluate('window.editor.key("a", "KeyA", 2)');
    await waitFor("/\\d+ selected/.test(document.getElementById('status').textContent)");
    runner.check(
      "the status bar reports the selection size",
      /\d+ selected/.test(await evaluate("document.getElementById('status').textContent")),
      await evaluate("document.getElementById('status').textContent"),
    );
    runner.check(
      "the demo toolbar buttons carry shortcut hints",
      /Ctrl\/\u2318-F/.test(await evaluate('document.getElementById("search").title')) &&
        /Ctrl\/\u2318-Z/.test(await evaluate('document.getElementById("undo").title')) &&
        /Ctrl\/\u2318-Y/.test(await evaluate('document.getElementById("redo").title')),
    );
    await evaluate(`(() => {
      const select = document.getElementById("theme");
      select.value = "dark";
      select.dispatchEvent(new Event("change"));
      return true;
    })()`);
    await sleep(150);
    runner.check(
      "the demo theme select toggles the dark shell",
      await evaluate("document.body.classList.contains('dark')"),
    );
    const fullPageDark = await evaluate(`(() => {
      const bg = getComputedStyle(document.documentElement).backgroundColor;
      const m = bg.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
      if (!m) return { bg, dark: false };
      const [r, g, b] = [Number(m[1]), Number(m[2]), Number(m[3])];
      return { bg, dark: r < 40 && g < 40 && b < 40 };
    })()`);
    runner.check(
      "the whole page canvas is dark, not just the editor",
      fullPageDark.dark && (await evaluate("document.documentElement.classList.contains('dark')")),
      JSON.stringify(fullPageDark),
    );
    runner.check(
      "the status bar follows the theme select",
      /Dark/.test(await evaluate("document.getElementById('status').textContent")),
      await evaluate("document.getElementById('status').textContent"),
    );
    const shortHeight = await evaluate("document.getElementById('editor').clientHeight");
    await evaluate(
      "window.editor.setDoc(Array.from({ length: 400 }, (_, i) => 'line ' + i).join('\\n'))",
    );
    await sleep(250);
    const longHeight = await evaluate("document.getElementById('editor').clientHeight");
    await evaluate("window.editor.setDoc('fn main { }')");
    await sleep(250);
    const shrinkHeight = await evaluate("document.getElementById('editor').clientHeight");
    const maxHeight = await evaluate("Math.max(240, window.innerHeight * 0.7)");
    runner.check(
      "the demo editor shrinks to short documents and caps long ones",
      shortHeight < maxHeight - 20 &&
        Math.abs(longHeight - maxHeight) <= 2 &&
        shrinkHeight < maxHeight - 20,
      `short=${shortHeight} long=${longHeight} shrink=${shrinkHeight} max=${maxHeight}`,
    );
    const demoShot = await cdp.send("Page.captureScreenshot", { format: "png" });
    fs.writeFileSync(
      path.join(ROOT, "_build", "browser-e2e-demo.png"),
      Buffer.from(demoShot.data, "base64"),
    );
    runner.check(
      "no runtime exceptions or console errors were reported",
      pageErrors.length === 0,
      JSON.stringify(pageErrors.slice(0, 5)),
    );

    console.log(`\n${runner.failed === 0 ? "ALL BROWSER TESTS PASSED" : "BROWSER TESTS FAILED"} (${runner.passed} passed, ${runner.failed} failed)`);
    cleanup();
    process.exit(runner.failed === 0 ? 0 : 1);
  } catch (error) {
    console.error("browser e2e error:", error);
    cleanup();
    process.exit(1);
  }
}

main();
