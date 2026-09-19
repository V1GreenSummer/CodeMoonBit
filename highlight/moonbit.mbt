///|
fn is_moonbit_keyword(word : String) -> Bool {
  match word {
    "pub"
    | "fn"
    | "let"
    | "mut"
    | "const"
    | "type"
    | "enum"
    | "struct"
    | "impl"
    | "trait"
    | "match"
    | "if"
    | "else"
    | "while"
    | "for"
    | "loop"
    | "break"
    | "continue"
    | "return"
    | "guard"
    | "test"
    | "async"
    | "extern"
    | "raise"
    | "try"
    | "catch"
    | "derive"
    | "using"
    | "priv" => true
    _ => false
  }
}

///|
fn is_moonbit_atom(word : String) -> Bool {
  word == "true" || word == "false"
}

///|
fn is_moonbit_punct(c : Int) -> Bool {
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
fn is_moonbit_operator(c : Int) -> Bool {
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
  c == 35 ||
  c == 92
}

///|
/// Scans an already open block comment, tracking nesting depth. Emits one
/// `Comment` token for the consumed region and returns the remaining depth.
fn moonbit_block_comment(sc : Scanner, start_depth : Int) -> Int {
  let mut depth = start_depth
  let start = sc.pos
  while !sc.eof() {
    let c = sc.peek(0)
    if c == 47 && sc.peek(1) == 42 {
      sc.pos = sc.pos + 2
      depth = depth + 1
    } else if c == 42 && sc.peek(1) == 47 {
      sc.pos = sc.pos + 2
      depth = depth - 1
      if depth == 0 {
        break
      }
    } else {
      let _ = sc.advance()
    }
  }
  sc.push(start, sc.pos, Comment)
  depth
}

///|
fn moonbit_number(sc : Scanner) -> Unit {
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
  }
  sc.push(start, sc.pos, Number)
}

///|
/// Scans a MoonBit string, supporting `"""` triple-quoted strings.
fn moonbit_string(sc : Scanner) -> Unit {
  if sc.peek(0) == 34 && sc.peek(1) == 34 && sc.peek(2) == 34 {
    let start = sc.pos
    sc.pos = sc.pos + 3
    while !sc.eof() {
      if sc.peek(0) == 34 && sc.peek(1) == 34 && sc.peek(2) == 34 {
        sc.pos = sc.pos + 3
        break
      }
      let _ = sc.advance()
    }
    sc.push(start, sc.pos, String)
  } else {
    scan_quoted(sc, 34)
  }
}

///|
fn moonbit_tokenizer(line : String, state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  let mut depth = state
  if depth > 0 {
    depth = moonbit_block_comment(sc, depth)
    if depth > 0 {
      return (sc.tokens, depth)
    }
  }
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
    } else if c == 47 && sc.peek(1) == 42 {
      sc.pos = sc.pos + 2
      depth = moonbit_block_comment(sc, 1)
      if depth > 0 {
        return (sc.tokens, depth)
      }
    } else if c == 34 {
      moonbit_string(sc)
    } else if c == 39 {
      scan_quoted(sc, 39)
    } else if is_digit(c) {
      moonbit_number(sc)
    } else if is_word_start(c) {
      let start = sc.pos
      while is_word(sc.peek(0)) {
        let _ = sc.advance()
      }
      let word = sc.line[start:sc.pos].to_owned()
      let typ = if is_moonbit_keyword(word) {
        Keyword
      } else if is_moonbit_atom(word) {
        Atom
      } else if is_upper(sc.code_at(start)) {
        TypeName
      } else {
        VariableName
      }
      sc.push(start, sc.pos, typ)
    } else if is_moonbit_punct(c) {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
    } else if is_moonbit_operator(c) {
      let start = sc.pos
      while is_moonbit_operator(sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Operator)
    } else {
      let start = sc.pos
      let _ = sc.advance()
      sc.push(start, sc.pos, Invalid)
    }
  }
  (sc.tokens, depth)
}

///|
pub fn moonbit_language() -> Language {
  {
    name: "moonbit",
    tokenizer: moonbit_tokenizer,
    indent_fn: None,
    brackets: [("(", ")"), ("[", "]"), ("{", "}")],
    comment_tokens: Some(("/*", "*/")),
    comment_line: Some("//"),
  }
}
