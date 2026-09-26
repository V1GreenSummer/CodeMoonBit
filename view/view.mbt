///|
/// Geometry and rendering for a single line, computed in view coordinates.
pub struct LineLayout {
  xs : Array[Double]
  width : Double
}

///|
/// The editor view: owns the DOM, the scroll position and the rendering of an
/// `EditorState`.
pub struct EditorView {
  priv container : @ffi.JsAny
  priv scroller : @ffi.JsAny
  priv content : @ffi.JsAny
  priv gutter : @ffi.JsAny
  priv input : @ffi.JsAny
  priv editor_id : Int
  priv mut state : @state.EditorState
  priv mut options : ViewOptions
  priv mut language : @highlight.Language
  priv mut highlighter : @highlight.HighlightCache
  priv mut decorations : Array[Decoration]
  priv mut decorations_provider : ((@state.EditorState) -> Array[Decoration])?
  priv mut line_filter : ((@state.EditorState, Int) -> Bool)?
  priv char_widths : Map[Int, Double]
  priv mut space_width : Double
  priv mut scroll_top : Double
  priv mut scroll_left : Double
  priv mut client_height : Double
  priv mut client_width : Double
  priv mut dragging : Bool
  priv mut vis_lines : Array[Int]
  priv mut vis_tops : Array[Double]
  priv mut vis_heights : Array[Double]
  priv mut total_height : Double
  /// Per-line HTML cache: (signature, html) keyed by document line; unchanged
  /// lines are pushed into the frame with one FFI call instead of being
  /// rebuilt glyph by glyph.
  priv mut line_html_cache : Array[(String, @ffi.JsAny)?]
  priv mut gutter_html_cache : Array[(String, @ffi.JsAny)?]
  priv mut cache_gen : Int
  /// Allows host-initiated document replacement (`set_doc`) in read-only
  /// mode: read-only blocks user input, not programmatic value setting.
  priv mut host_edit : Bool
}

///|
pub fn EditorView::new(
  container : @ffi.JsAny,
  editor_id : Int,
  state : @state.EditorState,
  options : ViewOptions,
) -> EditorView {
  @ffi.attach(container, editor_id)
  let scroller = @ffi.part(container, @ffi.js_string("scroller"))
  let content = @ffi.part(container, @ffi.js_string("content"))
  let gutter = @ffi.part(container, @ffi.js_string("gutter"))
  let input = @ffi.part(container, @ffi.js_string("input"))
  let language = @highlight.language_by_name(options.language_name)
  let space = @ffi.measure_text(options.font, " ")
  let view : EditorView = {
    container,
    scroller,
    content,
    gutter,
    input,
    editor_id,
    state,
    options,
    language,
    highlighter: @highlight.HighlightCache::new(language),
    decorations: [],
    decorations_provider: None,
    line_filter: None,
    char_widths: Map([]),
    space_width: if space > 0.0 {
      space
    } else {
      8.0
    },
    scroll_top: 0.0,
    scroll_left: 0.0,
    client_height: 0.0,
    client_width: 0.0,
    dragging: false,
    vis_lines: [],
    vis_tops: [],
    vis_heights: [],
    total_height: 0.0,
    line_html_cache: [],
    gutter_html_cache: [],
    cache_gen: 0,
    host_edit: false,
  }
  view.client_width = @ffi.client_width(scroller)
  view.client_height = @ffi.client_height(scroller)
  view.render()
  view
}

///|
pub fn EditorView::id(self : EditorView) -> Int {
  self.editor_id
}

///|
pub fn EditorView::content_element(self : EditorView) -> @ffi.JsAny {
  self.content
}

///|
pub fn EditorView::state(self : EditorView) -> @state.EditorState {
  self.state
}

///|
pub fn EditorView::options(self : EditorView) -> ViewOptions {
  self.options
}

///|
pub fn EditorView::set_options(
  self : EditorView,
  options : ViewOptions,
) -> Unit {
  if options.font != self.options.font {
    self.char_widths.clear()
    let space = @ffi.measure_text(options.font, " ")
    self.space_width = if space > 0.0 { space } else { 8.0 }
  }
  self.options = options
  self.language = @highlight.language_by_name(options.language_name)
  self.highlighter = @highlight.HighlightCache::new(self.language)
  self.invalidate_render_cache()
  self.render()
}

///|
pub fn EditorView::set_decorations_provider(
  self : EditorView,
  provider : (@state.EditorState) -> Array[Decoration],
) -> Unit {
  self.decorations_provider = Some(provider)
}

///|
pub fn EditorView::set_line_filter(
  self : EditorView,
  filter : (@state.EditorState, Int) -> Bool,
) -> Unit {
  self.line_filter = Some(filter)
}

///|
pub fn EditorView::set_state(
  self : EditorView,
  state : @state.EditorState,
) -> Unit {
  self.state = state
  self.highlighter.invalidate(0)
  self.invalidate_render_cache()
  self.render()
  @ffi.notify_update(self.editor_id)
}

///|
pub fn EditorView::focus(self : EditorView) -> Unit {
  @ffi.focus(self.scroller)
}

