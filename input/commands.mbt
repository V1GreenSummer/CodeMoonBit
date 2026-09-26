///|
/// Builds a transaction that replaces every selection range with `text`, and
/// places a cursor after each insertion.
fn spec_with_changes(
  state : @state.EditorState,
  changes : Array[@core.Change],
  event : String,
) -> @state.TransactionSpec {
  let cs = @core.ChangeSet::of(changes)
  let sel = state.selection()
  let ranges : Array[@core.SelectionRange] = []
  for r in sel.ranges() {
    ranges.push(
      @core.SelectionRange::new(cs.map_pos(r.anchor, 1), cs.map_pos(r.head, 1)),
    )
  }
  @state.TransactionSpec::new(
    changes=cs,
    selection=@core.EditorSelection::create(ranges, sel.main_index()),
    annotations=[@state.UserEvent(event)],
    scroll_into_view=true,
  )
}

///|
/// Builds a selection-only transaction.
fn selection_result(
  state : @state.EditorState,
  ranges : Array[@core.SelectionRange],
) -> @state.TransactionSpec {
  @state.TransactionSpec::new(
    selection=@core.EditorSelection::create(
      ranges,
      state.selection().main_index(),
    ),
    scroll_into_view=true,
  )
}

///|
fn code_unit_at(doc : @core.Text, pos : Int) -> Int {
  if pos < 0 || pos >= doc.length() {
    return -1
  }
  let (line, col) = doc.line_col(pos)
  let text = doc.line(line)
  if col < text.length() {
    text.unsafe_get(col).to_int()
  } else {
    10
  }
}

///|
/// The code-unit offset just before `pos`, stepping over a full surrogate pair.
pub fn prev_char_boundary(doc : @core.Text, pos : Int) -> Int {
  let p = if pos > doc.length() { doc.length() } else { pos }
  if p <= 0 {
    return 0
  }
  let lo = code_unit_at(doc, p - 1)
  if lo.is_trailing_surrogate() &&
    p >= 2 &&
    code_unit_at(doc, p - 2).is_leading_surrogate() {
    p - 2
  } else {
    p - 1
  }
}

///|
/// The code-unit offset just after `pos`, stepping over a full surrogate pair.
pub fn next_char_boundary(doc : @core.Text, pos : Int) -> Int {
  let len = doc.length()
  let p = if pos < 0 { 0 } else { pos }
  if p >= len {
    return len
  }
  let hi = code_unit_at(doc, p)
  if hi.is_leading_surrogate() &&
    p + 1 < len &&
    code_unit_at(doc, p + 1).is_trailing_surrogate() {
    p + 2
  } else {
    p + 1
  }
}

///|
fn spaces(count : Int) -> String {
  if count <= 0 {
    return ""
  }
  let sb = StringBuilder()
  for i = 0; i < count; i = i + 1 {
    sb.write_char(' ')
  }
  sb.to_string()
}

///|
/// Replaces every selection with `text` and leaves cursors after it.
pub fn insert_text(
  state : @state.EditorState,
  text : String,
) -> @state.TransactionSpec {
  let changes : Array[@core.Change] = []
  for r in state.selection().ranges() {
    changes.push(@core.Change::new(r.from(), r.to(), text))
  }
  spec_with_changes(state, changes, "input.type")
}

///|
/// Inserts a newline plus a copy of the current line's leading whitespace.
pub fn insert_newline(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  for r in state.selection().ranges() {
    let line = doc.line_at(r.from())
    let indent = leading_whitespace(doc.line(line))
    changes.push(@core.Change::new(r.from(), r.to(), "\n" + indent))
  }
  spec_with_changes(state, changes, "input.type")
}

///|
/// Deletes the selection, or the character (code point) before each cursor.
pub fn delete_char_backward(
  state : @state.EditorState,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  for r in state.selection().ranges() {
    if r.anchor != r.head {
      changes.push(@core.Change::new(r.from(), r.to(), ""))
    } else if r.head > 0 {
      changes.push(
        @core.Change::new(prev_char_boundary(doc, r.head), r.head, ""),
      )
    }
  }
  spec_with_changes(state, changes, "input.delete")
}

