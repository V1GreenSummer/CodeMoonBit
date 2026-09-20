import { createEditor } from "../js/browser.js";

const INITIAL = `// CodeMoonBit — a CodeMirror-like editor written in MoonBit.
// Try editing, use Mod-F to search, Alt-ArrowUp/Down for extra cursors.

fn greet(name : String) -> String {
  "Hello, " + name + "!"
}

test "greet" {
  inspect(greet("MoonBit"), content="Hello, MoonBit!")
}
`;

const prefersDark =
  typeof window !== "undefined" &&
  typeof window.matchMedia === "function" &&
  window.matchMedia("(prefers-color-scheme: dark)").matches;

const state = {
  value: INITIAL,
  language: "moonbit",
  theme: prefersDark ? "dark" : "light",
  lineNumbers: true,
  lineWrapping: false,
  readOnly: false,
};

const status = document.getElementById("status");
const container = document.getElementById("editor");

const MIN_EDITOR_HEIGHT = 240;
const MAX_EDITOR_HEIGHT = () => Math.max(MIN_EDITOR_HEIGHT, window.innerHeight * 0.7);

function fitEditorHeight() {
  const content = container.querySelector(".cm-content");
  if (!content) return;
  const contentHeight = parseFloat(content.style.height) || content.scrollHeight || 0;
  const target = Math.min(MAX_EDITOR_HEIGHT(), Math.max(MIN_EDITOR_HEIGHT, contentHeight + 24));
  container.style.minHeight = "0px";
  container.style.height = `${Math.round(target)}px`;
}

window.addEventListener("resize", fitEditorHeight);
const languageSelect = document.getElementById("language");
const themeSelect = document.getElementById("theme");

function setStatus(text) {
  status.textContent = text;
}

setStatus("Loading editor…");

let editor;
try {
  editor = await createEditor(container, { ...state });
} catch (error) {
  const message = error && error.message ? error.message : String(error);
  status.classList.add("error");
  setStatus(`Failed to load editor: ${message}`);
  console.error("CodeMoonBit demo failed to load", error);
  throw error;
}

window.editor = editor;

function languageLabel() {
  const option =
    languageSelect.selectedOptions && languageSelect.selectedOptions[0];
  return option ? option.textContent.trim() : state.language;
}

function lineColAt(doc, pos) {
  const limit = Math.max(0, Math.min(pos, doc.length));
  let line = 1;
  let lineStart = 0;
  for (let i = 0; i < limit; i += 1) {
    if (doc.charCodeAt(i) === 10) {
      line += 1;
      lineStart = i + 1;
    }
  }
  return { line, col: limit - lineStart + 1 };
}

function selectionSummary(selection) {
  if (!selection || !Array.isArray(selection.ranges)) return "";
  let selected = 0;
  for (const range of selection.ranges) {
    selected += Math.abs(range.head - range.anchor);
  }
  if (selected > 0) return `${selected} selected`;
  if (selection.ranges.length > 1) return `${selection.ranges.length} cursors`;
  return "";
}

function refreshStatus() {
  const doc = editor.getDoc();
  const selection = editor.getSelection();
  const main =
    selection && selection.ranges && selection.ranges[selection.main]
      ? selection.ranges[selection.main]
      : { head: 0 };
  const { line, col } = lineColAt(doc, main.head);
  const parts = [`Ln ${line}, Col ${col}`];
  const summary = selectionSummary(selection);
  if (summary) parts.push(summary);
  parts.push(`${doc.split("\n").length} lines`);
  parts.push(languageLabel());
  parts.push(state.theme === "dark" ? "Dark" : "Light");
  setStatus(parts.join(" · "));
}

function applyTheme(theme) {
  const dark = theme === "dark";
  document.body.classList.toggle("dark", dark);
  document.documentElement.classList.toggle("dark", dark);
  document.body.dataset.theme = theme;
  themeSelect.value = theme;
}

applyTheme(state.theme);
refreshStatus();
fitEditorHeight();

languageSelect.addEventListener("change", (event) => {
  state.language = event.target.value;
  editor.setOption("language", state.language);
  refreshStatus();
  fitEditorHeight();
});

themeSelect.addEventListener("change", (event) => {
  state.theme = event.target.value;
  editor.setOption("theme", state.theme);
  applyTheme(state.theme);
  refreshStatus();
  fitEditorHeight();
});

for (const id of ["line-numbers", "line-wrapping", "read-only"]) {
  document.getElementById(id).addEventListener("change", (event) => {
    const key = id.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    state[key] = event.target.checked;
    editor.setOption(key, event.target.checked);
    refreshStatus();
  });
}

document.getElementById("search").addEventListener("click", () => {
  editor.focus();
  editor.openSearch();
});

document.getElementById("undo").addEventListener("click", () => {
  editor.undo();
  refreshStatus();
  fitEditorHeight();
});

document.getElementById("redo").addEventListener("click", () => {
  editor.redo();
  refreshStatus();
  fitEditorHeight();
});

document.getElementById("fold-all").addEventListener("click", () => {
  editor.foldAll();
  refreshStatus();
  fitEditorHeight();
});

document.getElementById("unfold-all").addEventListener("click", () => {
  editor.unfoldAll();
  refreshStatus();
  fitEditorHeight();
});

container.addEventListener("keyup", refreshStatus);
container.addEventListener("mouseup", refreshStatus);
editor.onUpdate(() => {
  refreshStatus();
  fitEditorHeight();
});