///|
pub fn EditorView::destroy(self : EditorView) -> Unit {
  @ffi.detach(self.container)
}

///|
fn EditorView::is_visible(self : EditorView, line : Int) -> Bool {
  match self.line_filter {
    Some(filter) => filter(self.state, line)
    None => true
  }
}

///|
fn EditorView::char_width(self : EditorView, code : Int) -> Double {
  match self.char_widths.get(code) {
    Some(w) => w
    None => {
      let s = StringBuilder()
      s.write_char(Int::unsafe_to_char(code))
      let w = @ffi.measure_text(self.options.font, s.to_string())
      self.char_widths.set(code, w)
      w
    }
  }
}

///|
fn EditorView::layout_line(self : EditorView, line : Int) -> LineLayout {
  let s = self.state.doc().line(line)
  let n = s.length()
  let xs = Array::make(n + 1, 0.0)
  let mut x = 0.0
  let mut i = 0
  while i < n {
    xs[i] = x
    let code = s.unsafe_get(i).to_int()
    if code == 9 {
      let col = if self.space_width > 0.0 {
        (x / self.space_width + 0.5).to_int()
      } else {
        0
      }
      let tab = self.options.tab_size
      let width = if tab > 0 { tab - col % tab } else { 1 }
      x = x + self.space_width * width.to_double()
      i = i + 1
    } else if code >= 0xD800 && code <= 0xDBFF && i + 1 < n {
      let next = s.unsafe_get(i + 1).to_int()
      if next >= 0xDC00 && next <= 0xDFFF {
        xs[i + 1] = x
        let pair = StringBuilder()
        pair.write_char(Int::unsafe_to_char(code))
        pair.write_char(Int::unsafe_to_char(next))
        x = x + @ffi.measure_text(self.options.font, pair.to_string())
        i = i + 2
      } else {
        x = x + self.char_width(code)
        i = i + 1
      }
    } else {
      x = x + self.char_width(code)
      i = i + 1
    }
  }
  xs[n] = x
  { xs, width: x, }
}

///|
fn EditorView::line_height_of(self : EditorView, layout : LineLayout) -> Double {
  if self.options.line_wrapping && self.client_width > 0.0 {
    let segments = (layout.width / self.client_width).ceil().to_int().max(1)
    self.options.line_height * segments.to_double()
  } else {
    self.options.line_height
  }
}

///|
fn EditorView::visible_lines(self : EditorView) -> Array[Int] {
  let result : Array[Int] = []
  if self.options.line_wrapping {
    for i = 0; i < self.state.line_count(); i = i + 1 {
      if self.is_visible(i) {
        result.push(i)
      }
    }
  } else {
    for i = 0; i < self.state.line_count(); i = i + 1 {
      if self.is_visible(i) {
        result.push(i)
      }
    }
  }
  result
}

///|
fn EditorView::compute_viewport(self : EditorView, lines : Array[Int]) -> Unit {
  let tops : Array[Double] = []
  let heights : Array[Double] = []
  let mut total = 0.0
  if !self.options.line_wrapping {
    for i = 0; i < lines.length(); i = i + 1 {
      tops.push(i.to_double() * self.options.line_height)
      heights.push(self.options.line_height)
    }
    total = lines.length().to_double() * self.options.line_height
  } else {
    let mut y = 0.0
    for i = 0; i < lines.length(); i = i + 1 {
      tops.push(y)
      let layout = self.layout_line(lines[i])
      let height = self.line_height_of(layout)
      heights.push(height)
      y = y + height
    }
    total = y
  }
  self.vis_lines = lines
  self.vis_tops = tops
  self.vis_heights = heights
  self.total_height = total
}

///|
fn push_double(sb : @ffi.JsStringBuilder, v : Double) -> Unit {
  let rounded = (v * 100.0).round() / 100.0
  sb.push(rounded.to_string())
}

///|
fn push_escaped(sb : @ffi.JsStringBuilder, s : String) -> Unit {
  let n = s.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    let escaped = match s.unsafe_get(i).to_int() {
      38 => "&amp;"
      60 => "&lt;"
      62 => "&gt;"
      34 => "&quot;"
      _ => ""
    }
    if escaped != "" {
      if i > start {
        sb.push(s[start:i].to_owned())
      }
      sb.push(escaped)
      start = i + 1
    }
    i = i + 1
  }
  if start < n {
    sb.push(s[start:n].to_owned())
  }
}

///|
fn token_class(typ : @highlight.TokenType) -> String {
  match typ {
    @highlight.TokenType::Keyword => "tok-keyword"
    @highlight.TokenType::TypeName => "tok-type"
    @highlight.TokenType::VariableName => "tok-variable"
    @highlight.TokenType::PropertyName => "tok-property"
    @highlight.TokenType::Atom => "tok-atom"
    @highlight.TokenType::Number => "tok-number"
    @highlight.TokenType::String => "tok-string"
    @highlight.TokenType::Comment => "tok-comment"
    @highlight.TokenType::Operator => "tok-operator"
    @highlight.TokenType::Punctuation => "tok-punctuation"
    @highlight.TokenType::Meta => "tok-meta"
    @highlight.TokenType::Tag => "tok-tag"
    @highlight.TokenType::Attribute => "tok-attribute"
    @highlight.TokenType::Invalid => "tok-invalid"
  }
}

