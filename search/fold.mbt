///|
/// A foldable block of lines. `from_line` stays visible, all lines up to and
/// including `to_line` are hidden.
pub struct FoldRange {
  from_line : Int
  to_line : Int
} derive(Eq)

///|
pub extend FoldRange with Eq::{not_equal, equal}

///|
/// The set of currently collapsed line ranges.
pub struct FoldState {
  folded : Array[FoldRange]
}

///|
pub fn FoldState::empty() -> FoldState {
  { folded: [], }
}

///|
/// Replaces the set of folded ranges.
pub let set_folds_effect : @state.StateEffect[Array[FoldRange]] = @state.StateEffect::new()

///|
pub let fold_field : @state.StateField[FoldState] = @state.StateField::new(
  init=fn(_) { FoldState::empty() },
  update=fn(old, tr) {
    match tr.effect(set_folds_effect) {
      Some(folds) => { folded: folds, }
      None =>
        {
          folded: map_folds(
            tr.start_state().doc(),
            tr.new_doc(),
            tr.changes(),
            old.folded,
          ),
        }
    }
  },
)

///|
/// Maps folded line ranges through a change set so folds survive edits.
/// Drops folds whose mapped range collapses to fewer than two lines.
fn map_folds(
  old_doc : @core.Text,
  new_doc : @core.Text,
  changes : @core.ChangeSet,
  folds : Array[FoldRange],
) -> Array[FoldRange] {
  if changes.is_empty() {
    return folds
  }
  let old_lines = old_doc.lines()
  let result : Array[FoldRange] = []
  for fold in folds {
    if fold.from_line < 0 ||
      fold.from_line >= old_lines ||
      fold.to_line < 0 ||
      fold.to_line >= old_lines {
      continue
    }
    let from_pos = new_doc.clip_pos(
      changes.map_pos(old_doc.line_start(fold.from_line), 1),
    )
    let to_pos = new_doc.clip_pos(
      changes.map_pos(old_doc.line_end(fold.to_line), -1),
    )
    let from_line = new_doc.line_at(from_pos)
    let to_line = new_doc.line_at(to_pos)
    if from_line < to_line {
      result.push({ from_line, to_line, })
    }
  }
  normalize_folds(result)
}

///|
/// Sorts and prunes a list of folds so that the result is sorted and
/// non-overlapping. Larger folds win over nested ones.
fn normalize_folds(folds : Array[FoldRange]) -> Array[FoldRange] {
  let candidates = folds.copy()
  candidates.sort_by(fn(a, b) {
    if a.from_line != b.from_line {
      a.from_line - b.from_line
    } else {
      b.to_line - a.to_line
    }
  })
  let result : Array[FoldRange] = []
  for fold in candidates {
    if fold.from_line >= fold.to_line {
      continue
    }
    let overlaps = match result.last() {
      Some(prev) => prev.to_line >= fold.from_line
      None => false
    }
    if !overlaps {
      result.push(fold)
    }
  }
  result
}

///|
fn is_blank_line(line : String) -> Bool {
  for i = 0; i < line.length(); i = i + 1 {
    let c = line.unsafe_get(i).to_int()
    if c != 32 && c != 9 && c != 13 {
      return false
    }
  }
  true
}

///|
fn indent_width(line : String) -> Int {
  let mut width = 0
  let mut i = 0
  while i < line.length() {
    let c = line.unsafe_get(i).to_int()
    if c == 32 {
      width = width + 1
    } else if c == 9 {
      width = width + 4
    } else {
      break
    }
    i = i + 1
  }
  width
}

///|
fn code_end(line : String, line_comment : String?) -> Int {
  match line_comment {
    Some(marker) if marker.length() > 0 =>
      match line.find(marker) {
        Some(index) => index
        None => line.length()
      }
    _ => line.length()
  }
}

///|
fn token_at(line : String, at : Int, token : String) -> Bool {
  if token.length() == 0 || at < 0 || at + token.length() > line.length() {
    return false
  }
  for i = 0; i < token.length(); i = i + 1 {
    if line.unsafe_get(at + i) != token.unsafe_get(i) {
      return false
    }
  }
  true
}

