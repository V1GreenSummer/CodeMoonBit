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

const state = {
  value: INITIAL,
  language: "moonbit",
  theme: "light",
  lineNumbers: true,
  lineWrapping: false,
  readOnly: false,
};

const status = document.getElementById("status");
const container = document.getElementById("editor");
const editor = await createEditor(container, { ...state });

function refreshStatus() {
  const info = editor.getState();
  status.textContent = `${info}  |  lines rendered: ${editor.getHTML().split("cm-line").length - 1}`;
}

refreshStatus();

for (const id of ["language", "theme"]) {
  document.getElementById(id).addEventListener("change", (event) => {
    state[id] = event.target.value;
    editor.setOption(id, event.target.value);
    refreshStatus();
  });
}

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
});

document.getElementById("redo").addEventListener("click", () => {
  editor.redo();
  refreshStatus();
});

document.getElementById("fold-all").addEventListener("click", () => {
  editor.foldAll();
  refreshStatus();
});

document.getElementById("unfold-all").addEventListener("click", () => {
  editor.unfoldAll();
  refreshStatus();
});

container.addEventListener("keyup", refreshStatus);
container.addEventListener("mouseup", refreshStatus);