///|
fn token_name(typ : @highlight.TokenType) -> String {
  match typ {
    @highlight.TokenType::Keyword => "keyword"
    @highlight.TokenType::TypeName => "type"
    @highlight.TokenType::VariableName => "variable"
    @highlight.TokenType::PropertyName => "property"
    @highlight.TokenType::Atom => "atom"
    @highlight.TokenType::Number => "number"
    @highlight.TokenType::String => "string"
    @highlight.TokenType::Comment => "comment"
    @highlight.TokenType::Operator => "operator"
    @highlight.TokenType::Punctuation => "punctuation"
    @highlight.TokenType::Meta => "meta"
    @highlight.TokenType::Tag => "tag"
    @highlight.TokenType::Attribute => "attribute"
    @highlight.TokenType::Invalid => "invalid"
  }
}

///|
fn EditorView::decoration_classes(self : EditorView, line : Int) -> String {
  let buf = StringBuilder()
  for d in self.decorations {
    match d {
      Line(l, cls) =>
        if l == line {
          buf.write_char(' ')
          buf.write_string(cls)
        }
      _ => ()
    }
  }
  buf.to_string()
}

///|
fn EditorView::fold_widget(self : EditorView, line : Int) -> Bool {
  for d in self.decorations {
    match d {
      Fold(l) => if l == line { return true }
      _ => ()
    }
  }
  false
}

///|
/// True when `line` starts a foldable block that is not currently folded.
fn EditorView::foldable_line(self : EditorView, line : Int) -> Bool {
  for d in self.decorations {
    match d {
      Foldable(l) => if l == line { return true }
      _ => ()
    }
  }
  false
}

///|
fn EditorView::render_marks(
  self : EditorView,
  sb : @ffi.JsStringBuilder,
) -> Unit {
  let doc = self.state.doc()
  let lh = self.options.line_height
  for d in self.decorations {
    match d {
      Mark(range, cls) => {
        let (from_line, from_col) = doc.line_col(range.from)
        let (to_line, to_col) = doc.line_col(range.to)
        for line = from_line; line <= to_line; line = line + 1 {
          if !self.is_visible(line) {
            continue
          }
          let top = self.top_of_line(line)
          if top < 0.0 {
            continue
          }
          let layout = self.layout_line(line)
          let line_len = doc.line_length(line)
          let c1 = if line == from_line { from_col } else { 0 }
          let c2 = if line == to_line { to_col } else { line_len }
          let x1 = layout.xs[c1.min(layout.xs.length() - 1)]
          let x2 = layout.xs[c2.min(layout.xs.length() - 1)]
          if self.options.line_wrapping && self.client_width > 0.0 {
            let mut seg = (x1 / self.client_width).floor().to_int()
            let end_seg = (x2 / self.client_width).floor().to_int()
            while seg <= end_seg {
              let seg_start = self.client_width * seg.to_double()
              let seg_end = seg_start + self.client_width
              let rx1 = x1.max(seg_start)
              let rx2 = if c2 == line_len && line == to_line {
                seg_end
              } else {
                x2.min(seg_end)
              }
              if rx2 > rx1 {
                push_mark(
                  sb,
                  cls,
                  rx1 - seg_start,
                  top + lh * seg.to_double(),
                  rx2 - rx1,
                  lh,
                )
              }
              seg = seg + 1
            }
          } else {
            let end = if line < to_line { layout.width } else { x2 }
            push_mark(
              sb,
              cls,
              x1,
              top,
              if end > x1 {
                end - x1
              } else {
                2.0
              },
              lh,
            )
          }
        }
      }
      _ => ()
    }
  }
}

///|
fn push_mark(
  sb : @ffi.JsStringBuilder,
  cls : String,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
) -> Unit {
  sb.push("<div class=\"cm-mark ")
  sb.push(cls)
  sb.push("\" style=\"left:")
  push_double(sb, x)
  sb.push("px;top:")
  push_double(sb, y)
  sb.push("px;width:")
  push_double(sb, w)
  sb.push("px;height:")
  push_double(sb, h)
  sb.push("px\"></div>")
}