///|
/// Computes foldable line ranges from a document using bracket pairs and
/// indentation. `line_comment`, when given, hides everything after the marker
/// on a line from the bracket scanner.
pub fn compute_folds(
  doc : @core.Text,
  brackets : Array[(String, String)],
  line_comment : String?,
) -> Array[FoldRange] {
  let folds : Array[FoldRange] = []
  let line_count = doc.lines()
  for line = 0; line < line_count; line = line + 1 {
    if is_blank_line(doc.line(line)) {
      continue
    }
    let base_indent = indent_width(doc.line(line))
    let mut last = line
    let mut next = line + 1
    while next < line_count {
      if is_blank_line(doc.line(next)) {
        next = next + 1
      } else if indent_width(doc.line(next)) > base_indent {
        last = next
        next = next + 1
      } else {
        break
      }
    }
    if last > line {
      folds.push({ from_line: line, to_line: last, })
    }
  }
  let stack : Array[(Int, Int, Int)] = []
  for line = 0; line < line_count; line = line + 1 {
    let text = doc.line(line)
    let limit = code_end(text, line_comment)
    let mut i = 0
    while i < limit {
      let mut handled = false
      for pair_index = 0
          pair_index < brackets.length()
          pair_index = pair_index + 1 {
        let (open, _) = brackets[pair_index]
        if token_at(text, i, open) {
          stack.push((pair_index, i, line))
          i = i + open.length()
          handled = true
          break
        }
      }
      if handled {
        continue
      }
      for pair_index = 0
          pair_index < brackets.length()
          pair_index = pair_index + 1 {
        let (_, close) = brackets[pair_index]
        if token_at(text, i, close) {
          if stack.length() > 0 {
            let (top_pair, _, top_line) = stack[stack.length() - 1]
            if top_pair == pair_index {
              let _ = stack.pop()
              if line > top_line {
                folds.push({ from_line: top_line, to_line: line, })
              }
            }
          }
          i = i + close.length()
          handled = true
          break
        }
      }
      if !handled {
        i = i + 1
      }
    }
  }
  normalize_folds(folds)
}

///|
fn fold_state(state : @state.EditorState) -> FoldState? {
  if state.has_field(fold_field.id()) {
    Some(state.field(fold_field))
  } else {
    None
  }
}

///|
fn fold_spec(folds : Array[FoldRange]) -> @state.TransactionSpec {
  @state.TransactionSpec::new(effects=[
    set_folds_effect.of(normalize_folds(folds)),
  ])
}

///|
fn cursor_line(state : @state.EditorState) -> Int {
  state.doc().line_at(state.selection().main_range().head)
}

///|
/// Folds the block starting at the cursor line, if it is foldable.
pub fn fold_at(
  state : @state.EditorState,
  brackets : Array[(String, String)],
) -> @state.TransactionSpec? {
  match fold_state(state) {
    None => None
    Some(fold) => {
      let line = cursor_line(state)
      for candidate in compute_folds(state.doc(), brackets, None) {
        if candidate.from_line == line && !contains_fold(fold.folded, candidate) {
          return Some(fold_spec(fold.folded + [candidate]))
        }
      }
      None
    }
  }
}

///|
/// Folds the block starting at `line`, or the innermost block enclosing it,
/// without relying on the cursor position.
pub fn fold_line(
  state : @state.EditorState,
  line : Int,
  brackets : Array[(String, String)],
) -> @state.TransactionSpec? {
  match fold_state(state) {
    None => None
    Some(fold) => {
      let mut exact : FoldRange? = None
      let mut enclosing : FoldRange? = None
      for candidate in compute_folds(state.doc(), brackets, None) {
        if contains_fold(fold.folded, candidate) {
          continue
        }
        if candidate.from_line == line {
          exact = Some(candidate)
          break
        }
        if candidate.from_line < line && line <= candidate.to_line {
          match enclosing {
            Some(prev) =>
              if candidate.from_line > prev.from_line {
                enclosing = Some(candidate)
              }
            None => enclosing = Some(candidate)
          }
        }
      }
      match exact {
        Some(candidate) => Some(fold_spec(fold.folded + [candidate]))
        None =>
          match enclosing {
            Some(candidate) => Some(fold_spec(fold.folded + [candidate]))
            None => None
          }
      }
    }
  }
}

