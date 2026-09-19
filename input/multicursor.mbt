///|
fn has_cursor_at(sel : @core.EditorSelection, pos : Int) -> Bool {
  for r in sel.ranges() {
    if r.from() == pos && r.to() == pos {
      return true
    }
  }
  false
}

///|
/// Adds a cursor `dir` lines away from the main range, at the same column.
fn add_cursor_relative(
  state : @state.EditorState,
  dir : Int,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let sel = state.selection()
  let main = sel.main_range()
  let (line, col) = doc.line_col(main.head)
  let target = line + dir
  if target < 0 || target >= doc.lines() {
    return @state.TransactionSpec::new(selection=sel)
  }
  let pos = doc.pos(target, col)
  if has_cursor_at(sel, pos) {
    return @state.TransactionSpec::new(selection=sel)
  }
  @state.TransactionSpec::new(
    selection=sel.add_range(@core.SelectionRange::cursor(pos)),
  )
}

///|
/// Adds a cursor one line above the main range.
pub fn add_cursor_above(state : @state.EditorState) -> @state.TransactionSpec {
  add_cursor_relative(state, -1)
}

///|
/// Adds a cursor one line below the main range.
pub fn add_cursor_below(state : @state.EditorState) -> @state.TransactionSpec {
  add_cursor_relative(state, 1)
}

///|
/// Adds a cursor at the end of the main range's line.
pub fn add_cursor_to_line_end(
  state : @state.EditorState,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let sel = state.selection()
  let main = sel.main_range()
  let pos = doc.line_end(doc.line_at(main.head))
  if has_cursor_at(sel, pos) {
    return @state.TransactionSpec::new(selection=sel)
  }
  @state.TransactionSpec::new(
    selection=sel.add_range(@core.SelectionRange::cursor(pos)),
  )
}

///|
fn matches_at(text : String, pat : String, at : Int) -> Bool {
  if at < 0 || at + pat.length() > text.length() {
    return false
  }
  for i = 0; i < pat.length(); i = i + 1 {
    if text.unsafe_get(at + i) != pat.unsafe_get(i) {
      return false
    }
  }
  true
}

///|
fn overlaps_selection(
  sel : @core.EditorSelection,
  from : Int,
  to : Int,
) -> Bool {
  for r in sel.ranges() {
    if from < r.to() && r.from() < to {
      return true
    }
  }
  false
}

///|
/// Adds a range for the next occurrence of `selection_text` after the main
/// range, wrapping around the document. Returns `None` for empty text or when
/// every occurrence is already selected.
pub fn select_next_occurrence(
  state : @state.EditorState,
  selection_text~ : String,
) -> @state.TransactionSpec? {
  if selection_text.length() == 0 {
    return None
  }
  let doc = state.doc()
  let text = doc.to_string()
  let sel = state.selection()
  let main = sel.main_range()
  let len = selection_text.length()
  let candidates : Array[Int] = []
  let mut i = 0
  while i + len <= text.length() {
    if matches_at(text, selection_text, i) {
      candidates.push(i)
      i = i + len
    } else {
      i = i + 1
    }
  }
  let mut chosen : Int? = None
  for c in candidates {
    if c >= main.to() && !overlaps_selection(sel, c, c + len) {
      chosen = Some(c)
      break
    }
  }
  if chosen is None {
    for c in candidates {
      if !overlaps_selection(sel, c, c + len) {
        chosen = Some(c)
        break
      }
    }
  }
  match chosen {
    None => None
    Some(pos) =>
      Some(
        @state.TransactionSpec::new(
          selection=sel.add_range(@core.SelectionRange::new(pos, pos + len)),
        ),
      )
  }
}

///|
/// Reads the main selection text from the state and selects its next
/// occurrence.
pub fn select_next_occurrence_cmd(
  state : @state.EditorState,
) -> @state.TransactionSpec? {
  let main = state.selection().main_range()
  let text = state.doc().slice(main.from(), main.to())
  select_next_occurrence(state, selection_text=text)
}