///|
fn EditorView::render_selections(
  self : EditorView,
  sb : @ffi.JsStringBuilder,
) -> Unit {
  let doc = self.state.doc()
  let lh = self.options.line_height
  let ranges = self.state.selection().ranges()
  let main = self.state.selection().main_range()
  let mut main_cursor_placed = false
  for r in ranges {
    if r.is_empty() {
      let pos = r.head
      let (line, col) = doc.line_col(pos)
      let top = self.top_of_line(line)
      if top >= 0.0 {
        let layout = self.layout_line(line)
        let x = layout.xs[col.min(layout.xs.length() - 1)]
        let y = top + self.segment_offset(x)
        let xx = if self.options.line_wrapping && self.client_width > 0.0 {
          x - (x / self.client_width).floor() * self.client_width
        } else {
          x
        }
        if r.anchor == main.anchor && r.head == main.head {
          main_cursor_placed = true
          @ffi.set_cursor(self.content, xx, y, lh, 1)
        } else {
          sb.push("<div class=\"cm-cursor\" style=\"left:")
          push_double(sb, xx)
          sb.push("px;top:")
          push_double(sb, y)
          sb.push("px;height:")
          push_double(sb, lh)
          sb.push("px\"></div>")
        }
      }
    } else {
      let (from_line, from_col) = doc.line_col(r.from())
      let (to_line, to_col) = doc.line_col(r.to())
      for line = from_line; line <= to_line; line = line + 1 {
        if !self.is_visible(line) {
          continue
        }
        let top = self.top_of_line(line)
        if top < 0.0 {
          continue
        }
        let layout = self.layout_line(line)
        let line_len = doc.line_length(line)
        let c1 = if line == from_line { from_col } else { 0 }
        let c2 = if line == to_line { to_col } else { line_len }
        let x1 = layout.xs[c1.min(layout.xs.length() - 1)]
        let x2 = layout.xs[c2.min(layout.xs.length() - 1)]
        if self.options.line_wrapping && self.client_width > 0.0 {
          let mut seg = (x1 / self.client_width).floor().to_int()
          let end_seg = (x2 / self.client_width).floor().to_int()
          while seg <= end_seg {
            let seg_start = self.client_width * seg.to_double()
            let seg_end = seg_start + self.client_width
            let rx1 = x1.max(seg_start)
            let rx2 = if c2 == line_len && line == to_line {
              seg_end
            } else {
              x2.min(seg_end)
            }
            if rx2 > rx1 {
              sb.push("<div class=\"cm-selection\" style=\"left:")
              push_double(sb, rx1 - seg_start)
              sb.push("px;top:")
              push_double(sb, top + lh * seg.to_double())
              sb.push("px;width:")
              push_double(sb, rx2 - rx1)
              sb.push("px;height:")
              push_double(sb, lh)
              sb.push("px\"></div>")
            }
            seg = seg + 1
          }
        } else if c2 > c1 || (line < to_line && c1 == c2) {
          let end = if line < to_line { layout.width } else { x2 }
          sb.push("<div class=\"cm-selection\" style=\"left:")
          push_double(sb, x1)
          sb.push("px;top:")
          push_double(sb, top)
          sb.push("px;width:")
          push_double(sb, if end > x1 { end - x1 } else { 6.0 })
          sb.push("px;height:")
          push_double(sb, lh)
          sb.push("px\"></div>")
        }
      }
    }
  }
  if !main_cursor_placed {
    @ffi.set_cursor(self.content, 0.0, 0.0, lh, 0)
  }
}

///|
/// The y offset of a line, or -1 when the line is not currently laid out.
fn EditorView::top_of_line(self : EditorView, line : Int) -> Double {
  for i = 0; i < self.vis_lines.length(); i = i + 1 {
    if self.vis_lines[i] == line {
      return self.vis_tops[i]
    }
  }
  -1.0
}

///|
fn EditorView::segment_offset(self : EditorView, x : Double) -> Double {
  if self.options.line_wrapping && self.client_width > 0.0 {
    (x / self.client_width).floor() * self.options.line_height
  } else {
    0.0
  }
}

///|
fn EditorView::invalidate_render_cache(self : EditorView) -> Unit {
  self.cache_gen = self.cache_gen + 1
  self.line_html_cache = []
  self.gutter_html_cache = []
}

///|
fn EditorView::cached_line_html(
  self : EditorView,
  line : Int,
  signature : String,
) -> @ffi.JsAny? {
  if line < 0 || line >= self.line_html_cache.length() {
    return None
  }
  match self.line_html_cache[line] {
    Some((cached, html)) => if cached == signature { Some(html) } else { None }
    None => None
  }
}

///|
fn EditorView::put_line_html(
  self : EditorView,
  line : Int,
  signature : String,
  html : @ffi.JsAny,
) -> Unit {
  while self.line_html_cache.length() <= line {
    self.line_html_cache.push(None)
  }
  self.line_html_cache[line] = Some((signature, html))
}

///|
fn EditorView::cached_gutter_html(
  self : EditorView,
  line : Int,
  signature : String,
) -> @ffi.JsAny? {
  if line < 0 || line >= self.gutter_html_cache.length() {
    return None
  }
  match self.gutter_html_cache[line] {
    Some((cached, html)) => if cached == signature { Some(html) } else { None }
    None => None
  }
}

///|
fn EditorView::put_gutter_html(
  self : EditorView,
  line : Int,
  signature : String,
  html : @ffi.JsAny,
) -> Unit {
  while self.gutter_html_cache.length() <= line {
    self.gutter_html_cache.push(None)
  }
  self.gutter_html_cache[line] = Some((signature, html))
}

