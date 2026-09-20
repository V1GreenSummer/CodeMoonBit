///|
/// A line tokenizer that marks the whole line as a variable name, used for
/// plain text documents.
fn plain_tokenizer(line : String, _state : Int) -> (Array[Token], Int) {
  if line.length() == 0 {
    ([], 0)
  } else {
    ([{ from: 0, to: line.length(), typ: VariableName }], 0)
  }
}

///|
pub fn plain_language() -> Language {
  {
    name: "plain",
    tokenizer: plain_tokenizer,
    indent_fn: None,
    brackets: [("(", ")"), ("[", "]"), ("{", "}")],
    comment_tokens: None,
    comment_line: None,
  }
}

///|
/// A stream-style syntax definition: a line tokenizer plus metadata used by
/// the editor for indentation and bracket handling.
pub struct Language {
  priv name : String
  priv tokenizer : (String, Int) -> (Array[Token], Int)
  priv indent_fn : ((String, Int) -> Int)?
  priv brackets : Array[(String, String)]
  priv comment_tokens : (String, String)?
  priv comment_line : String?
}

///|
pub fn Language::name(self : Language) -> String {
  self.name
}

///|
/// Tokenizes one line, starting from `state`. Returns the tokens (with
/// line-relative UTF-16 offsets) and the state to use for the next line.
pub fn Language::tokenize(
  self : Language,
  line : String,
  state : Int,
) -> (Array[Token], Int) {
  (self.tokenizer)(line, state)
}

///|
/// Computes the indentation of a line in this language. Falls back to
/// `previous_indent` when the language has no indentation function.
pub fn Language::indent(
  self : Language,
  line : String,
  state : Int,
  previous_indent : Int,
) -> Int {
  match self.indent_fn {
    Some(f) => f(line, state)
    None => previous_indent
  }
}

///|
pub fn Language::brackets(self : Language) -> Array[(String, String)] {
  self.brackets.copy()
}

///|
pub fn Language::line_comment(self : Language) -> String? {
  self.comment_line
}

///|
pub fn Language::block_comment(self : Language) -> (String, String)? {
  self.comment_tokens
}
