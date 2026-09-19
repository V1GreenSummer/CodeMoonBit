///|
fn is_js_keyword(word : String) -> Bool {
  match word {
    "break"
    | "case"
    | "catch"
    | "class"
    | "const"
    | "continue"
    | "debugger"
    | "default"
    | "delete"
    | "do"
    | "else"
    | "export"
    | "extends"
    | "finally"
    | "for"
    | "function"
    | "if"
    | "import"
    | "in"
    | "instanceof"
    | "let"
    | "new"
    | "return"
    | "super"
    | "switch"
    | "this"
    | "throw"
    | "try"
    | "typeof"
    | "var"
    | "void"
    | "while"
    | "with"
    | "yield"
    | "async"
    | "await"
    | "static"
    | "of" => true
    _ => false
  }
}

///|
fn is_js_punct(c : Int) -> Bool {
  c == 40 ||
  c == 41 ||
  c == 91 ||
  c == 93 ||
  c == 123 ||
  c == 125 ||
  c == 44 ||
  c == 59 ||
  c == 58 ||
  c == 46
}

///|
fn is_js_operator(c : Int) -> Bool {
  c == 43 ||
  c == 45 ||
  c == 42 ||
  c == 47 ||
  c == 37 ||
  c == 38 ||
  c == 124 ||
  c == 94 ||
  c == 33 ||
  c == 126 ||
  c == 60 ||
  c == 62 ||
  c == 61 ||
  c == 63 ||
  c == 64 ||
  c == 35
}

///|
fn is_regex_prefix_char(c : Int) -> Bool {
  c == 40 ||
  c == 44 ||
  c == 61 ||
  c == 58 ||
  c == 91 ||
  c == 33 ||
  c == 38 ||
  c == 124 ||
  c == 63 ||
  c == 123 ||
  c == 125 ||
  c == 59 ||
  c == 43 ||
  c == 45 ||
  c == 42 ||
  c == 37 ||
  c == 94 ||
  c == 126 ||
  c == 60 ||
  c == 62
}

///|
fn is_regex_prefix_word(word : String) -> Bool {
  match word {
    "return"
    | "typeof"
    | "instanceof"
    | "in"
    | "of"
    | "new"
    | "delete"
    | "void"
    | "case"
    | "do"
    | "else"
    | "yield"
    | "await" => true
    _ => false
  }
}

///|
/// Scans a `/* ... */` comment starting at the current position; returns
/// whether the comment was closed on this line.
fn js_block_comment(sc : Scanner) -> Bool {
  let start = sc.pos
  sc.pos = sc.pos + 2
  let mut closed = false
  while !sc.eof() {
    if sc.peek(0) == 42 && sc.peek(1) == 47 {
      sc.pos = sc.pos + 2
      closed = true
      break
    }
    let _ = sc.advance()
  }
  sc.push(start, sc.pos, Comment)
  closed
}

///|
fn js_template_body(sc : Scanner, start : Int) -> Bool {
  let mut closed = false
  while !sc.eof() {
    let c = sc.peek(0)
    if c == 92 {
      sc.pos = sc.pos + 1
      if !sc.eof() {
        let _ = sc.advance()
      }
    } else if c == 96 {
      let _ = sc.advance()
      closed = true
      break
    } else {
      let _ = sc.advance()
    }
  }
  sc.push(start, sc.pos, String)
  closed
}

///|
fn js_string(sc : Scanner, quote : Int) -> Unit {
  let start = sc.pos
  sc.pos = sc.pos + 1
  while !sc.eof() {
    let c = sc.peek(0)
    if c == 92 {
      sc.pos = sc.pos + 1
      if !sc.eof() {
        let _ = sc.advance()
      }
    } else if c == quote {
      let _ = sc.advance()
      break
    } else {
      let _ = sc.advance()
    }
  }
  sc.push(start, sc.pos, String)
}

///|
/// Attempts to scan a regular expression literal. Restores the position and
/// returns `false` when no closing `/` is found on the line.
fn js_regex(sc : Scanner) -> Bool {
  let start = sc.pos
  sc.pos = sc.pos + 1
  let mut in_class = false
  let mut closed = false
  while !sc.eof() {
    let c = sc.peek(0)
    if c == 92 {
      sc.pos = sc.pos + 1
      if !sc.eof() {
        let _ = sc.advance()
      }
    } else if c == 91 {
      in_class = true
      let _ = sc.advance()
    } else if c == 93 {
      in_class = false
      let _ = sc.advance()
    } else if c == 47 && !in_class {
      let _ = sc.advance()
      closed = true
      break
    } else {
      let _ = sc.advance()
    }
  }
  if !closed {
    sc.pos = start
    return false
  }
  while is_alpha(sc.peek(0)) {
    let _ = sc.advance()
  }
  sc.push(start, sc.pos, String)
  true
}