///|
fn EditorView::build_line_html(
  self : EditorView,
  line : Int,
  top : Double,
  main_line : Int,
  text : String,
  tokens : Array[@highlight.Token],
  starts : Array[Int],
) -> @ffi.JsAny {
  let sb = @ffi.JsStringBuilder::new()
  let lh = self.options.line_height
  let active = if line == main_line { " cm-active-line" } else { "" }
  let classes = self.decoration_classes(line)
  for seg = 0; seg + 1 < starts.length(); seg = seg + 1 {
    let c1 = starts[seg]
    let c2 = starts[seg + 1]
    let seg_top = top + lh * seg.to_double()
    sb.push("<div class=\"cm-line")
    sb.push(active)
    sb.push(classes)
    sb.push("\" style=\"top:")
    push_double(sb, seg_top)
    sb.push("px;height:")
    push_double(sb, lh)
    sb.push("px\">")
    let mut pos = c1
    for tok in tokens {
      if tok.to <= c1 {
        continue
      }
      if tok.from >= c2 {
        break
      }
      let tf = tok.from.max(c1)
      let tt = tok.to.min(c2)
      if tf > pos {
        push_escaped(sb, text[pos:tf].to_owned())
      }
      sb.push("<span class=\"")
      sb.push(token_class(tok.typ))
      sb.push("\" data-token=\"")
      sb.push(token_name(tok.typ))
      sb.push("\">")
      push_escaped(sb, text[tf:tt].to_owned())
      sb.push("</span>")
      pos = tt
    }
    if pos < c2 {
      push_escaped(sb, text[pos:c2].to_owned())
    }
    if seg + 2 == starts.length() && self.fold_widget(line) {
      sb.push("<span class=\"cm-fold-ellipsis\">\u{2026}</span>")
    }
    sb.push("</div>")
  }
  sb.finish()
}

///|
fn EditorView::build_gutter_html(
  self : EditorView,
  line : Int,
  top : Double,
  height : Double,
  main_line : Int,
) -> @ffi.JsAny {
  let sb = @ffi.JsStringBuilder::new()
  sb.push("<div class=\"cm-gutter-line")
  if line == main_line {
    sb.push(" cm-active-gutter")
  }
  sb.push("\" style=\"top:")
  push_double(sb, top)
  sb.push("px;height:")
  push_double(sb, height)
  sb.push("px\">")
  if self.fold_widget(line) {
    sb.push("<span class=\"cm-fold cm-fold-folded\" data-line=\"")
    sb.push(line.to_string())
    sb.push("\">\u{25B8}</span>")
  } else if self.foldable_line(line) {
    sb.push("<span class=\"cm-fold cm-fold-foldable\" data-line=\"")
    sb.push(line.to_string())
    sb.push("\">\u{25BE}</span>")
  }
  sb.push((line + 1).to_string())
  sb.push("</div>")
  sb.finish()
}

///|
pub fn EditorView::render(self : EditorView) -> Unit {
  self.client_width = @ffi.client_width(self.scroller)
  self.client_height = @ffi.client_height(self.scroller)
  let doc = self.state.doc()
  let lines = self.visible_lines()
  self.compute_viewport(lines)
  self.decorations = match self.decorations_provider {
    Some(provider) => provider(self.state)
    None => []
  }
  let first = self.first_visible_index()
  let last = self.last_visible_index_after(first)
  let content_html = @ffi.JsStringBuilder::new()
  let gutter_html = @ffi.JsStringBuilder::new()
  let (main_line, _) = doc.line_col(self.state.selection().main_range().head)
  for i = first; i <= last && i < lines.length(); i = i + 1 {
    let line = lines[i]
    let top = self.vis_tops[i]
    let layout = self.layout_line(line)
    let height = self.line_height_of(layout)
    let active = if line == main_line { " cm-active-line" } else { "" }
    let text = doc.line(line)
    let (state, tokens) = self.highlighter.tokens_and_state_for_line(doc, line)
    let fold = self.fold_widget(line)
    let foldable = self.foldable_line(line)
    let signature = "\{self.cache_gen}|\{line}|\{state}|\{top}|\{active}|\{fold}|\{foldable}|\{text}|\{self.decoration_classes(line)}"
    let html = match self.cached_line_html(line, signature) {
      Some(html) => html
      None => {
        let starts = self.segment_starts(line)
        let built = self.build_line_html(
          line, top, main_line, text, tokens, starts,
        )
        self.put_line_html(line, signature, built)
        built
      }
    }
    content_html.push_js(html)
    if self.options.line_numbers {
      let gutter_signature = "\{self.cache_gen}|\{line}|\{top}|\{height}|\{active}|\{fold}|\{foldable}"
      let gutter = match self.cached_gutter_html(line, gutter_signature) {
        Some(html) => html
        None => {
          let built = self.build_gutter_html(line, top, height, main_line)
          self.put_gutter_html(line, gutter_signature, built)
          built
        }
      }
      gutter_html.push_js(gutter)
    }
  }
  self.render_marks(content_html)
  self.render_selections(content_html)
  @ffi.set_html(self.content, content_html.finish())
  @ffi.set_html(self.gutter, gutter_html.finish())
  @ffi.set_style(
    self.content,
    @ffi.js_string("height"),
    @ffi.js_string(self.total_height.to_string() + "px"),
  )
  self.vis_lines = lines
  self.publish_cursor_position()
}

