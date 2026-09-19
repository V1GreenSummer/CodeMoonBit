///|
fn token_at_string(s : String, at : Int, token : String) -> Bool {
  if token.length() == 0 || at < 0 || at + token.length() > s.length() {
    return false
  }
  for i = 0; i < token.length(); i = i + 1 {
    if s.unsafe_get(at + i) != token.unsafe_get(i) {
      return false
    }
  }
  true
}

///|
fn match_forward(
  text : String,
  at : Int,
  open : String,
  close : String,
) -> @core.Range? {
  let length = text.length()
  let mut depth = 0
  let mut i = at + open.length()
  while i < length {
    if token_at_string(text, i, close) {
      if depth == 0 {
        return Some(@core.Range::new(at, i + close.length()))
      }
      depth = depth - 1
      i = i + close.length()
    } else if token_at_string(text, i, open) {
      depth = depth + 1
      i = i + open.length()
    } else {
      i = i + 1
    }
  }
  None
}

///|
fn match_backward(
  text : String,
  at : Int,
  open : String,
  close : String,
) -> @core.Range? {
  let mut depth = 0
  let mut i = at - close.length() - 1
  while i >= 0 {
    if token_at_string(text, i, open) {
      if depth == 0 {
        return Some(@core.Range::new(i, at))
      }
      depth = depth - 1
      i = i - 1
    } else if token_at_string(text, i, close) {
      depth = depth + 1
      i = i - close.length()
    } else {
      i = i - 1
    }
  }
  None
}

///|
/// Finds the bracket matching the one at `pos`.
///
/// If the code unit at `pos` starts an opening bracket it is matched forward;
/// otherwise if the code unit ending at `pos` is a closing bracket (i.e. the
/// cursor sits right after it) it is matched backward. The returned range
/// spans both brackets. Comments and strings are not skipped.
pub fn matching_bracket(
  doc : @core.Text,
  pos : Int,
  brackets : Array[(String, String)],
) -> @core.Range? {
  let text = doc.to_string()
  let length = text.length()
  let at = clamp_code(pos, 0, length)
  for pair_index = 0
      pair_index < brackets.length()
      pair_index = pair_index + 1 {
    let (open, close) = brackets[pair_index]
    if token_at_string(text, at, open) {
      return match_forward(text, at, open, close)
    }
  }
  for pair_index = 0
      pair_index < brackets.length()
      pair_index = pair_index + 1 {
    let (open, close) = brackets[pair_index]
    if token_at_string(text, at - close.length(), close) {
      return match_backward(text, at, open, close)
    }
  }
  None
}
