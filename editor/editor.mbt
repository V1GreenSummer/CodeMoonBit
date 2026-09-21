///|
/// A compiler/linter diagnostic rendered as an in-editor mark.
pub(all) struct Diagnostic {
  from : Int
  to : Int
  severity : String
  message : String
} derive(Debug, Eq)

///|
/// A high-level editor instance bound to a DOM container.
pub struct Editor {
  priv view : @view.EditorView
  priv id : Int
  priv mut options : @view.ViewOptions
  priv mut comp_active : Bool
  priv mut comp_from : Int?
  priv mut comp_text : String
  priv mut diagnostics : Array[Diagnostic]
}

///|
fn default_extensions() -> Array[@state.Extension] {
  [
    @state.history_field.extension(),
    @search.search_field.extension(),
    @search.fold_field.extension(),
    @input.keymap(search_keymap()),
    @input.keymap(@input.default_keymap()),
  ]
}

///|
fn search_keymap() -> Array[@input.KeyBinding] {
  [
    @input.key_binding(key="Ctrl-f", run=fn(_) { Some(@search.open_search()) }),
    @input.key_binding(key="Mod-f", run=fn(_) { Some(@search.open_search()) }),
    @input.key_binding(key="Escape", run=fn(state) {
      if @search.is_search_open(state) {
        Some(@search.close_search(state))
      } else {
        None
      }
    }),
    @input.key_binding(key="Enter", run=fn(state) {
      if @search.is_search_open(state) {
        @search.select_next(state)
      } else {
        None
      }
    }),
    @input.key_binding(key="Shift-Enter", run=fn(state) {
      if @search.is_search_open(state) {
        @search.select_prev(state)
      } else {
        None
      }
    }),
  ]
}

///|
pub fn Editor::create(container : @ffi.JsAny, id : Int) -> Editor {
  let options = @view.ViewOptions::default()
  let state = @state.EditorState::create(
    config=default_extensions(),
    doc=@core.Text::empty(),
    selection=@core.EditorSelection::cursor(0),
  )
  let view = @view.EditorView::new(container, id, state, options)
  let editor : Editor = {
    view,
    id,
    options,
    comp_active: false,
    comp_from: None,
    comp_text: "",
    diagnostics: [],
  }
  view.set_decorations_provider(fn(s) { editor.decorations(s) })
  view.set_line_filter(fn(s, line) { is_line_visible(s, line) })
  editor
}

///|
pub fn Editor::id(self : Editor) -> Int {
  self.id
}

///|
pub fn Editor::view(self : Editor) -> @view.EditorView {
  self.view
}

///|
pub fn Editor::options(self : Editor) -> @view.ViewOptions {
  self.options
}

///|
fn language_of(options : @view.ViewOptions) -> @highlight.Language {
  @highlight.language_by_name(options.language_name)
}

///|
fn is_line_visible(state : @state.EditorState, line : Int) -> Bool {
  if state.has_field(@search.fold_field.id()) {
    !@search.is_line_hidden(state, line)
  } else {
    true
  }
}

///|
fn Editor::decorations(
  self : Editor,
  state : @state.EditorState,
) -> Array[@view.Decoration] {
  let result : Array[@view.Decoration] = []
  if state.has_field(@search.search_field.id()) && @search.is_search_open(state) {
    let search = state.field(@search.search_field)
    for i = 0; i < search.matches.length(); i = i + 1 {
      let cls = if i == search.current {
        "cm-search-match cm-search-current"
      } else {
        "cm-search-match"
      }
      result.push(@view.Decoration::Mark(search.matches[i], cls))
    }
  }
  let language = language_of(self.options)
  let folded_lines : Array[Bool] = Array::make(state.line_count(), false)
  if state.has_field(@search.fold_field.id()) {
    let folds = state.field(@search.fold_field)
    for f in folds.folded {
      result.push(@view.Decoration::Fold(f.from_line))
      if f.from_line >= 0 && f.from_line < folded_lines.length() {
        folded_lines[f.from_line] = true
      }
    }
  }
  let doc = state.doc()
  if doc.lines() <= 20000 {
    for
      fold in @search.compute_folds(
        doc,
        language.brackets(),
        language.line_comment(),
      ) {
      if !folded_lines[fold.from_line] {
        result.push(@view.Decoration::Foldable(fold.from_line))
      }
    }
  }
  let brackets = language.brackets()
  if brackets.length() > 0 {
    let pos = state.selection().main_range().head
    match @search.matching_bracket(doc, pos, brackets) {
      Some(range) =>
        result.push(@view.Decoration::Mark(range, "cm-bracket-match"))
      None => ()
    }
  }
  for d in self.diagnostics {
    let cls = if d.severity == "warning" {
      "cm-diagnostic-warning"
    } else {
      "cm-diagnostic-error"
    }
    result.push(@view.Decoration::Mark(@core.Range::new(d.from, d.to), cls))
  }
  result
}