///|
/// Keeps the hidden input element at the cursor so IME candidate windows and
/// native text widgets appear near the caret.
fn EditorView::publish_cursor_position(self : EditorView) -> Unit {
  let doc = self.state.doc()
  let pos = self.state.selection().main_range().head
  let (line, col) = doc.line_col(pos)
  let top = self.top_of_line(line)
  if top < 0.0 {
    return
  }
  let layout = self.layout_line(line)
  let x = layout.xs[col.min(layout.xs.length() - 1)]
  let lh = self.options.line_height
  let mut y = top
  let mut xx = x
  if self.options.line_wrapping && self.client_width > 0.0 {
    let seg = (x / self.client_width).floor()
    xx = x - seg * self.client_width
    y = top + seg * lh
  }
  let gutter = @ffi.client_width(self.gutter) + 4.0
  let mut left = gutter + xx - self.scroll_left
  let mut t = y - self.scroll_top
  if left < 0.0 {
    left = 0.0
  }
  if t < 0.0 {
    t = 0.0
  }
  let rounded_left = (left * 100.0).round() / 100.0
  let rounded_top = (t * 100.0).round() / 100.0
  @ffi.set_style(
    self.input,
    @ffi.js_string("left"),
    @ffi.js_string(rounded_left.to_string() + "px"),
  )
  @ffi.set_style(
    self.input,
    @ffi.js_string("top"),
    @ffi.js_string(rounded_top.to_string() + "px"),
  )
  @ffi.set_style(
    self.input,
    @ffi.js_string("height"),
    @ffi.js_string(lh.to_string() + "px"),
  )
}

///|
fn EditorView::first_visible_index(self : EditorView) -> Int {
  for i = 0; i < self.vis_lines.length(); i = i + 1 {
    if self.vis_tops[i] + self.vis_heights[i] > self.scroll_top {
      return i
    }
  }
  self.vis_lines.length()
}

///|
fn EditorView::last_visible_index_after(self : EditorView, from : Int) -> Int {
  let bottom = self.scroll_top + self.client_height
  let mut i = from
  while i < self.vis_lines.length() {
    if self.vis_tops[i] > bottom {
      return i - 1
    }
    i = i + 1
  }
  self.vis_lines.length() - 1
}

///|
/// Column offsets where visual segments of a line start, followed by the line
/// length. Without wrapping this is `[0, n]`.
fn EditorView::segment_starts(self : EditorView, line : Int) -> Array[Int] {
  let n = self.state.doc().line_length(line)
  if !self.options.line_wrapping || self.client_width <= 0.0 {
    return [0, n]
  }
  let layout = self.layout_line(line)
  let starts : Array[Int] = [0]
  let mut seg_start = 0
  let mut i = 1
  while i <= n {
    if i == n {
      break
    }
    if layout.xs[i] - layout.xs[seg_start] >= self.client_width {
      starts.push(i)
      seg_start = i
    }
    i = i + 1
  }
  if starts[starts.length() - 1] != n {
    starts.push(n)
  }
  starts
}

///|
fn EditorView::ensure_cursor_visible(self : EditorView) -> Unit {
  let doc = self.state.doc()
  let pos = self.state.selection().main_range().head
  let (line, col) = doc.line_col(pos)
  let top = self.top_of_line(line)
  if top < 0.0 {
    return
  }
  let layout = self.layout_line(line)
  let x = layout.xs[col.min(layout.xs.length() - 1)]
  let y = top + self.segment_offset(x)
  let xx = if self.options.line_wrapping && self.client_width > 0.0 {
    x - (x / self.client_width).floor() * self.client_width
  } else {
    x
  }
  let lh = self.options.line_height
  let mut new_top = self.scroll_top
  if y < self.scroll_top {
    new_top = y
  } else if y + lh > self.scroll_top + self.client_height {
    new_top = y + lh - self.client_height
  }
  let mut new_left = self.scroll_left
  if xx < self.scroll_left {
    new_left = xx
  } else if xx > self.scroll_left + self.client_width - 20.0 {
    new_left = xx - self.client_width + 40.0
  }
  if new_top < 0.0 {
    new_top = 0.0
  }
  if new_left < 0.0 {
    new_left = 0.0
  }
  if new_top != self.scroll_top || new_left != self.scroll_left {
    let previous_first = self.first_visible_index()
    let previous_last = self.last_visible_index_after(previous_first)
    self.scroll_top = new_top
    self.scroll_left = new_left
    @ffi.set_scroll(self.scroller, new_top, new_left)
    let next_first = self.first_visible_index()
    let next_last = self.last_visible_index_after(next_first)
    if next_first != previous_first || next_last != previous_last {
      self.render()
    }
  }
}

