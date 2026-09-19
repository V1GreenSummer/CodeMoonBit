///|
/// The leading space/tab prefix of a line.
pub fn leading_whitespace(line : String) -> String {
  let mut i = 0
  while i < line.length() {
    let c = line.unsafe_get(i).to_int()
    if c == 32 || c == 9 {
      i = i + 1
    } else {
      break
    }
  }
  line[:i].to_owned()
}

///|
/// The visual indentation width of a line, expanding tabs to `tab_size`.
pub fn count_indent(line : String, tab_size? : Int = 4) -> Int {
  let mut col = 0
  let mut i = 0
  while i < line.length() {
    let c = line.unsafe_get(i).to_int()
    if c == 32 {
      col = col + 1
    } else if c == 9 {
      col = col + tab_size - col % tab_size
    } else {
      break
    }
    i = i + 1
  }
  col
}

///|
/// The visual indentation width of a document line.
pub fn line_indent(doc : @core.Text, line : Int, tab_size? : Int = 4) -> Int {
  count_indent(doc.line(line), tab_size~)
}

///|
/// The document lines touched by a selection range.
fn touched_lines(doc : @core.Text, r : @core.SelectionRange) -> Array[Int] {
  let start = doc.line_at(r.from())
  let mut end = doc.line_at(r.to())
  if end > start && r.to() == doc.line_start(end) {
    end = end - 1
  }
  let result : Array[Int] = []
  for i = start; i <= end; i = i + 1 {
    result.push(i)
  }
  result
}

///|
/// Inserts `spaces(4)` before every line touched by the selection.
pub fn indent_more(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  let seen : Array[Int] = []
  for r in state.selection().ranges() {
    for line in touched_lines(doc, r) {
      if !seen.contains(line) {
        seen.push(line)
        changes.push(@core.Change::insert(doc.line_start(line), spaces(4)))
      }
    }
  }
  spec_with_changes(state, changes, "input.indent")
}

///|
/// Removes up to four leading whitespace units from every touched line.
pub fn indent_less(state : @state.EditorState) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  let seen : Array[Int] = []
  for r in state.selection().ranges() {
    for line in touched_lines(doc, r) {
      if !seen.contains(line) {
        seen.push(line)
        let text = doc.line(line)
        let mut len = 0
        if text.length() > 0 && text.unsafe_get(0).to_int() == 9 {
          len = 1
        } else {
          while len < 4 &&
                len < text.length() &&
                text.unsafe_get(len).to_int() == 32 {
            len = len + 1
          }
        }
        if len > 0 {
          let start = doc.line_start(line)
          changes.push(@core.Change::delete(start, start + len))
        }
      }
    }
  }
  spec_with_changes(state, changes, "input.indent")
}

///|
/// Indents the touched lines, or inserts spaces up to the next tab stop when
/// the cursor sits after the leading whitespace.
pub fn insert_tab(
  state : @state.EditorState,
  indent_unit? : Int = 4,
) -> @state.TransactionSpec {
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  let seen : Array[Int] = []
  for r in state.selection().ranges() {
    if r.anchor != r.head {
      for line in touched_lines(doc, r) {
        if !seen.contains(line) {
          seen.push(line)
          changes.push(
            @core.Change::insert(doc.line_start(line), spaces(indent_unit)),
          )
        }
      }
    } else {
      let pos = r.head
      let line = doc.line_at(pos)
      let start = doc.line_start(line)
      let col = pos - start
      let ws = leading_whitespace(doc.line(line)).length()
      if col <= ws {
        if !seen.contains(line) {
          seen.push(line)
          changes.push(@core.Change::insert(start, spaces(indent_unit)))
        }
      } else {
        let count = indent_unit - col % indent_unit
        changes.push(@core.Change::insert(pos, spaces(count)))
      }
    }
  }
  spec_with_changes(state, changes, "input.type")
}