///|
/// Replaces the in-editor diagnostic marks and redraws.
pub fn Editor::set_diagnostics(self : Editor, list : Array[Diagnostic]) -> Unit {
  if self.diagnostics == list {
    return
  }
  self.diagnostics = list
  self.view.render()
}

///|
pub fn Editor::state(self : Editor) -> @state.EditorState {
  self.view.state()
}

///|
pub fn Editor::apply(self : Editor, spec : @state.TransactionSpec) -> Bool {
  self.view.apply_spec(spec)
}

///|
pub fn Editor::focus(self : Editor) -> Unit {
  self.view.focus()
}

///|
pub fn Editor::destroy(self : Editor) -> Unit {
  self.view.destroy()
}

///|
/// Clears any in-progress IME composition session.
fn Editor::reset_composition(self : Editor) -> Unit {
  self.comp_active = false
  self.comp_from = None
  self.comp_text = ""
}

///|
pub fn Editor::set_doc(self : Editor, text : String) -> Unit {
  self.reset_composition()
  self.view.set_doc(text)
}

///|
pub fn Editor::set_selection(self : Editor, anchor : Int, head : Int) -> Unit {
  ignore(
    self.apply(
      @state.TransactionSpec::new(
        selection=@core.EditorSelection::single(anchor, head),
        scroll_into_view=true,
      ),
    ),
  )
}

///|
pub fn Editor::doc_string(self : Editor) -> String {
  self.view.state().to_string()
}

///|
pub fn Editor::rendered_html(self : Editor) -> String {
  @ffi.read_js_string(@ffi.get_html(self.view.content_element()))
}

///|
pub fn Editor::set_option(self : Editor, key : String, value : String) -> Unit {
  let old = self.options
  let mut opts : @view.ViewOptions = {
    line_numbers: old.line_numbers,
    line_wrapping: old.line_wrapping,
    tab_size: old.tab_size,
    read_only: old.read_only,
    theme: old.theme,
    font: old.font,
    line_height: old.line_height,
    language_name: old.language_name,
  }
  let mut indent_changed = false
  match key {
    "lineNumbers" =>
      opts = @view.ViewOptions::with_line_numbers(old, parse_bool(value))
    "lineWrapping" =>
      opts = @view.ViewOptions::with_line_wrapping(old, parse_bool(value))
    "readOnly" =>
      opts = @view.ViewOptions::with_read_only(old, parse_bool(value))
    "tabSize" => {
      opts = @view.ViewOptions::with_tab_size(old, parse_int(value, 4).max(1))
      indent_changed = true
    }
    "language" => opts = @view.ViewOptions::with_language_name(old, value)
    "theme" => opts = @view.ViewOptions::with_theme(old, value)
    "font" => opts = @view.ViewOptions::with_font(old, value)
    "lineHeight" => {
      let d = parse_double(value, 20.0)
      opts = @view.ViewOptions::with_line_height(
        old,
        if d > 0.0 {
          d
        } else {
          20.0
        },
      )
    }
    _ => ()
  }
  self.options = opts
  self.view.set_options(opts)
  if indent_changed {
    let state = @state.EditorState::create(
      config=default_extensions() + [@input.indent_unit(opts.tab_size)],
      doc=self.state().doc(),
      selection=self.state().selection(),
    )
    self.view.set_state(state)
    @ffi.set_style(
      self.view.content_element(),
      @ffi.js_string("tabSize"),
      @ffi.js_string(opts.tab_size.to_string()),
    )
  }
}

///|
fn parse_bool(value : String) -> Bool {
  value == "true" || value == "1"
}