///|
pub fn EditorView::apply_spec(
  self : EditorView,
  spec : @state.TransactionSpec,
) -> Bool {
  if self.options.read_only && !self.host_edit {
    match spec.changes {
      Some(cs) => if !cs.is_empty() { return false }
      None => ()
    }
  }
  let previous_selection = self.state.selection()
  let tr = self.state.update(spec)
  let changes = tr.changes()
  if !changes.is_empty() {
    let first_change = changes.changes()[0]
    let line = self.state.doc().line_at(first_change.from)
    self.highlighter.invalidate(line)
  }
  let scroll = tr.scroll_into_view()
  self.state = tr.state()
  self.render()
  if scroll {
    self.ensure_cursor_visible()
  }
  if !changes.is_empty() || !self.state.selection().eq(previous_selection) {
    @ffi.notify_update(self.editor_id)
  }
  true
}

///|
pub fn EditorView::set_doc(self : EditorView, text : String) -> Unit {
  self.invalidate_render_cache()
  self.host_edit = true
  let changes = @core.ChangeSet::of([
    @core.Change::new(0, self.state.length(), text),
  ])
  let spec = @state.TransactionSpec::new(
    changes~,
    selection=@core.EditorSelection::cursor(0),
    annotations=[@state.UserEvent("setValue")],
    scroll_into_view=true,
  )
  let _ = self.apply_spec(spec)
  self.host_edit = false
}

///|
fn EditorView::pos_at_coords(self : EditorView, x : Double, y : Double) -> Int {
  let mut index = 0
  let mut found = false
  for i = 0; i < self.vis_lines.length(); i = i + 1 {
    let bottom = self.vis_tops[i] + self.vis_heights[i]
    if y < bottom {
      index = i
      found = true
      break
    }
  }
  if !found {
    if self.vis_lines.length() == 0 {
      return 0
    }
    index = self.vis_lines.length() - 1
  }
  let line = self.vis_lines[index]
  if self.options.line_wrapping && self.client_width > 0.0 {
    let starts = self.segment_starts(line)
    let mut seg = ((y - self.vis_tops[index]) / self.options.line_height)
      .floor()
      .to_int()
    if seg < 0 {
      seg = 0
    }
    if seg > starts.length() - 2 {
      seg = starts.length() - 2
    }
    let xx = x + seg.to_double() * self.client_width
    return self.col_at_x(line, xx)
  }
  self.col_at_x(line, x)
}

///|
fn EditorView::col_at_x(self : EditorView, line : Int, x : Double) -> Int {
  let doc = self.state.doc()
  let layout = self.layout_line(line)
  let n = doc.line_length(line)
  let mut col = n
  for i = 0; i <= n; i = i + 1 {
    if layout.xs[i] > x {
      col = i
      break
    }
  }
  if col > 0 && col <= n && layout.xs[col] > x {
    let left = layout.xs[col - 1]
    if x - left < layout.xs[col] - x {
      col = col - 1
    }
  }
  doc.pos(line, self.snap_col(line, col, x, layout))
}

///|
/// Snaps a column that falls inside a surrogate pair to whichever side of the
/// pair is closer to the pointer, so selections never split a code point.
fn EditorView::snap_col(
  self : EditorView,
  line : Int,
  col : Int,
  x : Double,
  layout : LineLayout,
) -> Int {
  let doc = self.state.doc()
  let n = doc.line_length(line)
  if col <= 0 || col >= n {
    return col
  }
  let s = doc.line(line)
  let high = s.unsafe_get(col - 1).to_int()
  let low = s.unsafe_get(col).to_int()
  let in_pair = high >= 0xD800 &&
    high <= 0xDBFF &&
    low >= 0xDC00 &&
    low <= 0xDFFF
  if !in_pair {
    return col
  }
  let left = layout.xs[col - 1]
  let right = layout.xs[col + 1]
  if x < (left + right) / 2.0 {
    col - 1
  } else {
    col + 1
  }
}

///|
fn EditorView::word_boundaries(self : EditorView, pos : Int) -> @core.Range {
  let doc = self.state.doc()
  let text = doc.to_string()
  let is_word = fn(code : Int) -> Bool {
    (code >= 48 && code <= 57) ||
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    code == 95
  }
  let anchor = doc.snap_pos_left(pos)
  let mut from = anchor
  while from > 0 {
    let candidate = doc.snap_pos_left(from - 1)
    if !is_word(text.unsafe_get(candidate).to_int()) {
      break
    }
    from = candidate
  }
  let mut to = anchor
  while to < text.length() {
    let code = text.unsafe_get(to).to_int()
    if !is_word(code) {
      break
    }
    to = doc.snap_pos_right(to + 1)
  }
  if from == to {
    if to < text.length() {
      to = doc.snap_pos_right(to + 1)
    } else if from > 0 {
      from = doc.snap_pos_left(from - 1)
    }
  }
  @core.Range::new(from, to)
}

