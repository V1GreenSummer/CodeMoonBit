///|
let registry : Map[Int, @editor.Editor] = Map([])

///|
fn with_editor(id : Int, f : (@editor.Editor) -> Unit) -> Unit {
  match registry.get(id) {
    Some(editor) => f(editor)
    None => ()
  }
}

///|
pub fn cm_create(container : @ffi.JsAny, id : Int) -> Unit {
  let editor = @editor.Editor::create(container, id)
  registry.set(id, editor)
}

///|
pub fn cm_destroy(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.destroy() })
  registry.remove(id)
}

///|
pub fn cm_set_option(id : Int, key : @ffi.JsAny, value : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) {
    editor.set_option(@ffi.read_js_string(key), @ffi.read_js_string(value))
  })
}

///|
pub fn cm_set_doc(id : Int, text : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) { editor.set_doc(@ffi.read_js_string(text)) })
}

///|
pub fn cm_set_selection(id : Int, anchor : Int, head : Int) -> Unit {
  with_editor(id, fn(editor) { editor.set_selection(anchor, head) })
}

///|
fn json_int(obj : Map[String, Json], key : String, fallback : Int) -> Int {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => fallback
  }
}

///|
fn json_text(
  obj : Map[String, Json],
  key : String,
  fallback : String,
) -> String {
  match obj.get(key) {
    Some(Json::String(s)) => s
    _ => fallback
  }
}

///|
/// Replaces the in-editor diagnostics. The host sends a JSON array of
/// `{severity, message, line, column, endLine, endColumn}` objects with
/// 1-based positions, matching the workbench diagnostic shape.
pub fn cm_set_diagnostics(id : Int, payload : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) {
    let text = @ffi.read_js_string(payload)
    let doc = editor.state().doc()
    let list : Array[@editor.Diagnostic] = []
    let parsed : Json? = Some(@json.parse(text)) catch { _ => None }
    match parsed {
      Some(Json::Array(items)) =>
        for item in items {
          match item {
            Json::Object(obj) => {
              let line = json_int(obj, "line", 1)
              let column = json_int(obj, "column", 1)
              let end_line = json_int(obj, "endLine", line)
              let end_column = json_int(obj, "endColumn", column + 1)
              let from = doc.pos(line - 1, column - 1)
              let to = doc.pos(end_line - 1, end_column - 1)
              list.push(@editor.Diagnostic::{
                from,
                to: if to > from {
                  to
                } else {
                  from
                },
                severity: json_text(obj, "severity", "error"),
                message: json_text(obj, "message", ""),
              })
            }
            _ => ()
          }
        }
      _ => ()
    }
    editor.set_diagnostics(list)
  })
}

///|
pub fn cm_get_doc(id : Int) -> @ffi.JsAny {
  match registry.get(id) {
    Some(editor) => @ffi.js_string(editor.doc_string())
    None => @ffi.js_string("")
  }
}

///|
pub fn cm_get_html(id : Int) -> @ffi.JsAny {
  match registry.get(id) {
    Some(editor) => @ffi.js_string(editor.rendered_html())
    None => @ffi.js_string("")
  }
}

///|
pub fn cm_get_selection(id : Int) -> @ffi.JsAny {
  match registry.get(id) {
    Some(editor) => {
      let selection = editor.state().selection()
      let sb = @ffi.JsStringBuilder::new()
      sb.push("{\"main\":")
      sb.push(selection.main_index().to_string())
      sb.push(",\"ranges\":[")
      let ranges = selection.ranges()
      for i = 0; i < ranges.length(); i = i + 1 {
        if i > 0 {
          sb.push(",")
        }
        sb.push("{\"anchor\":")
        sb.push(ranges[i].anchor.to_string())
        sb.push(",\"head\":")
        sb.push(ranges[i].head.to_string())
        sb.push("}")
      }
      sb.push("]}")
      sb.finish()
    }
    None => @ffi.js_string("")
  }
}