///|
fn parse_int(value : String, fallback : Int) -> Int {
  let mut i = 0
  let mut neg = false
  if value.length() > 0 && value.unsafe_get(0).to_int() == 45 {
    neg = true
    i = 1
  }
  let mut result = 0
  let mut any = false
  while i < value.length() {
    let code = value.unsafe_get(i).to_int()
    if code < 48 || code > 57 {
      return fallback
    }
    result = result * 10 + (code - 48)
    any = true
    i = i + 1
  }
  if !any {
    fallback
  } else if neg {
    -result
  } else {
    result
  }
}

///|
fn parse_double(value : String, fallback : Double) -> Double {
  let mut i = 0
  let mut neg = false
  if value.length() > 0 && value.unsafe_get(0).to_int() == 45 {
    neg = true
    i = 1
  }
  let mut result = 0.0
  let mut any = false
  let mut seen_dot = false
  let mut scale = 1.0
  while i < value.length() {
    let code = value.unsafe_get(i).to_int()
    if code == 46 {
      if seen_dot {
        return fallback
      }
      seen_dot = true
      i = i + 1
      continue
    }
    if code < 48 || code > 57 {
      return fallback
    }
    any = true
    if seen_dot {
      scale = scale * 10.0
      result = result + (code - 48).to_double() / scale
    } else {
      result = result * 10.0 + (code - 48).to_double()
    }
    i = i + 1
  }
  if !any {
    fallback
  } else if neg {
    -result
  } else {
    result
  }
}

///|
pub fn Editor::dispatch_key(self : Editor, event : @input.KeyEvent) -> Bool {
  match @input.run_keymap_facet(self.state(), event) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
      self.view.ensure_cursor_visible_public()
      true
    }
    None => {
      let printable = event.key.length() == 1 &&
        (event.mods & (@input.mod_ctrl | @input.mod_alt | @input.mod_meta)) == 0
      if printable {
        let spec = @input.insert_text(self.state(), event.key)
        let _ = self.view.apply_spec(spec)
        self.view.ensure_cursor_visible_public()
        true
      } else {
        false
      }
    }
  }
}

///|
pub fn Editor::dispatch_mouse(
  self : Editor,
  kind : Int,
  x : Double,
  y : Double,
  detail : Int,
) -> Bool {
  self.view.dispatch_mouse(kind, x, y, detail)
}

///|
pub fn Editor::dispatch_scroll(
  self : Editor,
  top : Double,
  left : Double,
) -> Unit {
  self.view.dispatch_scroll(top, left)
}

///|
pub fn Editor::dispatch_focus(self : Editor, focused : Int) -> Unit {
  self.view.dispatch_focus(focused)
}

///|
pub fn Editor::dispatch_paste(self : Editor, text : @ffi.JsAny) -> Unit {
  if self.options.read_only {
    return
  }
  let spec = @input.insert_text(self.state(), @ffi.read_js_string(text))
  let _ = self.view.apply_spec(spec)
  self.view.ensure_cursor_visible_public()
}

///|
pub fn Editor::dispatch_input(self : Editor, text : @ffi.JsAny) -> Bool {
  if self.options.read_only || self.comp_active {
    return false
  }
  let spec = @input.insert_text(self.state(), @ffi.read_js_string(text))
  let ok = self.view.apply_spec(spec)
  self.view.ensure_cursor_visible_public()
  ok
}

///|
/// Applies one composition edit as an ordinary history-tracked `input.type`
/// change so consecutive updates merge into a single undo group.
fn Editor::apply_composition_change(
  self : Editor,
  from : Int,
  to : Int,
  text : String,
) -> Unit {
  let cs = @core.ChangeSet::of([@core.Change::new(from, to, text)])
  let selection = self.state().selection()
  let ranges : Array[@core.SelectionRange] = []
  for r in selection.ranges() {
    ranges.push(
      @core.SelectionRange::new(cs.map_pos(r.anchor, 1), cs.map_pos(r.head, 1)),
    )
  }
  let spec = @state.TransactionSpec::new(
    changes=cs,
    selection=@core.EditorSelection::create(ranges, selection.main_index()),
    annotations=[@state.UserEvent("input.type")],
    scroll_into_view=true,
  )
  let _ = self.view.apply_spec(spec)
  self.view.ensure_cursor_visible_public()
}