///|
fn contains_fold(folds : Array[FoldRange], fold : FoldRange) -> Bool {
  for existing in folds {
    if existing.from_line == fold.from_line && existing.to_line == fold.to_line {
      return true
    }
  }
  false
}

///|
/// Unfolds the block containing the cursor line.
pub fn unfold_at(state : @state.EditorState) -> @state.TransactionSpec? {
  match fold_state(state) {
    None => None
    Some(fold) => {
      let line = cursor_line(state)
      let remaining : Array[FoldRange] = []
      let mut removed = false
      for existing in fold.folded {
        if existing.from_line == line ||
          (line > existing.from_line && line <= existing.to_line) {
          removed = true
        } else {
          remaining.push(existing)
        }
      }
      if !removed {
        None
      } else {
        Some(fold_spec(remaining))
      }
    }
  }
}

///|
/// Removes the fold starting at `line`, regardless of the cursor position.
pub fn unfold_line(
  state : @state.EditorState,
  line : Int,
) -> @state.TransactionSpec? {
  match fold_state(state) {
    None => None
    Some(fold) => {
      let remaining : Array[FoldRange] = []
      let mut removed = false
      for existing in fold.folded {
        if existing.from_line == line {
          removed = true
        } else {
          remaining.push(existing)
        }
      }
      if !removed {
        None
      } else {
        Some(fold_spec(remaining))
      }
    }
  }
}

///|
/// Folds every foldable block in the document.
pub fn fold_all(
  state : @state.EditorState,
  brackets : Array[(String, String)],
) -> @state.TransactionSpec? {
  match fold_state(state) {
    None => None
    Some(fold) => {
      let computed = compute_folds(state.doc(), brackets, None)
      if computed.length() == 0 {
        return None
      }
      Some(fold_spec(fold.folded + computed))
    }
  }
}

///|
/// Unfolds every block.
pub fn unfold_all(state : @state.EditorState) -> @state.TransactionSpec? {
  match fold_state(state) {
    None => None
    Some(fold) =>
      if fold.folded.length() == 0 {
        None
      } else {
        Some(fold_spec([]))
      }
  }
}

///|
/// True when `line` is hidden by a fold (the `from_line` of a fold remains
/// visible).
pub fn is_line_hidden(state : @state.EditorState, line : Int) -> Bool {
  match fold_state(state) {
    None => false
    Some(fold) => {
      for existing in fold.folded {
        if line > existing.from_line && line <= existing.to_line {
          return true
        }
      }
      false
    }
  }
}

///|
/// The first visible line at or after `line`, clamped to the document.
pub fn next_visible_line(state : @state.EditorState, line : Int) -> Int {
  let line_count = state.line_count()
  if line_count == 0 {
    return 0
  }
  let start = clamp_code(line, 0, line_count - 1)
  let mut i = start
  while i < line_count {
    if !is_line_hidden(state, i) {
      return i
    }
    i = i + 1
  }
  let mut j = start - 1
  while j >= 0 {
    if !is_line_hidden(state, j) {
      return j
    }
    j = j - 1
  }
  0
}

///|
/// The first visible line at or before `line`, clamped to the document.
pub fn prev_visible_line(state : @state.EditorState, line : Int) -> Int {
  let line_count = state.line_count()
  if line_count == 0 {
    return 0
  }
  let start = clamp_code(line, 0, line_count - 1)
  let mut i = start
  while i >= 0 {
    if !is_line_hidden(state, i) {
      return i
    }
    i = i - 1
  }
  0
}
