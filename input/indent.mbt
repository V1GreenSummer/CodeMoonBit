///|
/// The configured indentation width, defaulting to four spaces. The last
/// configured value wins.
pub let indent_unit_facet : @state.Facet[Int] = @state.Facet::new(
  default=fn() { 4 },
  combine=fn(_previous : Int, value : Int) { value },
)

///|
/// Configures the indentation width used by Tab, `Mod-]` and `Mod-[`.
pub fn indent_unit(n : Int) -> @state.Extension {
  indent_unit_facet.of(n)
}

///|
/// The indentation width configured in `state`, or four when unset.
pub fn configured_indent(state : @state.EditorState) -> Int {
  let value = state.facet(indent_unit_facet)
  if value > 0 {
    value
  } else {
    4
  }
}

///|
/// Resolves the indentation width for an editing command: an explicit
/// `indent_unit` wins, otherwise the state's configured value is used.
fn resolve_indent(state : @state.EditorState, indent_unit : Int?) -> Int {
  match indent_unit {
    Some(value) => if value > 0 { value } else { configured_indent(state) }
    None => configured_indent(state)
  }
}

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
/// Inserts `indent_unit` spaces before every line touched by the selection,
/// using the configured indent when `indent_unit` is omitted.
pub fn indent_more(
  state : @state.EditorState,
  indent_unit? : Int,
) -> @state.TransactionSpec {
  let unit = resolve_indent(state, indent_unit)
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  let seen : Array[Int] = []
  for r in state.selection().ranges() {
    for line in touched_lines(doc, r) {
      if !seen.contains(line) {
        seen.push(line)
        changes.push(@core.Change::insert(doc.line_start(line), spaces(unit)))
      }
    }
  }
  spec_with_changes(state, changes, "input.indent")
}

///|
/// Removes up to one leading indentation unit from every touched line, using
/// the configured indent when `indent_unit` is omitted.
pub fn indent_less(
  state : @state.EditorState,
  indent_unit? : Int,
) -> @state.TransactionSpec {
  let unit = resolve_indent(state, indent_unit)
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
          while len < unit &&
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
/// the cursor sits after the leading whitespace. Uses the configured indent
/// when `indent_unit` is omitted.
pub fn insert_tab(
  state : @state.EditorState,
  indent_unit? : Int,
) -> @state.TransactionSpec {
  let unit = resolve_indent(state, indent_unit)
  let doc = state.doc()
  let changes : Array[@core.Change] = []
  let seen : Array[Int] = []
  for r in state.selection().ranges() {
    if r.anchor != r.head {
      for line in touched_lines(doc, r) {
        if !seen.contains(line) {
          seen.push(line)
          changes.push(@core.Change::insert(doc.line_start(line), spaces(unit)))
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
          changes.push(@core.Change::insert(start, spaces(unit)))
        }
      } else {
        let count = unit - col % unit
        changes.push(@core.Change::insert(pos, spaces(count)))
      }
    }
  }
  spec_with_changes(state, changes, "input.type")
}
