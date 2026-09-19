///|
/// Caches per-line tokens and the tokenizer state at the start of each line,
/// so that only the affected suffix is re-tokenized after an edit.
pub struct HighlightCache {
  priv language : Language
  priv states : Array[Int?]
  priv lines : Array[Array[Token]?]
}

///|
pub fn HighlightCache::new(language : Language) -> HighlightCache {
  { language, states: [], lines: [] }
}

///|
fn HighlightCache::ensure(self : HighlightCache, n : Int) -> Unit {
  while self.lines.length() < n {
    self.lines.push(None)
  }
  while self.states.length() < n + 1 {
    self.states.push(None)
  }
}

///|
/// Returns the tokens of `line`, tokenizing forward from the nearest cached
/// state when necessary.
pub fn HighlightCache::tokens_for_line(
  self : HighlightCache,
  doc : @core.Text,
  line : Int,
) -> Array[Token] {
  let count = doc.lines()
  if count == 0 {
    return []
  }
  let target = if line < 0 {
    0
  } else if line >= count {
    count - 1
  } else {
    line
  }
  self.ensure(count)
  match self.lines[target] {
    Some(tokens) => return tokens
    None => ()
  }
  let mut start = target
  while start > 0 && self.states[start] is None {
    start = start - 1
  }
  let mut state = match self.states[start] {
    Some(s) => s
    None => 0
  }
  for i = start; i <= target; i = i + 1 {
    self.states[i] = Some(state)
    let (tokens, next) = self.language.tokenize(doc.line(i), state)
    self.lines[i] = Some(tokens)
    state = next
  }
  self.states[target + 1] = Some(state)
  match self.lines[target] {
    Some(tokens) => tokens
    None => []
  }
}

///|
/// Drops all cached tokens for lines at or after `from_line`, forcing them to
/// be recomputed (and re-derived from an earlier valid state) on demand.
pub fn HighlightCache::invalidate(
  self : HighlightCache,
  from_line : Int,
) -> Unit {
  let f = if from_line < 0 { 0 } else { from_line }
  if f >= self.lines.length() {
    return
  }
  for i = f; i < self.lines.length(); i = i + 1 {
    self.lines[i] = None
  }
  for i = f; i < self.states.length(); i = i + 1 {
    self.states[i] = None
  }
}
