///|
/// A mutable cursor over one line that collects tokens as it goes.
priv struct Scanner {
  line : String
  len : Int
  mut pos : Int
  tokens : Array[Token]
}

///|
fn Scanner::new(line : String) -> Scanner {
  { line, len: line.length(), pos: 0, tokens: [] }
}

///|
fn Scanner::eof(self : Scanner) -> Bool {
  self.pos >= self.len
}

///|
/// Code unit at `self.pos + off`, or `-1` when out of bounds.
fn Scanner::peek(self : Scanner, off : Int) -> Int {
  let i = self.pos + off
  if i < 0 || i >= self.len {
    -1
  } else {
    self.line.unsafe_get(i).to_int()
  }
}

///|
fn Scanner::code_at(self : Scanner, i : Int) -> Int {
  if i < 0 || i >= self.len {
    -1
  } else {
    self.line.unsafe_get(i).to_int()
  }
}

///|
/// Consumes one character (a surrogate pair counts as one) and returns the
/// leading code unit. Never splits a surrogate pair.
fn Scanner::advance(self : Scanner) -> Int {
  let c = self.peek(0)
  let next = self.peek(1)
  let width = if c >= 0xD800 && c <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF {
    2
  } else {
    1
  }
  self.pos = self.pos + width
  c
}

///|
fn Scanner::push(self : Scanner, from : Int, to : Int, typ : TokenType) -> Unit {
  if to > from {
    self.tokens.push({ from, to, typ })
  }
}

///|
fn is_whitespace(c : Int) -> Bool {
  c == 32 || c == 9 || c == 13 || c == 10
}

///|
fn is_digit(c : Int) -> Bool {
  c >= 48 && c <= 57
}

///|
fn is_upper(c : Int) -> Bool {
  c >= 65 && c <= 90
}

///|
fn is_lower(c : Int) -> Bool {
  c >= 97 && c <= 122
}

///|
fn is_alpha(c : Int) -> Bool {
  is_upper(c) || is_lower(c)
}

///|
fn is_hex(c : Int) -> Bool {
  is_digit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
}

///|
fn is_word_start(c : Int) -> Bool {
  is_alpha(c) || c == 95 || c == 36 || c >= 0x80
}

///|
fn is_word(c : Int) -> Bool {
  is_word_start(c) || is_digit(c)
}

///|
/// Scans a `"`- or `'`-quoted string starting at the current position and
/// pushes a `String` token. Stops at end of line when unterminated.
fn scan_quoted(sc : Scanner, quote : Int) -> Unit {
  let start = sc.pos
  let _ = sc.advance()
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
/// Scans the body of a quoted string (after the opening quote) until the
/// closing quote; returns whether it was closed. Used for states that carry
/// an unterminated string across lines.
fn scan_string_body(sc : Scanner, quote : Int) -> Bool {
  while !sc.eof() {
    let c = sc.peek(0)
    if c == 92 {
      sc.pos = sc.pos + 1
      if !sc.eof() {
        let _ = sc.advance()
      }
    } else if c == quote {
      let _ = sc.advance()
      return true
    } else {
      let _ = sc.advance()
    }
  }
  false
}

///|
/// Index of the first run of `count` or more `ch` code units, or `-1`.
fn find_char_run(line : String, from : Int, ch : Int, count : Int) -> Int {
  let n = line.length()
  let mut i = from
  while i + count <= n {
    let mut j = 0
    while j < count && line.unsafe_get(i + j).to_int() == ch {
      j = j + 1
    }
    if j == count {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Length of the run of `ch` code units starting at `i`.
fn char_run_length(line : String, i : Int, ch : Int) -> Int {
  let mut n = 0
  while i + n < line.length() && line.unsafe_get(i + n).to_int() == ch {
    n = n + 1
  }
  n
}
