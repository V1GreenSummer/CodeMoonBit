///|
// Typst syntax highlighting (ported from the workbench's StreamLanguage rules).
//
// State: 0 normal, 1 string, 2 raw, 3 math, 4 strong, 5 emphasis,
// 10 + depth while inside a (nestable) block comment.

///|
fn typst_keyword(word : String) -> Bool {
  word == "let" ||
  word == "set" ||
  word == "show" ||
  word == "rule" ||
  word == "import" ||
  word == "include" ||
  word == "context" ||
  word == "if" ||
  word == "else" ||
  word == "for" ||
  word == "while" ||
  word == "return" ||
  word == "none" ||
  word == "auto" ||
  word == "true" ||
  word == "false"
}

///|
fn typst_slice(line : String, from : Int, to : Int) -> String {
  let buf = StringBuilder()
  let n = line.length()
  let mut i = from
  let end = if to > n { n } else { to }
  while i < end {
    buf.write_char(line.unsafe_get(i).unsafe_to_char())
    i = i + 1
  }
  buf.to_string()
}

///|
fn typst_word_char(c : Int) -> Bool {
  is_word(c) || c == 45 || c == 46
}

///|
fn typst_tokenizer(line : String, state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  let mut mode = if state >= 10 { 9 } else { state }
  let mut depth = if state >= 10 { state - 10 } else { 0 }
  let mut span_start = 0
  while !sc.eof() {
    if mode == 9 {
      let start = sc.pos
      while !sc.eof() {
        if sc.matches("/*") {
          depth = depth + 1
          sc.pos = sc.pos + 2
        } else if sc.matches("*/") {
          depth = depth - 1
          sc.pos = sc.pos + 2
          break
        } else {
          let _ = sc.advance()
        }
      }
      sc.push(start, sc.pos, Comment)
      if depth > 0 {
        break
      }
      mode = 0
    } else if mode == 1 {
      let start = span_start
      let mut closed = false
      while !sc.eof() {
        let ch = sc.peek(0)
        if ch == 92 {
          sc.pos = sc.pos + 1
          if !sc.eof() {
            let _ = sc.advance()
          }
        } else if ch == 34 {
          let _ = sc.advance()
          closed = true
          break
        } else {
          let _ = sc.advance()
        }
      }
      sc.push(start, sc.pos, String)
      if closed {
        mode = 0
      }
    } else if mode == 2 || mode == 3 || mode == 4 || mode == 5 {
      let closer = if mode == 2 {
        96
      } else if mode == 3 {
        36
      } else if mode == 4 {
        42
      } else {
        95
      }
      let typ = if mode == 3 {
        Number
      } else if mode == 4 {
        TypeName
      } else if mode == 5 {
        VariableName
      } else {
        String
      }
      let start = span_start
      let mut closed = false
      while !sc.eof() {
        if sc.peek(0) == closer {
          let _ = sc.advance()
          closed = true
          break
        }
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, typ)
      if closed {
        mode = 0
      }
    } else {
      let c = sc.peek(0)
      if is_whitespace(c) {
        let _ = sc.advance()
      } else if sc.matches("//") {
        sc.push(sc.pos, sc.len, Comment)
        sc.pos = sc.len
      } else if sc.matches("/*") {
        depth = 0
        mode = 9
      } else if c == 61 && sc.only_ws_before() {
        let mut n = 0
        while n < 6 && sc.peek(n) == 61 {
          n = n + 1
        }
        if n > 0 && sc.peek(n) == 32 {
          sc.push(0, sc.len, TypeName)
          sc.pos = sc.len
        } else {
          let _ = sc.advance()
        }
      } else if sc.only_ws_before() && (c == 45 || c == 43) && sc.peek(1) == 32 {
        sc.push(sc.pos, sc.pos + 1, Keyword)
        let _ = sc.advance()
      } else if sc.only_ws_before() && is_digit(c) {
        let start = sc.pos
        let mut n = 0
        while is_digit(sc.peek(n)) {
          n = n + 1
        }
        if sc.peek(n) == 46 && sc.peek(n + 1) == 32 {
          sc.push(start, start + n + 1, Keyword)
          sc.pos = start + n + 1
        } else {
          let _ = sc.advance()
        }
      } else if c == 60 {
        let start = sc.pos
        let _ = sc.advance()
        while !sc.eof() && sc.peek(0) != 62 && !is_whitespace(sc.peek(0)) {
          let _ = sc.advance()
        }
        if sc.peek(0) == 62 {
          let _ = sc.advance()
          sc.push(start, sc.pos, Attribute)
        } else {
          sc.pos = start + 1
        }
      } else if c == 64 {
        let start = sc.pos
        let _ = sc.advance()
        while typst_word_char(sc.peek(0)) {
          let _ = sc.advance()
        }
        if sc.pos > start + 1 {
          sc.push(start, sc.pos, Tag)
        }
      } else if c == 35 {
        let start = sc.pos
        let _ = sc.advance()
        while typst_word_char(sc.peek(0)) {
          let _ = sc.advance()
        }
        if sc.pos > start + 1 {
          sc.push(start, sc.pos, Keyword)
        }
      } else if c == 34 {
        span_start = sc.pos
        mode = 1
        let _ = sc.advance()
      } else if c == 96 {
        span_start = sc.pos
        mode = 2
        let _ = sc.advance()
      } else if c == 36 {
        span_start = sc.pos
        mode = 3
        let _ = sc.advance()
      } else if c == 42 {
        span_start = sc.pos
        mode = 4
        let _ = sc.advance()
      } else if c == 95 {
        span_start = sc.pos
        mode = 5
        let _ = sc.advance()
      } else if is_word_start(c) {
        let start = sc.pos
        let _ = sc.advance()
        while typst_word_char(sc.peek(0)) {
          let _ = sc.advance()
        }
        if typst_keyword(typst_slice(line, start, sc.pos)) {
          sc.push(start, sc.pos, Keyword)
        }
      } else if is_digit(c) {
        let start = sc.pos
        while is_digit(sc.peek(0)) || sc.peek(0) == 46 {
          let _ = sc.advance()
        }
        sc.push(start, sc.pos, Number)
      } else {
        let _ = sc.advance()
      }
    }
  }
  let next_state = if mode == 9 { 10 + depth } else { mode }
  (sc.tokens, next_state)
}

///|
pub fn typst_language() -> Language {
  {
    name: "typst",
    tokenizer: typst_tokenizer,
    indent_fn: None,
    brackets: [("(", ")"), ("[", "]"), ("{", "}")],
    comment_tokens: Some(("/*", "*/")),
    comment_line: Some("//"),
  }
}