///|
fn js_number(sc : Scanner) -> Unit {
  let start = sc.pos
  let second = sc.peek(1)
  if sc.peek(0) == 48 && (second == 120 || second == 88) {
    sc.pos = sc.pos + 2
    while is_hex(sc.peek(0)) || sc.peek(0) == 95 {
      let _ = sc.advance()
    }
  } else if sc.peek(0) == 48 && (second == 98 || second == 66) {
    sc.pos = sc.pos + 2
    while sc.peek(0) == 48 || sc.peek(0) == 49 || sc.peek(0) == 95 {
      let _ = sc.advance()
    }
  } else if sc.peek(0) == 48 && (second == 111 || second == 79) {
    sc.pos = sc.pos + 2
    while (sc.peek(0) >= 48 && sc.peek(0) <= 55) || sc.peek(0) == 95 {
      let _ = sc.advance()
    }
  } else {
    while is_digit(sc.peek(0)) || sc.peek(0) == 95 {
      let _ = sc.advance()
    }
    if sc.peek(0) == 46 && is_digit(sc.peek(1)) {
      sc.pos = sc.pos + 1
      while is_digit(sc.peek(0)) || sc.peek(0) == 95 {
        let _ = sc.advance()
      }
    }
    if sc.peek(0) == 101 || sc.peek(0) == 69 {
      let save = sc.pos
      sc.pos = sc.pos + 1
      if sc.peek(0) == 43 || sc.peek(0) == 45 {
        sc.pos = sc.pos + 1
      }
      if is_digit(sc.peek(0)) {
        while is_digit(sc.peek(0)) || sc.peek(0) == 95 {
          let _ = sc.advance()
        }
      } else {
        sc.pos = save
      }
    }
    if sc.peek(0) == 110 {
      let _ = sc.advance()
    }
  }
  sc.push(start, sc.pos, Number)
}

///|
fn javascript_tokenizer(line : String, state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  let mut mode = state
  if mode == 1 {
    if js_block_comment(sc) {
      mode = 0
    } else {
      return (sc.tokens, 1)
    }
  } else if mode == 2 {
    if js_template_body(sc, sc.pos) {
      mode = 0
    } else {
      return (sc.tokens, 2)
    }
  }
  let mut prev_char = -1
  let mut prev_word = ""
  while !sc.eof() {
    let c = sc.peek(0)
    if is_whitespace(c) {
      let _ = sc.advance()
    } else if c == 47 && sc.peek(1) == 47 {
      let start = sc.pos
      while !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Comment)
      prev_char = -1
      prev_word = ""
    } else if c == 47 && sc.peek(1) == 42 {
      if !js_block_comment(sc) {
        return (sc.tokens, 1)
      }
      prev_char = 42
      prev_word = ""
    } else if c == 34 || c == 39 {
      js_string(sc, c)
      prev_char = c
      prev_word = ""
    } else if c == 96 {
      let start = sc.pos
      let _ = sc.advance()
      if !js_template_body(sc, start) {
        return (sc.tokens, 2)
      }
      prev_char = 96
      prev_word = ""
    } else if c == 47 &&
      (
        prev_char == -1 ||
        is_regex_prefix_char(prev_char) ||
        is_regex_prefix_word(prev_word)
      ) &&
      js_regex(sc) {
      prev_char = 47
      prev_word = ""
    } else if is_digit(c) {
      js_number(sc)
      prev_char = sc.code_at(sc.pos - 1)
      prev_word = ""
    } else if is_word_start(c) {
      let start = sc.pos
      while is_word(sc.peek(0)) {
        let _ = sc.advance()
      }
      let word = sc.line[start:sc.pos].to_owned()
      let typ = if is_js_keyword(word) {
        Keyword
      } else if is_upper(sc.code_at(start)) {
        TypeName
      } else {
        VariableName
      }
      sc.push(start, sc.pos, typ)
      prev_char = sc.code_at(sc.pos - 1)
      prev_word = word
    } else if is_js_punct(c) {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
      prev_char = c
      prev_word = ""
    } else if is_js_operator(c) {
      let start = sc.pos
      while is_js_operator(sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Operator)
      prev_char = sc.code_at(sc.pos - 1)
      prev_word = ""
    } else {
      let start = sc.pos
      let _ = sc.advance()
      sc.push(start, sc.pos, Invalid)
      prev_char = sc.code_at(sc.pos - 1)
      prev_word = ""
    }
  }
  (sc.tokens, mode)
}

///|
pub fn javascript_language() -> Language {
  {
    name: "javascript",
    tokenizer: javascript_tokenizer,
    indent_fn: None,
    brackets: [("(", ")"), ("[", "]"), ("{", "}")],
    comment_tokens: Some(("/*", "*/")),
    comment_line: Some("//"),
  }
}