///|
pub fn cm_get_state(id : Int) -> @ffi.JsAny {
  match registry.get(id) {
    Some(editor) => {
      let state = editor.state()
      let sb = @ffi.JsStringBuilder::new()
      sb.push("len=")
      sb.push(state.length().to_string())
      sb.push(";lines=")
      sb.push(state.line_count().to_string())
      sb.push(";sel=")
      let ranges = state.selection().ranges()
      for i = 0; i < ranges.length(); i = i + 1 {
        if i > 0 {
          sb.push(",")
        }
        sb.push(ranges[i].anchor.to_string())
        sb.push(":")
        sb.push(ranges[i].head.to_string())
      }
      sb.push(";main=")
      sb.push(state.selection().main_index().to_string())
      sb.push(";search=")
      if state.has_field(@search.search_field.id()) {
        let search = state.field(@search.search_field)
        sb.push(if search.open { "1" } else { "0" })
        sb.push("/")
        sb.push(search.matches.length().to_string())
        sb.push("/")
        sb.push(search.current.to_string())
      } else {
        sb.push("-")
      }
      sb.push(";folds=")
      if state.has_field(@search.fold_field.id()) {
        sb.push(state.field(@search.fold_field).folded.length().to_string())
      } else {
        sb.push("-")
      }
      sb.finish()
    }
    None => @ffi.js_string("")
  }
}

///|
pub fn cm_focus(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.focus() })
}

///|
pub fn cm_key(id : Int, key : @ffi.JsAny, code : @ffi.JsAny, mods : Int) -> Int {
  match registry.get(id) {
    Some(editor) => {
      let event : @input.KeyEvent = {
        key: @ffi.read_js_string(key),
        code: @ffi.read_js_string(code),
        mods,
      }
      if editor.dispatch_key(event) {
        1
      } else {
        0
      }
    }
    None => 0
  }
}

///|
pub fn cm_mouse(
  id : Int,
  kind : Int,
  x : Double,
  y : Double,
  button : Int,
  detail : Int,
) -> Int {
  match registry.get(id) {
    Some(editor) => {
      let _ = button
      if editor.dispatch_mouse(kind, x, y, detail) {
        1
      } else {
        0
      }
    }
    None => 0
  }
}

///|
pub fn cm_scroll(id : Int, top : Double, left : Double) -> Unit {
  with_editor(id, fn(editor) { editor.dispatch_scroll(top, left) })
}

///|
pub fn cm_focus_event(id : Int, focused : Int) -> Unit {
  with_editor(id, fn(editor) { editor.dispatch_focus(focused) })
}

///|
pub fn cm_paste(id : Int, text : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) { editor.dispatch_paste(text) })
}

///|
pub fn cm_input(id : Int, text : @ffi.JsAny) -> Int {
  match registry.get(id) {
    Some(editor) => if editor.dispatch_input(text) { 1 } else { 0 }
    None => 0
  }
}

///|
pub fn cm_composition(id : Int, phase : Int, text : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) { editor.dispatch_composition(phase, text) })
}

///|
pub fn cm_selected_text(id : Int) -> @ffi.JsAny {
  match registry.get(id) {
    Some(editor) => editor.selected_text()
    None => @ffi.js_string("")
  }
}

///|
pub fn cm_resize(id : Int, width : Double, height : Double) -> Unit {
  let _ = (width, height)
  with_editor(id, fn(editor) { editor.view().render() })
}

///|
pub fn cm_fold_click(id : Int, line : Int) -> Unit {
  with_editor(id, fn(editor) { editor.toggle_fold(line) })
}

///|
pub fn cm_search_open(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.open_search() })
}

///|
pub fn cm_search_close(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.close_search() })
}

///|
pub fn cm_search_query(id : Int, text : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) {
    editor.set_search_query(@ffi.read_js_string(text))
  })
}

///|
pub fn cm_search_next(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.search_next() })
}

///|
pub fn cm_search_prev(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.search_prev() })
}

///|
pub fn cm_search_replace(id : Int, text : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) {
    editor.search_replace(@ffi.read_js_string(text))
  })
}

///|
pub fn cm_search_replace_all(id : Int, text : @ffi.JsAny) -> Unit {
  with_editor(id, fn(editor) { editor.replace_all(@ffi.read_js_string(text)) })
}

///|
pub fn cm_undo(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.undo() })
}

///|
pub fn cm_redo(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.redo() })
}

///|
pub fn cm_fold_all(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.fold_all() })
}

///|
pub fn cm_unfold_all(id : Int) -> Unit {
  with_editor(id, fn(editor) { editor.unfold_all() })
}

///|
fn main {

}
