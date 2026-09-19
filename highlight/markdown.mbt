///|
fn markdown_is_hr(line : String, from : Int) -> Int {
  let n = line.length()
  let mut count = 0
  let mut marker = 0
  let mut i = from
  while i < n {
    let c = line.unsafe_get(i).to_int()
    if c == 32 || c == 9 {
      i = i + 1
    } else if c == 45 || c == 42 || c == 95 {
      if marker == 0 {
        marker = c
      } else if marker != c {
        return 0
      }
      count = count + 1
      i = i + 1
    } else {
      return 0
    }
  }
  if count >= 3 {
    marker
  } else {
    0
  }
}

///|
fn markdown_flush_plain(sc : Scanner, plain_start : Int) -> Unit {
  sc.push(plain_start, sc.pos, VariableName)
}

///|
/// Scans inline markdown constructs: code spans, links, emphasis and escapes.
/// Plain text is emitted as `VariableName` so the line is fully covered.
fn markdown_inline(sc : Scanner) -> Unit {
  let mut plain_start = sc.pos
  while !sc.eof() {
    let c = sc.peek(0)
    if c == 92 {
      sc.pos = sc.pos + 1
      if !sc.eof() {
        let _ = sc.advance()
      }
    } else if c == 96 {
      let run = char_run_length(sc.line, sc.pos, 96)
      let close = find_char_run(sc.line, sc.pos + run, 96, run)
      if close >= 0 {
        markdown_flush_plain(sc, plain_start)
        let end = close + run
        sc.push(sc.pos, end, Comment)
        sc.pos = end
        plain_start = sc.pos
      } else {
        sc.pos = sc.pos + run
      }
    } else if c == 91 || (c == 33 && sc.peek(1) == 91) {
      let bang = if c == 33 { 1 } else { 0 }
      let open = sc.pos + bang
      let close_bracket = find_char_run(sc.line, open + 1, 93, 1)
      if close_bracket >= 0 && sc.code_at(close_bracket + 1) == 40 {
        let close_paren = find_char_run(sc.line, close_bracket + 2, 41, 1)
        if close_paren >= 0 {
          markdown_flush_plain(sc, plain_start)
          if bang == 1 {
            sc.push(sc.pos, sc.pos + 1, Punctuation)
          }
          sc.push(open, open + 1, Punctuation)
          sc.push(open + 1, close_bracket, String)
          sc.push(close_bracket, close_bracket + 1, Punctuation)
          sc.push(close_bracket + 1, close_bracket + 2, Punctuation)
          sc.push(close_bracket + 2, close_paren, String)
          sc.push(close_paren, close_paren + 1, Punctuation)
          sc.pos = close_paren + 1
          plain_start = sc.pos
        } else {
          let _ = sc.advance()
        }
      } else {
        let _ = sc.advance()
      }
    } else if c == 42 || c == 95 {
      let run = char_run_length(sc.line, sc.pos, c)
      let close = find_char_run(sc.line, sc.pos + run, c, run)
      if close >= 0 {
        markdown_flush_plain(sc, plain_start)
        let content_start = sc.pos + run
        sc.push(sc.pos, content_start, Punctuation)
        sc.push(content_start, close, Keyword)
        sc.push(close, close + run, Punctuation)
        sc.pos = close + run
        plain_start = sc.pos
      } else {
        sc.pos = sc.pos + run
      }
    } else {
      let _ = sc.advance()
    }
  }
  markdown_flush_plain(sc, plain_start)
}

///|
fn markdown_block(sc : Scanner, lead : Int) -> Int {
  let line = sc.line
  let n = sc.len
  let c = sc.code_at(lead)
  if (c == 96 || c == 126) && char_run_length(line, lead, c) >= 3 {
    let run = char_run_length(line, lead, c)
    sc.push(lead, lead + run, Meta)
    if lead + run < n {
      sc.push(lead + run, n, VariableName)
    }
    return if c == 96 { 1 } else { 2 }
  }
  if c == 35 {
    let run = char_run_length(line, lead, 35)
    if run <= 6 &&
      (lead + run == n || line.unsafe_get(lead + run).to_int() == 32) {
      sc.push(lead, lead + run, Punctuation)
      let mut text_start = lead + run
      while text_start < n && line.unsafe_get(text_start).to_int() == 32 {
        text_start = text_start + 1
      }
      let mut text_end = n
      while text_end > text_start &&
            line.unsafe_get(text_end - 1).to_int() == 32 {
        text_end = text_end - 1
      }
      let mut hash_start = text_end
      while hash_start > text_start &&
            line.unsafe_get(hash_start - 1).to_int() == 35 {
        hash_start = hash_start - 1
      }
      if hash_start < text_end &&
        (
          hash_start == text_start ||
          line.unsafe_get(hash_start - 1).to_int() == 32
        ) {
        sc.push(hash_start, text_end, Punctuation)
        text_end = hash_start
        while text_end > text_start &&
              line.unsafe_get(text_end - 1).to_int() == 32 {
          text_end = text_end - 1
        }
      }
      sc.push(text_start, text_end, Keyword)
      return 0
    }
  }
  if c == 62 {
    sc.push(lead, lead + 1, Punctuation)
    sc.pos = lead + 1
    markdown_inline(sc)
    return 0
  }
  if markdown_is_hr(line, lead) != 0 {
    sc.push(lead, n, Meta)
    return 0
  }
  if (c == 45 || c == 42 || c == 43) &&
    (lead + 1 == n || line.unsafe_get(lead + 1).to_int() == 32) {
    sc.push(lead, lead + 1, Punctuation)
    sc.pos = lead + 1
    markdown_inline(sc)
    return 0
  }
  let mut j = lead
  while is_digit(sc.code_at(j)) {
    j = j + 1
  }
  if j > lead &&
    (sc.code_at(j) == 46 || sc.code_at(j) == 41) &&
    (j + 1 == n || sc.code_at(j + 1) == 32) {
    sc.push(lead, j + 1, Punctuation)
    sc.pos = j + 1
    markdown_inline(sc)
    return 0
  }
  sc.pos = 0
  markdown_inline(sc)
  0
}

///|
fn markdown_tokenizer(line : String, state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  if state == 1 || state == 2 {
    let fence_char = if state == 1 { 96 } else { 126 }
    let close = find_char_run(line, 0, fence_char, 3)
    if close < 0 {
      sc.push(0, sc.len, Comment)
      return (sc.tokens, state)
    }
    sc.push(0, close, Comment)
    let run = char_run_length(line, close, fence_char)
    sc.push(close, close + run, Meta)
    if close + run < sc.len {
      sc.pos = close + run
      markdown_inline(sc)
    }
    return (sc.tokens, 0)
  }
  let mut lead = 0
  while lead < 3 && lead < sc.len && line.unsafe_get(lead).to_int() == 32 {
    lead = lead + 1
  }
  let mode = markdown_block(sc, lead)
  (sc.tokens, mode)
}

///|
pub fn markdown_language() -> Language {
  {
    name: "markdown",
    tokenizer: markdown_tokenizer,
    indent_fn: None,
    brackets: [("(", ")"), ("[", "]")],
    comment_tokens: None,
    comment_line: None,
  }
}
