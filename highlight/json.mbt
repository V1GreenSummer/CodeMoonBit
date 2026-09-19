///|
fn json_is_punct(c : Int) -> Bool {
  c == 123 || c == 125 || c == 91 || c == 93 || c == 44 || c == 58
}

///|
fn json_break_char(c : Int) -> Bool {
  is_whitespace(c) ||
  c == 34 ||
  c == 45 ||
  is_digit(c) ||
  is_word_start(c) ||
  json_is_punct(c)
}

///|
/// Scans the part of an unterminated string that continues on this line.
fn json_continue_string(sc : Scanner) -> Bool {
  let start = sc.pos
  let closed = scan_string_body(sc, 34)
  sc.push(start, sc.pos, String)
  closed
}

///|
fn json_string(sc : Scanner) -> Bool {
  let start = sc.pos
  sc.pos = sc.pos + 1
  let closed = scan_string_body(sc, 34)
  let mut look = sc.pos
  while look < sc.len && is_whitespace(sc.code_at(look)) {
    look = look + 1
  }
  let typ = if closed && sc.code_at(look) == 58 { PropertyName } else { String }
  sc.push(start, sc.pos, typ)
  closed
}

///|
fn json_number(sc : Scanner) -> Unit {
  let start = sc.pos
  if sc.peek(0) == 45 {
    sc.pos = sc.pos + 1
  }
  let int_start = sc.pos
  while is_digit(sc.peek(0)) {
    let _ = sc.advance()
  }
  if sc.pos == int_start {
    sc.push(start, sc.pos, Invalid)
    return
  }
  if sc.peek(0) == 46 {
    let dot = sc.pos
    sc.pos = sc.pos + 1
    let frac_start = sc.pos
    while is_digit(sc.peek(0)) {
      let _ = sc.advance()
    }
    if sc.pos == frac_start {
      sc.pos = dot
      sc.push(start, sc.pos, Number)
      return
    }
  }
  if sc.peek(0) == 101 || sc.peek(0) == 69 {
    let save = sc.pos
    sc.pos = sc.pos + 1
    if sc.peek(0) == 43 || sc.peek(0) == 45 {
      sc.pos = sc.pos + 1
    }
    let exp_start = sc.pos
    while is_digit(sc.peek(0)) {
      let _ = sc.advance()
    }
    if sc.pos == exp_start {
      sc.pos = save
    }
  }
  sc.push(start, sc.pos, Number)
}

///|
fn json_tokenizer(line : String, state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  let mut mode = state
  if mode == 1 {
    if json_continue_string(sc) {
      mode = 0
    } else {
      return (sc.tokens, 1)
    }
  }
  while !sc.eof() {
    let c = sc.peek(0)
    if is_whitespace(c) {
      let _ = sc.advance()
    } else if c == 34 {
      if !json_string(sc) {
        mode = 1
        break
      }
    } else if c == 45 || is_digit(c) {
      json_number(sc)
    } else if is_word_start(c) {
      let start = sc.pos
      while is_word(sc.peek(0)) {
        let _ = sc.advance()
      }
      let word = sc.line[start:sc.pos].to_owned()
      let typ = if word == "true" || word == "false" || word == "null" {
        Atom
      } else {
        Invalid
      }
      sc.push(start, sc.pos, typ)
    } else if json_is_punct(c) {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
    } else {
      let start = sc.pos
      while !sc.eof() && !json_break_char(sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Invalid)
    }
  }
  (sc.tokens, mode)
}

///|
pub fn json_language() -> Language {
  {
    name: "json",
    tokenizer: json_tokenizer,
    indent_fn: None,
    brackets: [("[", "]"), ("{", "}")],
    comment_tokens: None,
    comment_line: None,
  }
}