///|
/// Deletes the selection, or the character (code point) after each cursor.
pub fn delete_char_forward(
  state : @state.EditorState,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  for r in state.selection().ranges() {
    if r.anchor != r.head {
      changes.push(@core.Change::new(r.from(), r.to(), ""))
    } else if r.head < doc.length() {
      changes.push(
        @core.Change::new(r.head, next_char_boundary(doc, r.head), ""),
      )
    }
  }
  spec_with_changes(state, changes, "input.delete")
}

///|
fn unit_class(c : Int) -> Int {
  if c == 32 || c == 9 {
    0
  } else if (c >= 48 && c <= 57) ||
    (c >= 65 && c <= 90) ||
    (c >= 97 && c <= 122) ||
    c == 95 ||
    c > 127 {
    1
  } else {
    2
  }
}

///|
/// Deletes the preceding run of word characters or whitespace.
pub fn delete_group_backward(
  state : @state.EditorState,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  for r in state.selection().ranges() {
    if r.anchor != r.head {
      changes.push(@core.Change::new(r.from(), r.to(), ""))
    } else if r.head > 0 {
      let cls = unit_class(code_unit_at(doc, prev_char_boundary(doc, r.head)))
      let mut from = r.head
      while from > 0 {
        let prev = prev_char_boundary(doc, from)
        if unit_class(code_unit_at(doc, prev)) == cls {
          from = prev
        } else {
          break
        }
      }
      changes.push(@core.Change::new(from, r.head, ""))
    }
  }
  spec_with_changes(state, changes, "input.delete")
}

///|
/// Deletes from each cursor to the start of its line, or the selection.
pub fn delete_to_line_start(
  state : @state.EditorState,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  for r in state.selection().ranges() {
    if r.anchor != r.head {
      changes.push(@core.Change::new(r.from(), r.to(), ""))
    } else if r.head > 0 {
      let from = doc.line_start(doc.line_at(r.head))
      if from < r.head {
        changes.push(@core.Change::new(from, r.head, ""))
      }
    }
  }
  spec_with_changes(state, changes, "input.delete")
}

///|
/// Deletes from each cursor to the end of its line, or the selection.
pub fn delete_to_line_end(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  for r in state.selection().ranges() {
    if r.anchor != r.head {
      changes.push(@core.Change::new(r.from(), r.to(), ""))
    } else if r.head < doc.length() {
      let to = doc.line_end(doc.line_at(r.head))
      if to > r.head {
        changes.push(@core.Change::new(r.head, to, ""))
      }
    }
  }
  spec_with_changes(state, changes, "input.delete")
}

///|
/// Moves each cursor one code point left, collapsing any selection.
pub fn cursor_char_left(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(@core.SelectionRange::cursor(prev_char_boundary(doc, r.from())))
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor one code point right, collapsing any selection.
pub fn cursor_char_right(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(@core.SelectionRange::cursor(next_char_boundary(doc, r.to())))
  }
  selection_result(state, ranges)
}

///|
/// Clamps a column to the line length and snaps it left when it would fall
/// inside a surrogate pair.
fn snap_line_col(doc : @core.Text, line : Int, col : Int) -> Int {
  let len = doc.line_length(line)
  let c = if col < 0 { 0 } else if col > len { len } else { col }
  if c <= 0 || c >= len {
    return c
  }
  let s = doc.line(line)
  let high = s.unsafe_get(c - 1).to_int()
  let low = s.unsafe_get(c).to_int()
  if high >= 0xD800 && high <= 0xDBFF && low >= 0xDC00 && low <= 0xDFFF {
    c - 1
  } else {
    c
  }
}

