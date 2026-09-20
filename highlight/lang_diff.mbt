///|
fn diff_meta_line(line : String) -> Bool {
  line.has_prefix("@@") ||
  line.has_prefix("diff ") ||
  line.has_prefix("index ") ||
  line.has_prefix("+++") ||
  line.has_prefix("---") ||
  line.has_prefix("new file") ||
  line.has_prefix("deleted file") ||
  line.has_prefix("similarity") ||
  line.has_prefix("rename ") ||
  line.has_prefix("old mode") ||
  line.has_prefix("new mode")
}

///|
/// Unified diff: hunk/header lines become `Meta`, added/removed lines carry an
/// `Operator` marker plus their content, context lines are plain.
fn diff_tokenizer(line : String, _state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  if line.length() == 0 {
    return (sc.tokens, 0)
  }
  if diff_meta_line(line) {
    sc.push(0, sc.len, Meta)
    return (sc.tokens, 0)
  }
  let c = line.unsafe_get(0).to_int()
  if c == 43 || c == 45 || c == 33 {
    sc.push(0, 1, Operator)
    sc.push(1, sc.len, VariableName)
    return (sc.tokens, 0)
  }
  sc.push(0, sc.len, VariableName)
  (sc.tokens, 0)
}

///|
pub fn diff_language() -> Language {
  {
    name: "diff",
    tokenizer: diff_tokenizer,
    indent_fn: None,
    brackets: [("(", ")"), ("[", "]"), ("{", "}")],
    comment_tokens: None,
    comment_line: None,
  }
}
