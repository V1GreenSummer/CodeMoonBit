///|
fn is_tag_name_char(c : Int) -> Bool {
  is_word(c) || c == 45 || c == 46 || c == 58
}

///|
/// Scans an HTML comment body. With `at_open` the cursor sits on `<!--`.
/// Returns whether the comment closed on this line.
fn html_comment(sc : Scanner, at_open : Bool) -> Bool {
  let start = sc.pos
  if at_open {
    sc.pos = sc.pos + 4
  }
  while !sc.eof() {
    if sc.matches("-->") {
      sc.pos = sc.pos + 3
      sc.push(start, sc.pos, Comment)
      return true
    }
    let _ = sc.advance()
  }
  sc.push(start, sc.pos, Comment)
  false
}

///|
/// Scans an attribute value body. Returns whether the quote closed.
fn html_string_body(sc : Scanner, quote : Int) -> Bool {
  while !sc.eof() {
    if sc.peek(0) == quote {
      let _ = sc.advance()
      return true
    }
    let _ = sc.advance()
  }
  false
}

///|
/// Scans the inside of a tag (attributes, `=`, quoted values). Returns `0`
/// when the tag closed, or the continuation state (`2`/`3`/`4`).
fn html_tag_body(sc : Scanner) -> Int {
  while !sc.eof() {
    let c = sc.peek(0)
    if is_whitespace(c) {
      let _ = sc.advance()
    } else if c == 62 {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
      return 0
    } else if c == 47 && sc.peek(1) == 62 {
      sc.push(sc.pos, sc.pos + 2, Punctuation)
      sc.pos = sc.pos + 2
      return 0
    } else if c == 61 {
      sc.push(sc.pos, sc.pos + 1, Operator)
      sc.pos = sc.pos + 1
    } else if c == 34 || c == 39 {
      let quote = c
      let start = sc.pos
      sc.pos = sc.pos + 1
      let closed = html_string_body(sc, quote)
      sc.push(start, sc.pos, String)
      if !closed {
        return if quote == 34 { 3 } else { 4 }
      }
    } else if is_tag_name_char(c) || c == 64 {
      let start = sc.pos
      while is_tag_name_char(sc.peek(0)) || sc.peek(0) == 64 {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Attribute)
    } else {
      let start = sc.pos
      let _ = sc.advance()
      sc.push(start, sc.pos, Invalid)
    }
  }
  2
}

///|
/// Scans a tag starting at `<`. Returns the continuation state.
fn html_tag_start(sc : Scanner) -> Int {
  let start = sc.pos
  sc.push(start, start + 1, Punctuation)
  sc.pos = sc.pos + 1
  if sc.peek(0) == 47 {
    sc.push(sc.pos, sc.pos + 1, Punctuation)
    sc.pos = sc.pos + 1
  }
  let ns = sc.pos
  while is_tag_name_char(sc.peek(0)) {
    let _ = sc.advance()
  }
  if sc.pos > ns {
    sc.push(ns, sc.pos, Tag)
  }
  html_tag_body(sc)
}

///|
/// HTML/XML-style markup tokenizer: tags, attributes, quoted values, comments
/// (with multi-line state) and text runs.
fn html_tokenizer(line : String, state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  let mut st = state
  if st == 1 {
    if !html_comment(sc, false) {
      return (sc.tokens, 1)
    }
    st = 0
  } else if st == 2 {
    st = html_tag_body(sc)
    if st != 0 {
      return (sc.tokens, st)
    }
  } else if st == 3 || st == 4 {
    let quote = if st == 3 { 34 } else { 39 }
    let start = sc.pos
    let closed = html_string_body(sc, quote)
    sc.push(start, sc.pos, String)
    if !closed {
      return (sc.tokens, st)
    }
    st = html_tag_body(sc)
    if st != 0 {
      return (sc.tokens, st)
    }
  }
  while !sc.eof() {
    let c = sc.peek(0)
    if c == 60 {
      if sc.matches("<!--") {
        if !html_comment(sc, true) {
          return (sc.tokens, 1)
        }
      } else if sc.matches("<![CDATA[") {
        let start = sc.pos
        while !sc.eof() && !sc.matches("]]>") {
          let _ = sc.advance()
        }
        if sc.matches("]]>") {
          sc.pos = sc.pos + 3
        }
        sc.push(start, sc.pos, Meta)
      } else if sc.matches("<!") || sc.matches("<?") {
        let start = sc.pos
        while !sc.eof() && sc.peek(0) != 62 {
          let _ = sc.advance()
        }
        if !sc.eof() {
          let _ = sc.advance()
        }
        sc.push(start, sc.pos, Meta)
      } else {
        st = html_tag_start(sc)
        if st != 0 {
          return (sc.tokens, st)
        }
      }
    } else {
      let start = sc.pos
      while !sc.eof() && sc.peek(0) != 60 {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, VariableName)
    }
  }
  (sc.tokens, 0)
}

///|
fn markup_language(name : String) -> Language {
  {
    name,
    tokenizer: html_tokenizer,
    indent_fn: None,
    brackets: [("<", ">")],
    comment_tokens: Some(("<!--", "-->")),
    comment_line: None,
  }
}

///|
pub fn html_language() -> Language {
  markup_language("html")
}

///|
pub fn xml_language() -> Language {
  markup_language("xml")
}

///|
pub fn vue_language() -> Language {
  markup_language("vue")
}

///|
fn css_language_named(name : String, line_comments : Array[String]) -> Language {
  generic_language(
    lang_config(
      name,
      keywords=[
        "important", "media", "import", "charset", "keyframes", "font-face", "supports",
        "mixin", "include", "extend", "function", "if", "else", "each", "for", "return",
        "use", "forward", "layer", "container", "namespace",
      ],
      atoms=[
        "inherit", "initial", "unset", "revert", "none", "auto", "block", "inline",
        "flex", "grid", "absolute", "relative", "fixed", "static", "transparent",
      ],
      line_comments~,
      block_comments=[("/*", "*/")],
      quotes=["\"", "'"],
      at_keywords=true,
      hash_hex_colors=true,
      property_before=[58],
      dollar_vars=name != "css",
      leading_dot_numbers=true,
      punct_chars="()[]{}:;,",
      operator_chars="+-*/%<>=!~&|^",
    ),
  )
}

///|
pub fn css_language() -> Language {
  css_language_named("css", [])
}

///|
pub fn scss_language() -> Language {
  css_language_named("scss", ["//"])
}

///|
pub fn less_language() -> Language {
  css_language_named("less", ["//"])
}
