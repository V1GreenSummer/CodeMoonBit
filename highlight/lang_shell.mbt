///|
pub fn shell_language() -> Language {
  generic_language(
    lang_config(
      "shell",
      keywords=[
        "alias", "break", "case", "continue", "coproc", "declare", "do", "done",
        "elif", "else", "esac", "eval", "exec", "exit", "export", "fi", "for", "function",
        "if", "in", "local", "readonly", "return", "select", "set", "shift", "source",
        "then", "time", "trap", "typeset", "unset", "until", "while",
      ],
      atoms=["true", "false"],
      line_comments=["#"],
      quotes=["\"", "'"],
      templates=["`"],
      dollar_vars=true,
      shebang=true,
      operator_chars="+-*/%&|^!~<>=?:@",
    ),
  )
}

///|
pub fn powershell_language() -> Language {
  generic_language(
    lang_config(
      "powershell",
      keywords=[
        "begin", "break", "catch", "class", "continue", "data", "define", "do", "dynamicparam",
        "else", "elseif", "end", "enum", "exit", "filter", "finally", "for", "foreach",
        "from", "function", "if", "in", "param", "process", "return", "switch", "throw",
        "trap", "try", "until", "using", "var", "while", "workflow",
      ],
      atoms=["true", "false", "null"],
      line_comments=["#"],
      block_comments=[("<#", "#>")],
      quotes=["\"", "'"],
      escape=96,
      dollar_vars=true,
      hyphen_words=true,
      operator_chars="+-*/%&|^!~<>=?:.",
    ),
  )
}

///|
pub fn dockerfile_language() -> Language {
  generic_language(
    lang_config(
      "dockerfile",
      keywords=[
        "add", "arg", "cmd", "copy", "entrypoint", "env", "expose", "from", "healthcheck",
        "label", "maintainer", "onbuild", "run", "shell", "stopsignal", "user", "volume",
        "workdir",
      ],
      case_insensitive=true,
      line_comments=["#"],
      quotes=["\"", "'"],
      dollar_vars=true,
      operator_chars="=+-*/%&|^!~<>?:",
    ),
  )
}

///|
fn makefile_keyword(word : String) -> Bool {
  match word {
    "include"
    | "-include"
    | "sinclude"
    | "ifeq"
    | "ifneq"
    | "ifdef"
    | "ifndef"
    | "else"
    | "endif"
    | "define"
    | "endef"
    | "export"
    | "unexport"
    | "override"
    | "vpath" => true
    _ => false
  }
}

///|
fn makefile_variable(sc : Scanner) -> Unit {
  let start = sc.pos
  sc.pos = sc.pos + 1
  let c = sc.peek(0)
  if c == 40 || c == 123 {
    let close = if c == 40 { 41 } else { 125 }
    sc.pos = sc.pos + 1
    while !sc.eof() && sc.peek(0) != close {
      let _ = sc.advance()
    }
    if !sc.eof() {
      let _ = sc.advance()
    }
  } else {
    while is_word(sc.peek(0)) {
      let _ = sc.advance()
    }
  }
  sc.push(start, sc.pos, VariableName)
}

///|
/// Makefile: terse but recognizes comments, rules/targets (`Meta`), variables,
/// assignments and the usual conditional keywords.
fn makefile_tokenizer(line : String, _state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  if line.length() == 0 {
    return (sc.tokens, 0)
  }
  if line.unsafe_get(0).to_int() == 9 {
    let start = sc.pos
    let _ = sc.advance()
    sc.push(start, sc.pos, Punctuation)
  }
  let mut start_of_line = sc.pos == 0
  while !sc.eof() {
    let c = sc.peek(0)
    if is_whitespace(c) {
      let _ = sc.advance()
    } else if c == 35 {
      let start = sc.pos
      while !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Comment)
    } else if c == 36 {
      makefile_variable(sc)
      start_of_line = false
    } else if c == 61 || ((c == 58 || c == 63 || c == 43) && sc.peek(1) == 61) {
      let start = sc.pos
      let _ = sc.advance()
      if sc.peek(0) == 61 {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Operator)
      start_of_line = false
    } else if c == 58 {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
      start_of_line = false
    } else if is_word_start(c) || c == 46 || c == 45 {
      let start = sc.pos
      if c == 45 && sc.matches("-include") {
        sc.pos = sc.pos + 8
      } else {
        while is_word(sc.peek(0)) ||
              sc.peek(0) == 46 ||
              sc.peek(0) == 45 ||
              sc.peek(0) == 47 {
          let _ = sc.advance()
        }
      }
      let word = line[start:sc.pos].to_owned()
      let mut look = sc.pos
      while look < sc.len && (sc.code_at(look) == 32 || sc.code_at(look) == 9) {
        look = look + 1
      }
      let typ = if start_of_line && makefile_keyword(word) {
        Keyword
      } else if sc.code_at(look) == 58 && sc.code_at(look + 1) != 61 {
        Meta
      } else if sc.code_at(look) == 61 ||
        (sc.code_at(look) == 58 && sc.code_at(look + 1) == 61) {
        PropertyName
      } else {
        VariableName
      }
      sc.push(start, sc.pos, typ)
      start_of_line = false
    } else if c == 34 || c == 39 {
      let quote = c
      let start = sc.pos
      sc.pos = sc.pos + 1
      while !sc.eof() && sc.peek(0) != quote {
        if sc.peek(0) == 92 {
          sc.pos = sc.pos + 1
        }
        if !sc.eof() {
          let _ = sc.advance()
        }
      }
      if !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, String)
      start_of_line = false
    } else {
      let start = sc.pos
      let _ = sc.advance()
      sc.push(start, sc.pos, Invalid)
      start_of_line = false
    }
  }
  (sc.tokens, 0)
}

///|
pub fn makefile_language() -> Language {
  {
    name: "makefile",
    tokenizer: makefile_tokenizer,
    indent_fn: None,
    brackets: [("(", ")"), ("[", "]"), ("{", "}")],
    comment_tokens: None,
    comment_line: Some("#"),
  }
}
