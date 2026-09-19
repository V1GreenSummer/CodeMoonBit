///|
/// An opaque reference to a JavaScript value: a DOM node, a JS string, an
/// event object, and so on. Corresponds to WebAssembly `externref`.
#external
pub type JsAny

///|
pub extern "wasm" fn sb_new() -> Int = "dom" "sb_new"

///|
pub extern "wasm" fn sb_push(sb : Int, code : Int) -> Unit = "dom" "sb_push"

///|
pub extern "wasm" fn sb_clear(sb : Int) -> Unit = "dom" "sb_clear"

///|
pub extern "wasm" fn sb_finish(sb : Int) -> JsAny = "dom" "sb_finish"

///|
pub extern "wasm" fn js_len(s : JsAny) -> Int = "dom" "js_len"

///|
pub extern "wasm" fn js_char(s : JsAny, i : Int) -> Int = "dom" "js_char"

///|
pub fn push_string(sb : Int, s : String) -> Unit {
  for i = 0; i < s.length(); i = i + 1 {
    sb_push(sb, s.unsafe_get(i).to_int())
  }
}

///|
pub fn push_js_string(sb : Int, s : JsAny) -> Unit {
  let n = js_len(s)
  for i = 0; i < n; i = i + 1 {
    sb_push(sb, js_char(s, i))
  }
}

///|
pub fn read_js_string(s : JsAny) -> String {
  let n = js_len(s)
  let buf = StringBuilder::new()
  for i = 0; i < n; i = i + 1 {
    buf.write_char(Int::unsafe_to_char(js_char(s, i)))
  }
  buf.to_string()
}

///|
pub fn js_string(s : String) -> JsAny {
  let sb = sb_new()
  push_string(sb, s)
  sb_finish(sb)
}

///|
/// A reusable string builder handle backed by JavaScript.
pub struct JsStringBuilder {
  priv handle : Int
}

///|
pub fn JsStringBuilder::new() -> JsStringBuilder {
  { handle: sb_new() }
}

///|
pub fn JsStringBuilder::clear(self : JsStringBuilder) -> Unit {
  sb_clear(self.handle)
}

///|
pub fn JsStringBuilder::push(self : JsStringBuilder, s : String) -> Unit {
  push_string(self.handle, s)
}

///|
pub fn JsStringBuilder::push_char(self : JsStringBuilder, c : Char) -> Unit {
  sb_push(self.handle, c.to_int())
}

///|
pub fn JsStringBuilder::push_code(self : JsStringBuilder, code : Int) -> Unit {
  sb_push(self.handle, code)
}

///|
pub fn JsStringBuilder::finish(self : JsStringBuilder) -> JsAny {
  sb_finish(self.handle)
}

///|
pub extern "wasm" fn create(tag : JsAny) -> JsAny = "dom" "create"

///|
pub extern "wasm" fn append(parent : JsAny, child : JsAny) -> Unit = "dom" "append"

///|
pub extern "wasm" fn set_html(el : JsAny, html : JsAny) -> Unit = "dom" "set_html"

///|
pub extern "wasm" fn set_text(el : JsAny, text : JsAny) -> Unit = "dom" "set_text"

///|
pub extern "wasm" fn get_text(el : JsAny) -> JsAny = "dom" "get_text"

///|
pub extern "wasm" fn get_html(el : JsAny) -> JsAny = "dom" "get_html"

///|
pub extern "wasm" fn set_class(el : JsAny, cls : JsAny) -> Unit = "dom" "set_class"

///|
pub extern "wasm" fn add_class(el : JsAny, cls : JsAny) -> Unit = "dom" "add_class"

///|
pub extern "wasm" fn remove_class(el : JsAny, cls : JsAny) -> Unit = "dom" "remove_class"

///|
pub extern "wasm" fn set_style(el : JsAny, prop : JsAny, value : JsAny) -> Unit = "dom" "set_style"

///|
pub extern "wasm" fn set_attr(el : JsAny, name : JsAny, value : JsAny) -> Unit = "dom" "set_attr"

///|
pub extern "wasm" fn remove_attr(el : JsAny, name : JsAny) -> Unit = "dom" "remove_attr"

///|
pub extern "wasm" fn part(container : JsAny, name : JsAny) -> JsAny = "dom" "part"

///|
pub extern "wasm" fn set_scroll(
  el : JsAny,
  top : Double,
  left : Double,
) -> Unit = "dom" "set_scroll"

///|
pub extern "wasm" fn scroll_top(el : JsAny) -> Double = "dom" "scroll_top"

///|
pub extern "wasm" fn scroll_left(el : JsAny) -> Double = "dom" "scroll_left"

///|
pub extern "wasm" fn client_width(el : JsAny) -> Double = "dom" "client_width"

///|
pub extern "wasm" fn client_height(el : JsAny) -> Double = "dom" "client_height"

///|
pub extern "wasm" fn scroll_height(el : JsAny) -> Double = "dom" "scroll_height"

///|
pub extern "wasm" fn scroll_width(el : JsAny) -> Double = "dom" "scroll_width"

///|
pub extern "wasm" fn focus(el : JsAny) -> Unit = "dom" "focus"

///|
pub extern "wasm" fn blur(el : JsAny) -> Unit = "dom" "blur"

///|
pub extern "wasm" fn measure_width(font : JsAny, text : JsAny) -> Double = "dom" "measure_width"

///|
pub extern "wasm" fn attach(container : JsAny, editor_id : Int) -> Unit = "dom" "attach"

///|
pub extern "wasm" fn detach(container : JsAny) -> Unit = "dom" "detach"

///|
pub extern "wasm" fn request_measure(editor_id : Int) -> Unit = "dom" "request_measure"

///|
pub extern "wasm" fn notify_update(editor_id : Int) -> Unit = "dom" "notify_update"

///|
pub extern "wasm" fn log(message : JsAny) -> Unit = "dom" "log"

///|
pub fn log_string(message : String) -> Unit {
  log(js_string(message))
}

///|
pub fn measure_text(font : String, text : String) -> Double {
  measure_width(js_string(font), js_string(text))
}
