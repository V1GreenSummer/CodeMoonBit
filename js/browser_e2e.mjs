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
    await evaluate('document.querySelector(".cm-search-next").click()');
    await waitFor("window.editor.getState().includes('sel=8:11')");
    runner.check(
      "search next selects the following match",
      (await editorCall("getState()")).includes("sel=8:11"),
      await editorCall("getState()"),
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

    // 12. folding through the public API
    await editorCall("setDoc('fn a() {\\n  x\\n}\\n')");
    await evaluate("window.editor.foldAll()");
    await waitFor('window.count(".cm-fold") > 0');
    runner.check("fold all renders fold widgets", (await evaluate('window.count(".cm-fold")')) >= 1);
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

    // 15. screenshot for visual inspection
    const shot = await cdp.send("Page.captureScreenshot", { format: "png" });
    const shotPath = process.env.CM_SCREENSHOT || path.join(ROOT, "_build", "browser-e2e.png");
    fs.mkdirSync(path.dirname(shotPath), { recursive: true });
    fs.writeFileSync(shotPath, Buffer.from(shot.data, "base64"));
    console.log(`screenshot written to ${shotPath}`);

    runner.check(
      "no uncaught errors during the whole session",
      (await evaluate("window.errors.length")) === 0,
      JSON.stringify(await evaluate("window.errors")),
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