///|
pub fn EditorView::selected_text(self : EditorView) -> @ffi.JsAny {
  let doc = self.state.doc()
  let sb = @ffi.JsStringBuilder::new()
  let ranges = self.state.selection().ranges()
  for i = 0; i < ranges.length(); i = i + 1 {
    if i > 0 {
      sb.push("\n")
    }
    sb.push(doc.slice(ranges[i].from(), ranges[i].to()))
  }
  sb.finish()
}

///|
pub fn EditorView::select_range(
  self : EditorView,
  from : Int,
  to : Int,
) -> Unit {
  let spec = @state.TransactionSpec::new(
    changes=@core.ChangeSet::empty(),
    selection=@core.EditorSelection::single(from, to),
    scroll_into_view=true,
  )
  let _ = self.apply_spec(spec)
}

///|
pub fn EditorView::replace_range(
  self : EditorView,
  from : Int,
  to : Int,
  text : String,
) -> Unit {
  let spec = @state.TransactionSpec::new(
    changes=@core.ChangeSet::of([@core.Change::new(from, to, text)]),
    annotations=[@state.UserEvent("replace")],
    scroll_into_view=true,
  )
  let _ = self.apply_spec(spec)
}

///|
pub fn EditorView::scroll_top(self : EditorView) -> Double {
  self.scroll_top
}

///|
pub fn EditorView::client_height(self : EditorView) -> Double {
  self.client_height
}

///|
pub fn EditorView::client_width(self : EditorView) -> Double {
  self.client_width
}

///|
pub fn EditorView::dispatch_mouse(
  self : EditorView,
  kind : Int,
  x : Double,
  y : Double,
  detail : Int,
) -> Bool {
  let doc = self.state.doc()
  let pos = self.pos_at_coords(x, y)
  match kind {
    0 => {
      self.focus()
      let sel = if detail >= 3 {
        let (line, _) = doc.line_col(pos)
        @core.EditorSelection::create(
          [@core.SelectionRange::new(doc.line_start(line), doc.line_end(line))],
          0,
        )
      } else if detail == 2 {
        let word = self.word_boundaries(pos)
        @core.EditorSelection::single(word.from, word.to)
      } else {
        @core.EditorSelection::cursor(pos)
      }
      let spec = @state.TransactionSpec::new(
        changes=@core.ChangeSet::empty(),
        selection=sel,
      )
      let _ = self.apply_spec(spec)
      self.dragging = true
      true
    }
    1 => {
      if self.dragging {
        self.auto_scroll_drag(y, x)
        let pos = self.pos_at_coords(x, y)
        let anchor = self.state.selection().main_range().anchor
        let spec = @state.TransactionSpec::new(
          changes=@core.ChangeSet::empty(),
          selection=@core.EditorSelection::single(anchor, pos),
        )
        let _ = self.apply_spec(spec)
      }
      true
    }
    2 => {
      self.dragging = false
      true
    }
    _ => false
  }
}

///|
/// Scrolls the viewport while a drag is in progress and the pointer has left
/// the visible area, so selections can extend past the first screen.
fn EditorView::auto_scroll_drag(
  self : EditorView,
  y : Double,
  x : Double,
) -> Unit {
  let lh = self.options.line_height
  let mut new_top = self.scroll_top
  let viewport_y = y - self.scroll_top
  if viewport_y < 0.0 {
    let step = viewport_y.max(-3.0 * lh)
    new_top = self.scroll_top + step
  } else if viewport_y > self.client_height {
    let step = (viewport_y - self.client_height).min(3.0 * lh)
    new_top = self.scroll_top + step
  }
  if new_top < 0.0 {
    new_top = 0.0
  }
  let max_top = self.total_height - self.client_height
  if max_top > 0.0 && new_top > max_top {
    new_top = max_top
  }
  let mut new_left = self.scroll_left
  if x < self.scroll_left {
    new_left = x
  } else if x > self.scroll_left + self.client_width {
    new_left = x - self.client_width
  }
  if new_left < 0.0 {
    new_left = 0.0
  }
  if new_top != self.scroll_top || new_left != self.scroll_left {
    let previous_first = self.first_visible_index()
    let previous_last = self.last_visible_index_after(previous_first)
    self.scroll_top = new_top
    self.scroll_left = new_left
    @ffi.set_scroll(self.scroller, new_top, new_left)
    let next_first = self.first_visible_index()
    let next_last = self.last_visible_index_after(next_first)
    if next_first != previous_first || next_last != previous_last {
      self.render()
    }
  }
}

///|
pub fn EditorView::dispatch_scroll(
  self : EditorView,
  top : Double,
  left : Double,
) -> Unit {
  self.scroll_top = top
  self.scroll_left = left
  self.render()
}

///|
pub fn EditorView::dispatch_focus(self : EditorView, focused : Int) -> Unit {
  if focused == 1 {
    self.render()
  }
}

///|
pub fn EditorView::ensure_cursor_visible_public(self : EditorView) -> Unit {
  self.ensure_cursor_visible()
}

///|
pub fn EditorView::pos_at_coords_public(
  self : EditorView,
  x : Double,
  y : Double,
) -> Int {
  self.pos_at_coords(x, y)
}