///|
/// Moves each cursor one line up, preserving the column and clamping.
pub fn cursor_line_up(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    let (line, col) = doc.line_col(r.head)
    let target = if line > 0 { line - 1 } else { 0 }
    ranges.push(
      @core.SelectionRange::cursor(
        doc.pos(target, snap_line_col(doc, target, col)),
      ),
    )
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor one line down, preserving the column and clamping.
pub fn cursor_line_down(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    let (line, col) = doc.line_col(r.head)
    let target = if line + 1 < doc.lines() { line + 1 } else { line }
    ranges.push(
      @core.SelectionRange::cursor(
        doc.pos(target, snap_line_col(doc, target, col)),
      ),
    )
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor to the start of its line.
pub fn cursor_line_start(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(
      @core.SelectionRange::cursor(doc.line_start(doc.line_at(r.head))),
    )
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor to the end of its line.
pub fn cursor_line_end(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(@core.SelectionRange::cursor(doc.line_end(doc.line_at(r.head))))
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor to the start of the document.
pub fn cursor_doc_start(state : @state.EditorState) -> @state.TransactionSpec {
  let ranges : Array[@core.SelectionRange] = []
  for _ in state.selection().ranges() {
    ranges.push(@core.SelectionRange::cursor(0))
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor to the end of the document.
pub fn cursor_doc_end(state : @state.EditorState) -> @state.TransactionSpec {
  let ranges : Array[@core.SelectionRange] = []
  for _ in state.selection().ranges() {
    ranges.push(@core.SelectionRange::cursor(state.length()))
  }
  selection_result(state, ranges)
}

///|
/// Visual line start alias; wrapping is applied by the view.
pub fn cursor_visual_line_start(
  state : @state.EditorState,
) -> @state.TransactionSpec {
  cursor_line_start(state)
}

///|
/// Moves each cursor `lines` lines up, preserving the column and clamping.
pub fn page_up(
  state : @state.EditorState,
  lines? : Int = 10,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    let (line, col) = doc.line_col(r.head)
    let target = if line - lines > 0 { line - lines } else { 0 }
    ranges.push(@core.SelectionRange::cursor(doc.pos(target, col)))
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor `lines` lines down, preserving the column and clamping.
pub fn page_down(
  state : @state.EditorState,
  lines? : Int = 10,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    let (line, col) = doc.line_col(r.head)
    let target = if line + lines < doc.lines() {
      line + lines
    } else {
      doc.lines() - 1
    }
    ranges.push(@core.SelectionRange::cursor(doc.pos(target, col)))
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection one code point left.
pub fn select_char_left(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(
      @core.SelectionRange::new(r.anchor, prev_char_boundary(doc, r.head)),
    )
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection one code point right.
pub fn select_char_right(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(
      @core.SelectionRange::new(r.anchor, next_char_boundary(doc, r.head)),
    )
  }
  selection_result(state, ranges)
}

///|
fn is_space_unit(c : Int) -> Bool {
  c == 32 || c == 9 || c == 10 || c == 13
}

///|
fn is_word_unit(c : Int) -> Bool {
  (c >= 48 && c <= 57) ||
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  c == 95 ||
  c >= 0x80
}

///|
/// The previous word boundary before `pos`, skipping whitespace first and
/// then either a word run or a punctuation run.
pub fn prev_word_boundary(doc : @core.Text, pos : Int) -> Int {
  let n = doc.length()
  let mut p = if pos > n { n } else { pos }
  while p > 0 && is_space_unit(code_unit_at(doc, p - 1)) {
    p = prev_char_boundary(doc, p)
  }
  if p > 0 {
    if is_word_unit(code_unit_at(doc, p - 1)) {
      while p > 0 && is_word_unit(code_unit_at(doc, p - 1)) {
        p = prev_char_boundary(doc, p)
      }
    } else {
      while p > 0 &&
            !is_word_unit(code_unit_at(doc, p - 1)) &&
            !is_space_unit(code_unit_at(doc, p - 1)) {
        p = prev_char_boundary(doc, p)
      }
    }
  }
  p
}

///|
/// The next word boundary after `pos`, skipping whitespace first and then
/// either a word run or a punctuation run.
pub fn next_word_boundary(doc : @core.Text, pos : Int) -> Int {
  let n = doc.length()
  let mut p = if pos < 0 { 0 } else { pos }
  while p < n && is_space_unit(code_unit_at(doc, p)) {
    p = next_char_boundary(doc, p)
  }
  if p < n {
    if is_word_unit(code_unit_at(doc, p)) {
      while p < n && is_word_unit(code_unit_at(doc, p)) {
        p = next_char_boundary(doc, p)
      }
    } else {
      while p < n &&
            !is_word_unit(code_unit_at(doc, p)) &&
            !is_space_unit(code_unit_at(doc, p)) {
        p = next_char_boundary(doc, p)
      }
    }
  }
  p
}

///|
/// Moves each cursor to the start of the previous word.
pub fn cursor_word_left(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(@core.SelectionRange::cursor(prev_word_boundary(doc, r.from())))
  }
  selection_result(state, ranges)
}

///|
/// Moves each cursor to the start of the next word.
pub fn cursor_word_right(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(@core.SelectionRange::cursor(next_word_boundary(doc, r.to())))
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection to the previous word boundary.
pub fn select_word_left(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(
      @core.SelectionRange::new(r.anchor, prev_word_boundary(doc, r.head)),
    )
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection to the next word boundary.
pub fn select_word_right(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(
      @core.SelectionRange::new(r.anchor, next_word_boundary(doc, r.head)),
    )
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection one line up.
pub fn select_line_up(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    let (line, col) = doc.line_col(r.head)
    let target = if line > 0 { line - 1 } else { 0 }
    ranges.push(
      @core.SelectionRange::new(
        r.anchor,
        doc.pos(target, snap_line_col(doc, target, col)),
      ),
    )
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection one line down.
pub fn select_line_down(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    let (line, col) = doc.line_col(r.head)
    let target = if line + 1 < doc.lines() { line + 1 } else { line }
    ranges.push(
      @core.SelectionRange::new(
        r.anchor,
        doc.pos(target, snap_line_col(doc, target, col)),
      ),
    )
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection to the start of its line.
pub fn select_line_start(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(
      @core.SelectionRange::new(r.anchor, doc.line_start(doc.line_at(r.head))),
    )
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection to the end of its line.
pub fn select_line_end(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(
      @core.SelectionRange::new(r.anchor, doc.line_end(doc.line_at(r.head))),
    )
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection to the start of the document.
pub fn select_doc_start(state : @state.EditorState) -> @state.TransactionSpec {
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(@core.SelectionRange::new(r.anchor, 0))
  }
  selection_result(state, ranges)
}

///|
/// Extends each selection to the end of the document.
pub fn select_doc_end(state : @state.EditorState) -> @state.TransactionSpec {
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    ranges.push(@core.SelectionRange::new(r.anchor, state.length()))
  }
  selection_result(state, ranges)
}

///|
/// Selects the whole document.
pub fn select_all_cmd(state : @state.EditorState) -> @state.TransactionSpec {
  @state.TransactionSpec::new(
    selection=@core.EditorSelection::single(0, state.length()),
  )
}

///|
/// Selects the full lines touched by each selection range.
pub fn select_line(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let ranges : Array[@core.SelectionRange] = []
  for r in state.selection().ranges() {
    let start_line = doc.line_at(r.from())
    let mut end_line = doc.line_at(r.to())
    if end_line > start_line && r.to() == doc.line_start(end_line) {
      end_line = end_line - 1
    }
    ranges.push(
      @core.SelectionRange::new(
        doc.line_start(start_line),
        doc.line_end(end_line),
      ),
    )
  }
  selection_result(state, ranges)
}

///|
/// True when the line already starts with `token` after its indentation.
fn line_commented(line : String, token : String) -> Bool {
  let ws = leading_whitespace(line).length()
  if ws + token.length() > line.length() {
    return false
  }
  for i = 0; i < token.length(); i = i + 1 {
    if line.unsafe_get(ws + i) != token.unsafe_get(i) {
      return false
    }
  }
  true
}

///|
/// Comments or uncomments every line touched by the selection.
pub fn toggle_line_comment(
  state : @state.EditorState,
  token? : String = "//",
) -> @state.TransactionSpec {
  let doc = state.doc()
  let lines : Array[Int] = []
  for r in state.selection().ranges() {
    for line in touched_lines(doc, r) {
      if !lines.contains(line) {
        lines.push(line)
      }
    }
  }
  let mut all_commented = lines.length() > 0
  for line in lines {
    if !line_commented(doc.line(line), token) {
      all_commented = false
    }
  }
  let changes : Array[@core.Change] = []
  for line in lines {
    let start = doc.line_start(line)
    let text = doc.line(line)
    let ws = leading_whitespace(text).length()
    if all_commented {
      let from = start + ws
      let mut len = token.length()
      if ws + len < text.length() && text.unsafe_get(ws + len).to_int() == 32 {
        len = len + 1
      }
      changes.push(@core.Change::delete(from, from + len))
    } else if !line_commented(text, token) {
      changes.push(@core.Change::insert(start + ws, token + " "))
    }
  }
  spec_with_changes(state, changes, "input.comment")
}

///|
/// Undoes the last history group.
pub fn undo_cmd(state : @state.EditorState) -> @state.TransactionSpec? {
  @state.undo_spec(state)
}

///|
/// Redoes the last undone history group.
pub fn redo_cmd(state : @state.EditorState) -> @state.TransactionSpec? {
  @state.redo_spec(state)
}
