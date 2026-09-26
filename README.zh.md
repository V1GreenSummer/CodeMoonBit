# CodeMoonBit

[English](README.md) · 中文

一个用 [MoonBit](https://www.moonbitlang.com/) 从零实现的类 CodeMirror 代码编辑器：
编译为 `wasm-gc`，通过一层很薄的 DOM FFI 由 JavaScript 驱动。

文档模型、事务与扩展系统、语法高亮、搜索替换、代码折叠、键位、多光标、
撤销重做以及全部渲染逻辑都在 MoonBit 中实现；JavaScript 只负责 DOM 原语、
文本测量与事件转发。

## 功能特性

- **文档模型**：不可变按行文本、UTF-16 code unit 偏移、行列映射、
  `Range`/`RangeSet`、带逆变换与位置映射的 `Change`/`ChangeSet`。
- **状态与事务**：CodeMirror 风格的 `Facet`、`StateField`、`StateEffect`、
  `Extension`、`Transaction`、`EditorState`，用闭包实现类型擦除的异构状态
  （不依赖 `Any`）。
- **编辑**：插入/删除、回车自动缩进、Tab 停位、按词/按行删除、按词移动与
  选择（`Ctrl/⌘+方向键`、`Shift+Ctrl/⌘+方向键`）、缩进调整、行注释切换、
  多光标（`Alt-↑/↓`、`Mod-d`）、选区、双击选词/三击选行。
- **历史**：连续输入/删除按组撤销与重做，带总组数预算；非历史与远端改动会
  安全清空过期撤销步骤，避免误删内容。
- **语法高亮**：基于行状态的增量 tokenizer，覆盖约 50 种语言（C 系、脚本、
  Shell/构建、数据/配置、Web、MoonBit、JSON、Markdown、**Typst**），由可配置
  的通用分词器驱动，带逐行缓存与编辑失效。
- **搜索替换**：字面量与小正则子集（`^ $ . * + ? [] | \d \w \s \b`）、
  命中高亮、上一个/下一个、替换与全部替换，面板内显示 `当前/总数` 与快捷键提示。
- **代码折叠**：按括号与缩进计算折叠范围，可折叠行在 gutter 显示标记
  （未折叠 `▾`，已折叠 `▸` 并带行内 `…`），点击 gutter 即可折叠/展开，
  支持全部折叠/展开。
- **渲染**：按视口虚拟渲染并维护全文滚动高度、行号槽、当前行与当前行号高亮、
  焦点环与随焦点变化的光标/选区颜色、选区、多光标、括号匹配、主题化细滚动条、
  可选软换行、明暗主题、只读模式。
- **性能**：逐行 HTML 缓存（只重建被编辑的行，未变化行复用已生成的字符串）
  以及常驻光标层（仅在移动时更新，重渲染不会重置光标闪烁动画）。
- **输入**：可扩展键位 facet 与类 CodeMirror 默认键位、平台感知的 `Mod`
  绑定、可配置缩进、完整 IME 组合输入会话（一次组合一次撤销）、剪贴板
  复制/剪切/粘贴、鼠标选择与拖拽、滚动转发。
- **诊断**：宿主通过 `setDiagnostics` 注入诊断，以波浪下划线标记渲染并适配
  明暗主题；诊断集合未变化时不触发重绘。
- **宿主 API**：`onUpdate` 订阅、结构化 `getSelection`、显式 `setSelection`，
  以及作用域为 `.cm-editor` 的可分发样式表 `js/codemoonbit.css`。

## 目录结构

| 目录         | 内容                                                     |
| ------------ | -------------------------------------------------------- |
| `core/`      | 文本、范围、变更、选区（纯逻辑，单元测试）               |
| `state/`     | facet、field、effect、事务、历史（纯逻辑）               |
| `highlight/` | 增量分词器与行缓存（纯逻辑）                             |
| `search/`    | 搜索替换、折叠、括号匹配（纯逻辑）                       |
| `input/`     | 键位、编辑命令、多光标（纯逻辑）                         |
| `ffi/`       | wasm DOM 导入与 code unit 字符串编解码                   |
| `view/`      | 布局、几何、渲染、鼠标/滚动分发                          |
| `editor/`    | 组装编辑器：扩展、选项、事件入口                         |
| `main/`      | wasm 导出（`cm_*`）与编辑器注册表                        |
| `js/`        | DOM runtime、样式表、Node DOM shim、e2e 测试、浏览器加载 |
| `demo/`      | 静态演示页面                                             |

## 环境要求与构建

项目要求 **`moonc` 0.10.14 及以上**（用 `moon version --all` 查看）。
stable 通道版本低于该要求，请先安装 dev 通道：

```sh
export MOONBIT_INSTALL_DEV=1
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
moon version --all   # 应显示 moonc v0.10.14+...
```

```sh
moon check --target wasm-gc          # 类型检查（零警告）
moon test --target wasm-gc           # 137 个纯包单元测试
moon build --target wasm-gc          # 产物 _build/wasm-gc/debug/build/main/main.wasm
node js/e2e.mjs                      # 39 个 Node DOM shim 集成测试
node js/browser_e2e.mjs              # 84 个真实浏览器测试（CDP 驱动 Chromium）
moon fmt && moon info
```

## 在浏览器中使用

```sh
python3 -m http.server 8000
# 打开 http://localhost:8000/demo/
```

```html
<link rel="stylesheet" href="./js/codemoonbit.css" />
<div id="editor" style="height: 400px"></div>
<script type="module">
  import { createEditor } from "./js/browser.js";

  const editor = await createEditor(document.getElementById("editor"), {
    value: "fn main {\n  println(\"hello\")\n}\n",
    language: "moonbit",
    lineNumbers: true,
    theme: "light",
  });

  editor.focus();
  editor.onUpdate(() => console.log("document changed"));
</script>
```

返回的句柄包含 `getDoc`、`setDoc`、`setSelection`、`getHTML`、`getSelection`、
`getState`、`onUpdate`、`focus`、`destroy`、`openSearch`、`closeSearch`、
`searchNext`、`searchPrev`、`replace`、`replaceAll`、`undo`、`redo`、
`foldAll`、`unfoldAll`、`foldClick`、`key`、`mouse`、`paste`、`selectedText`、
`setDiagnostics`、`setOption`。

## 使用方

- [Typst.bit](https://github.com/V1GreenSummer/typst-bit) 将 CodeMoonBit
  作为其唯一编辑器（在仓库内打了补丁以支持 Typst 语言、诊断、IME 光标映射
  以及上述渲染优化）。

## FFI 设计

- JS 调用的导出函数在 `main/moon.pkg` 中声明，参数/返回值只使用 `Int`、
  `Bool`、`Double` 与 `#external type JsAny`（externref）。
- MoonBit → JS 字符串用 `sb_new`/`sb_push`/`sb_push_js`/`sb_finish` 构建
  （`sb_push_js` 复用已构建的 JS 字符串，用于逐行 HTML 缓存）；JS → MoonBit
  以 externref 传入，MoonBit 用 `js_len`/`js_char` 读取。所有偏移均为
  UTF-16 code unit。
- 事件在 `js/dom_runtime.js` 中接线：DOM 监听转发到 `cm_key`、`cm_mouse`、
  `cm_scroll`、`cm_paste`、`cm_composition` 等。MoonBit 计算可见视口的 HTML
  后经 `set_html` 写入，并通过 `notify_update` 通知宿主。

## 已知限制

- 每次事务都会重建可见视口的 HTML 字符串，但未变化的行由逐行 HTML 缓存复用，
  只重新生成被编辑的行；尚无逐行 DOM patch。
- 软换行按测量字符宽度切分视觉行，混排比例字体/CJK 时切分点可能与浏览器
  原生换行不同。
- Shift+点击扩选尚未接通（mousedown 不带修饰键信息）。
- 搜索正则是小子集，不是完整正则引擎。
- 文档结构为行数组并复用未变化的字符串，不是 rope；超大文档每次编辑为
  O(行数)。

## 参考

- 公开 API 受 CodeMirror 6 启发；仓库不包含任何 CodeMirror 源码，实现均为
  原创 MoonBit 代码。
- 依赖 MoonBit core 包（json、string、encoding）与 wasm-gc 工具链；
  未引入任何第三方编辑器源码。
- 被 [Typst.bit](https://github.com/V1GreenSummer/typst-bit) 用作唯一编辑器，
  并发布在 mooncakes.io：`V1GreenSummer/codemoonbit`。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