///|
/// Runs an IME composition session. Phase 0 starts, phase 1 updates the
/// provisional text and phase 2 commits the final text; every phase mutates
/// the document through the normal history path so one undo removes the whole
/// composition. Surrounding text is never touched.
pub fn Editor::dispatch_composition(
  self : Editor,
  phase : Int,
  text : @ffi.JsAny,
) -> Unit {
  if self.options.read_only {
    return
  }
  let value = @ffi.read_js_string(text)
  match phase {
    0 => {
      self.comp_active = true
      self.comp_from = None
      self.comp_text = ""
    }
    1 => {
      if !self.comp_active {
        self.comp_active = true
        self.comp_from = None
        self.comp_text = ""
      }
      match self.comp_from {
        Some(from) => {
          self.apply_composition_change(
            from,
            from + self.comp_text.length(),
            value,
          )
          self.comp_text = value
        }
        None =>
          if value.length() > 0 {
            let range = self.state().selection().main_range()
            self.apply_composition_change(range.from(), range.to(), value)
            self.comp_from = Some(range.from())
            self.comp_text = value
          }
      }
    }
    _ => {
      let from = self.comp_from
      match from {
        Some(start) =>
          if self.comp_text != value {
            self.apply_composition_change(
              start,
              start + self.comp_text.length(),
              value,
            )
          }
        None =>
          if value.length() > 0 {
            let spec = @input.insert_text(self.state(), value)
            let _ = self.view.apply_spec(spec)
            self.view.ensure_cursor_visible_public()
          }
      }
      self.reset_composition()
    }
  }
}

///|
pub fn Editor::selected_text(self : Editor) -> @ffi.JsAny {
  self.view.selected_text()
}

///|
pub fn Editor::open_search(self : Editor) -> Unit {
  let _ = self.view.apply_spec(@search.open_search())
}

///|
pub fn Editor::close_search(self : Editor) -> Unit {
  let _ = self.view.apply_spec(@search.close_search(self.state()))
}

///|
pub fn Editor::set_search_query(self : Editor, text : String) -> Unit {
  let query = @search.SearchQuery::new(text~)
  let _ = self.view.apply_spec(@search.set_query(self.state(), query))
}

///|
pub fn Editor::search_next(self : Editor) -> Unit {
  match @search.select_next(self.state()) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
    }
    None => ()
  }
}

///|
pub fn Editor::search_prev(self : Editor) -> Unit {
  match @search.select_prev(self.state()) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
    }
    None => ()
  }
}

///|
pub fn Editor::search_replace(self : Editor, replacement : String) -> Unit {
  match @search.replace_current(self.state(), replacement) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
    }
    None => ()
  }
}

///|
pub fn Editor::replace_all(self : Editor, replacement : String) -> Unit {
  match @search.replace_all(self.state(), replacement) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
    }
    None => ()
  }
}

///|
pub fn Editor::toggle_fold(self : Editor, line : Int) -> Unit {
  let state = self.state()
  if !state.has_field(@search.fold_field.id()) {
    return
  }
  match @search.unfold_line(state, line) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
    }
    None => {
      let brackets = language_of(self.options).brackets()
      match @search.fold_line(state, line, brackets) {
        Some(spec) => {
          let _ = self.view.apply_spec(spec)
        }
        None => ()
      }
    }
  }
}

///|
pub fn Editor::fold_all(self : Editor) -> Unit {
  let brackets = language_of(self.options).brackets()
  match @search.fold_all(self.state(), brackets) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
    }
    None => ()
  }
}

///|
pub fn Editor::unfold_all(self : Editor) -> Unit {
  match @search.unfold_all(self.state()) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
    }
    None => ()
  }
}

///|
pub fn Editor::undo(self : Editor) -> Unit {
  match @input.undo_cmd(self.state()) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
      self.view.ensure_cursor_visible_public()
    }
    None => ()
  }
}

///|
pub fn Editor::redo(self : Editor) -> Unit {
  match @input.redo_cmd(self.state()) {
    Some(spec) => {
      let _ = self.view.apply_spec(spec)
      self.view.ensure_cursor_visible_public()
    }
    None => ()
  }
}
