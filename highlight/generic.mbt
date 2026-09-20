///|
const STATE_BLOCK_BASE : Int = 1

///|
const STATE_BLOCK_STRIDE : Int = 64

///|
const STATE_TEMPLATE_BASE : Int = 1000

///|
const STATE_TRIPLE_BASE : Int = 1100

///|
const STATE_QUOTE_BASE : Int = 1150

///|
const STATE_SPECIAL_BASE : Int = 1200

///|
const STATE_RAW_BASE : Int = 1300

///|
const STATE_RUBY_BEGIN : Int = STATE_SPECIAL_BASE + 1

///|
const STATE_CPPRAW : Int = STATE_SPECIAL_BASE + 3

///|
const STATE_CSVERBATIM : Int = STATE_SPECIAL_BASE + 4

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
fn find_block_open(cfg : LangConfig, sc : Scanner) -> Int {
  let mut i = 0
  while i < cfg.block_comments.length() {
    let (open, _) = cfg.block_comments[i]
    if sc.matches(open) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn find_line_comment(cfg : LangConfig, sc : Scanner) -> Int {
  let mut i = 0
  while i < cfg.line_comments.length() {
    if sc.matches(cfg.line_comments[i]) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn find_template_open(cfg : LangConfig, sc : Scanner) -> Int {
  let mut i = 0
  while i < cfg.templates.length() {
    if sc.matches(cfg.templates[i]) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn find_triple_open(cfg : LangConfig, sc : Scanner) -> Int {
  let mut i = 0
  while i < cfg.triples.length() {
    if sc.matches(cfg.triples[i]) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn find_quote_open(cfg : LangConfig, sc : Scanner) -> Int {
  let mut i = 0
  while i < cfg.quotes.length() {
    if sc.matches(cfg.quotes[i]) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Index of a string prefix (Python-style `r`, `b`, `f`, ...) whose following
/// code unit is a quote character.
fn find_prefix(cfg : LangConfig, sc : Scanner) -> Int {
  let mut i = 0
  while i < cfg.string_prefixes.length() {
    let p = cfg.string_prefixes[i]
    if sc.matches(p) {
      let after = sc.code_at(sc.pos + p.length())
      if after == 34 || after == 39 {
        return i
      }
    }
    i = i + 1
  }
  -1
}

///|
/// Scans an open block comment, tracking nesting depth. Returns the number of
/// closing delimiters still required (`0` means the comment ended here).
fn scan_block_body(
  sc : Scanner,
  open : String,
  close : String,
  nested : Bool,
  start_depth : Int,
) -> Int {
  let start = sc.pos
  let mut depth = start_depth
  while !sc.eof() {
    if nested && sc.matches(open) {
      sc.pos = sc.pos + open.length()
      if depth < STATE_BLOCK_STRIDE - 1 {
        depth = depth + 1
      }
    } else if sc.matches(close) {
      sc.pos = sc.pos + close.length()
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
fn scan_delimited(
  sc : Scanner,
  delim : String,
  escape : Int,
  uses_escape : Bool,
  doubled : Bool,
) -> Bool {
  while !sc.eof() {
    if uses_escape && escape != 0 && sc.peek(0) == escape {
      sc.pos = sc.pos + 1
      if !sc.eof() {
        let _ = sc.advance()
      }
    } else if sc.matches(delim) {
      sc.pos = sc.pos + delim.length()
      return true
    } else if doubled &&
      delim.length() == 1 &&
      sc.peek(0) == delim.unsafe_get(0).to_int() &&
      sc.peek(1) == sc.peek(0) {
      sc.pos = sc.pos + 2
    } else {
      let _ = sc.advance()
    }
  }
  false
}

///|
fn scan_quote_at(
  sc : Scanner,
  quote : String,
  escape : Int,
  uses_escape : Bool,
  doubled : Bool,
) -> Bool {
  sc.pos = sc.pos + quote.length()
  scan_delimited(sc, quote, escape, uses_escape, doubled)
}

///|
fn scan_until_pair(sc : Scanner, pat : String) -> Bool {
  while !sc.eof() {
    if sc.matches(pat) {
      sc.pos = sc.pos + pat.length()
      return true
    }
    let _ = sc.advance()
  }
  false
}

///|
fn scan_raw_body(sc : Scanner, hashes : Int) -> Bool {
  while !sc.eof() {
    if sc.peek(0) == 34 {
      let mut ok = true
      let mut i = 0
      while i < hashes {
        if sc.code_at(sc.pos + 1 + i) != 35 {
          ok = false
          break
        }
        i = i + 1
      }
      if ok {
        sc.pos = sc.pos + 1 + hashes
        return true
      }
    }
    let _ = sc.advance()
  }
  false
}

///|
/// Scans the body of a prefixed string (the prefix is already consumed).
/// Returns a continuation state or `0` when the string ended on this line.
fn scan_prefixed_body(cfg : LangConfig, sc : Scanner, raw : Bool) -> Int {
  let uses_escape = !raw && cfg.quote_escapes
  let ti = find_triple_open(cfg, sc)
  if ti >= 0 {
    let t = cfg.triples[ti]
    let closed = scan_quote_at(sc, t, cfg.escape, uses_escape, false)
    if closed {
      return 0
    }
    return STATE_TRIPLE_BASE + ti
  }
  let qi = find_quote_open(cfg, sc)
  if qi >= 0 {
    let q = cfg.quotes[qi]
    let closed = scan_quote_at(
      sc,
      q,
      cfg.escape,
      uses_escape,
      cfg.doubled_quotes,
    )
    if closed {
      return 0
    }
    if cfg.multiline_quotes {
      return STATE_QUOTE_BASE + qi
    }
  }
  0
}

///|
fn scan_char_literal(sc : Scanner, escape : Int) -> Bool {
  let save = sc.pos
  sc.pos = sc.pos + 1
  if sc.eof() {
    sc.pos = save
    return false
  }
  if sc.peek(0) == escape {
    sc.pos = sc.pos + 1
    if sc.eof() {
      sc.pos = save
      return false
    }
    let _ = sc.advance()
    let mut steps = 0
    while !sc.eof() && sc.peek(0) != 39 && steps < 8 {
      let _ = sc.advance()
      steps = steps + 1
    }
  } else {
    let _ = sc.advance()
  }
  if !sc.eof() && sc.peek(0) == 39 {
    sc.pos = sc.pos + 1
    sc.push(save, sc.pos, String)
    return true
  }
  sc.pos = save
  false
}

///|
fn try_regex(sc : Scanner) -> Bool {
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
fn scan_number_suffix(sc : Scanner, cfg : LangConfig) -> Unit {
  if cfg.number_suffix_chars.length() > 0 &&
    ch_in(cfg.number_suffix_chars, sc.peek(0)) {
    while is_word(sc.peek(0)) {
      let _ = sc.advance()
    }
  }
}

///|
fn scan_number(sc : Scanner, cfg : LangConfig) -> Unit {
  let start = sc.pos
  let _ = sc.advance()
  if code_unit(sc.line, start) == 48 {
    let second = sc.peek(0)
    if second == 120 || second == 88 {
      let _ = sc.advance()
      while is_hex(sc.peek(0)) || sc.peek(0) == 95 {
        let _ = sc.advance()
      }
      scan_number_suffix(sc, cfg)
      sc.push(start, sc.pos, Number)
      return
    } else if second == 98 || second == 66 {
      let _ = sc.advance()
      while sc.peek(0) == 48 || sc.peek(0) == 49 || sc.peek(0) == 95 {
        let _ = sc.advance()
      }
      scan_number_suffix(sc, cfg)
      sc.push(start, sc.pos, Number)
      return
    } else if second == 111 || second == 79 {
      let _ = sc.advance()
      while (sc.peek(0) >= 48 && sc.peek(0) <= 55) || sc.peek(0) == 95 {
        let _ = sc.advance()
      }
      scan_number_suffix(sc, cfg)
      sc.push(start, sc.pos, Number)
      return
    }
  }
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
  scan_number_suffix(sc, cfg)
  sc.push(start, sc.pos, Number)
}

///|
fn classify_word(cfg : LangConfig, word : String) -> TokenType {
  let key = if cfg.case_insensitive { word.to_lower() } else { word }
  match cfg.words.get(key) {
    Some(t) => t
    None =>
      if cfg.capitalized_types && is_upper(code_unit(word, 0)) {
        TypeName
      } else {
        VariableName
      }
  }
}

///|
/// Whether the next non-blank code unit is one of the configured
/// "property" delimiters (`:` for YAML/CSS, `=` for TOML/INI).
fn property_ahead(cfg : LangConfig, sc : Scanner) -> Bool {
  if cfg.property_before.length() == 0 {
    return false
  }
  let mut i = sc.pos
  while i < sc.len && (sc.code_at(i) == 32 || sc.code_at(i) == 9) {
    i = i + 1
  }
  cfg.property_before.contains(sc.code_at(i))
}

///|
fn scan_sigil(sc : Scanner) -> Unit {
  let start = sc.pos
  sc.pos = sc.pos + 1
  if sc.peek(0) == 123 {
    sc.push(start, sc.pos, VariableName)
    return
  }
  if is_digit(sc.peek(0)) {
    while is_digit(sc.peek(0)) {
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
/// Resumes a token that was left open at the end of the previous line.
/// Returns the state for the next line (`0` when the token finished).
fn resume_generic(cfg : LangConfig, sc : Scanner, st : Int) -> Int {
  if cfg.templates.length() > 0 &&
    st >= cfg.state_template_base &&
    st < cfg.state_template_base + cfg.templates.length() {
    let idx = st - cfg.state_template_base
    let closed = scan_delimited(
      sc,
      cfg.templates[idx],
      cfg.escape,
      cfg.template_escapes,
      false,
    )
    sc.push(0, sc.pos, String)
    return if closed { 0 } else { st }
  }
  if st >= STATE_TRIPLE_BASE && st < STATE_TRIPLE_BASE + cfg.triples.length() {
    let idx = st - STATE_TRIPLE_BASE
    let closed = scan_delimited(sc, cfg.triples[idx], cfg.escape, true, false)
    sc.push(0, sc.pos, String)
    return if closed { 0 } else { st }
  }
  if st >= STATE_QUOTE_BASE && st < STATE_QUOTE_BASE + cfg.quotes.length() {
    let idx = st - STATE_QUOTE_BASE
    let closed = scan_delimited(
      sc,
      cfg.quotes[idx],
      cfg.escape,
      cfg.quote_escapes,
      cfg.doubled_quotes,
    )
    sc.push(0, sc.pos, String)
    return if closed { 0 } else { st }
  }
  if st >= STATE_BLOCK_BASE && st < STATE_BLOCK_BASE + 8 * STATE_BLOCK_STRIDE {
    let rel = st - STATE_BLOCK_BASE
    let idx = rel / STATE_BLOCK_STRIDE
    if idx >= cfg.block_comments.length() {
      return 0
    }
    let depth = rel % STATE_BLOCK_STRIDE + 1
    let (open, close) = cfg.block_comments[idx]
    let d = scan_block_body(sc, open, close, cfg.nested_comments, depth)
    return if d == 0 {
      0
    } else {
      STATE_BLOCK_BASE + idx * STATE_BLOCK_STRIDE + d - 1
    }
  }
  if st >= STATE_RAW_BASE && st < STATE_RAW_BASE + 256 {
    let hashes = st - STATE_RAW_BASE
    let closed = scan_raw_body(sc, hashes)
    sc.push(0, sc.pos, String)
    return if closed { 0 } else { st }
  }
  if st == STATE_CPPRAW {
    let closed = scan_until_pair(sc, ")\"")
    sc.push(0, sc.pos, String)
    return if closed { 0 } else { st }
  }
  if st == STATE_CSVERBATIM {
    let closed = scan_delimited(sc, "\"", 0, false, true)
    sc.push(0, sc.pos, String)
    return if closed { 0 } else { st }
  }
  if st == STATE_RUBY_BEGIN && cfg.ruby_begin {
    let closed = sc.matches("=end")
    let start = sc.pos
    while !sc.eof() {
      let _ = sc.advance()
    }
    sc.push(start, sc.pos, Comment)
    return if closed { 0 } else { st }
  }
  0
}

///|
/// Generic, configuration-driven line tokenizer. The same code powers every
/// language whose syntax is described by a `LangConfig`.
fn generic_tokenize(
  cfg : LangConfig,
  line : String,
  state : Int,
) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  let mut st = state
  if st != 0 {
    st = resume_generic(cfg, sc, st)
    if st != 0 {
      return (sc.tokens, st)
    }
  }
  let mut prev_char = -1
  let mut prev_word = ""
  while !sc.eof() {
    let c = sc.peek(0)
    if is_whitespace(c) {
      let _ = sc.advance()
      continue
    }
    if cfg.shebang && sc.pos == 0 && c == 35 && sc.peek(1) == 33 {
      let start = sc.pos
      while !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Comment)
      prev_char = -1
      prev_word = ""
      continue
    }
    if cfg.ruby_begin && sc.pos == 0 && sc.matches("=begin") {
      let start = sc.pos
      while !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Comment)
      return (sc.tokens, STATE_RUBY_BEGIN)
    }
    let bi = find_block_open(cfg, sc)
    if bi >= 0 {
      let (open, close) = cfg.block_comments[bi]
      sc.pos = sc.pos + open.length()
      let d = scan_block_body(sc, open, close, cfg.nested_comments, 1)
      if d > 0 {
        return (sc.tokens, STATE_BLOCK_BASE + bi * STATE_BLOCK_STRIDE + d - 1)
      }
      prev_char = 42
      prev_word = ""
      continue
    }
    if cfg.hash_hex_colors && c == 35 && is_hex(sc.peek(1)) {
      let start = sc.pos
      let _ = sc.advance()
      while is_hex(sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Number)
      prev_char = -1
      prev_word = ""
      continue
    }
    let li = find_line_comment(cfg, sc)
    if li >= 0 {
      let start = sc.pos
      while !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Comment)
      prev_char = -1
      prev_word = ""
      continue
    }
    if cfg.preprocessor && c == 35 && sc.only_ws_before() {
      let start = sc.pos
      while !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Meta)
      prev_char = -1
      prev_word = ""
      continue
    }
    if cfg.hash_attributes && c == 35 {
      let after = sc.peek(1)
      if after == 91 || (after == 33 && sc.peek(2) == 91) {
        let start = sc.pos
        let _ = sc.advance()
        if sc.peek(0) == 33 {
          let _ = sc.advance()
        }
        if sc.peek(0) == 91 {
          let _ = sc.advance()
        }
        let mut depth = 1
        while !sc.eof() && depth > 0 {
          let cc = sc.peek(0)
          if cc == 91 {
            depth = depth + 1
            let _ = sc.advance()
          } else if cc == 93 {
            depth = depth - 1
            let _ = sc.advance()
          } else {
            let _ = sc.advance()
          }
        }
        sc.push(start, sc.pos, Attribute)
        prev_char = -1
        prev_word = ""
        continue
      }
    }
    if cfg.table_headers && c == 91 && sc.only_ws_before() {
      let start = sc.pos
      let _ = sc.advance()
      while !sc.eof() && sc.peek(0) != 93 {
        let _ = sc.advance()
      }
      if !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Keyword)
      prev_char = -1
      prev_word = ""
      continue
    }
    let ti = find_template_open(cfg, sc)
    if ti >= 0 {
      let t = cfg.templates[ti]
      let start = sc.pos
      let closed = scan_quote_at(sc, t, cfg.escape, cfg.template_escapes, false)
      sc.push(start, sc.pos, String)
      if !closed {
        return (sc.tokens, cfg.state_template_base + ti)
      }
      prev_char = 96
      prev_word = ""
      continue
    }
    let qi = find_triple_open(cfg, sc)
    if qi >= 0 {
      let t = cfg.triples[qi]
      let start = sc.pos
      let closed = scan_quote_at(sc, t, cfg.escape, true, false)
      sc.push(start, sc.pos, String)
      if !closed {
        return (sc.tokens, STATE_TRIPLE_BASE + qi)
      }
      prev_char = 34
      prev_word = ""
      continue
    }
    if cfg.string_prefixes.length() > 0 {
      let pi = find_prefix(cfg, sc)
      if pi >= 0 {
        let p = cfg.string_prefixes[pi]
        let start = sc.pos
        sc.pos = sc.pos + p.length()
        let raw = ch_in(p, 114) || ch_in(p, 82)
        let ns = scan_prefixed_body(cfg, sc, raw)
        sc.push(start, sc.pos, String)
        if ns != 0 {
          return (sc.tokens, ns)
        }
        prev_char = 34
        prev_word = ""
        continue
      }
    }
    if cfg.rust_raw && c == 114 {
      let save = sc.pos
      let start = sc.pos
      sc.pos = sc.pos + 1
      let mut hashes = 0
      while sc.peek(0) == 35 {
        hashes = hashes + 1
        sc.pos = sc.pos + 1
      }
      if sc.peek(0) == 34 {
        sc.pos = sc.pos + 1
        let closed = scan_raw_body(sc, hashes)
        sc.push(start, sc.pos, String)
        if !closed {
          return (sc.tokens, STATE_RAW_BASE + hashes)
        }
        prev_char = 34
        prev_word = ""
        continue
      }
      sc.pos = save
    }
    if cfg.cpp_raw && c == 82 && sc.peek(1) == 34 {
      let start = sc.pos
      sc.pos = sc.pos + 2
      let closed = scan_until_pair(sc, ")\"")
      sc.push(start, sc.pos, String)
      if !closed {
        return (sc.tokens, STATE_CPPRAW)
      }
      prev_char = 34
      prev_word = ""
      continue
    }
    if cfg.csharp_verbatim && c == 64 && sc.peek(1) == 34 {
      let start = sc.pos
      sc.pos = sc.pos + 2
      let closed = scan_delimited(sc, "\"", 0, false, true)
      sc.push(start, sc.pos, String)
      if !closed {
        return (sc.tokens, STATE_CSVERBATIM)
      }
      prev_char = 34
      prev_word = ""
      continue
    }
    let qi2 = find_quote_open(cfg, sc)
    if qi2 >= 0 {
      let q = cfg.quotes[qi2]
      let start = sc.pos
      let closed = scan_quote_at(
        sc,
        q,
        cfg.escape,
        cfg.quote_escapes,
        cfg.doubled_quotes,
      )
      sc.push(start, sc.pos, String)
      if !closed && cfg.multiline_quotes {
        return (sc.tokens, STATE_QUOTE_BASE + qi2)
      }
      prev_char = q.unsafe_get(0).to_int()
      prev_word = ""
      continue
    }
    if cfg.char_literals && c == 39 {
      if scan_char_literal(sc, cfg.escape) {
        prev_char = 39
        prev_word = ""
        continue
      }
      if cfg.rust_lifetimes && (is_alpha(sc.peek(1)) || sc.peek(1) == 95) {
        let start = sc.pos
        sc.pos = sc.pos + 1
        while is_word(sc.peek(0)) {
          let _ = sc.advance()
        }
        sc.push(start, sc.pos, VariableName)
        prev_char = -1
        prev_word = ""
        continue
      }
    }
    if cfg.allow_regex &&
      c == 47 &&
      (
        prev_char == -1 ||
        is_regex_prefix_char(prev_char) ||
        is_regex_prefix_word(prev_word)
      ) &&
      try_regex(sc) {
      prev_char = 47
      prev_word = ""
      continue
    }
    if is_digit(c) ||
      (c == 46 && cfg.leading_dot_numbers && is_digit(sc.peek(1))) {
      scan_number(sc, cfg)
      prev_char = sc.code_at(sc.pos - 1)
      prev_word = ""
      continue
    }
    if cfg.dollar_vars &&
      c == 36 &&
      (is_word_start(sc.peek(1)) || is_digit(sc.peek(1)) || sc.peek(1) == 123) {
      scan_sigil(sc)
      prev_char = -1
      prev_word = ""
      continue
    }
    if cfg.sigil_chars.length() > 0 &&
      ch_in(cfg.sigil_chars, c) &&
      is_word_start(sc.peek(1)) {
      scan_sigil(sc)
      prev_char = -1
      prev_word = ""
      continue
    }
    if cfg.colon_atoms &&
      c == 58 &&
      is_word_start(sc.peek(1)) &&
      sc.peek(1) != 58 {
      let start = sc.pos
      sc.pos = sc.pos + 1
      while is_word(sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Atom)
      prev_char = -1
      prev_word = ""
      continue
    }
    if c == 64 &&
      (cfg.at_decorators || cfg.at_keywords) &&
      is_word_start(sc.peek(1)) {
      let start = sc.pos
      let _ = sc.advance()
      while is_word(sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(
        start,
        sc.pos,
        if cfg.at_decorators {
          Attribute
        } else {
          Keyword
        },
      )
      prev_char = -1
      prev_word = ""
      continue
    }
    if is_word_start(c) {
      let start = sc.pos
      while is_word(sc.peek(0)) ||
            (cfg.hyphen_words && sc.peek(0) == 45 && is_word(sc.peek(1))) {
        if sc.peek(0) == 45 {
          sc.pos = sc.pos + 1
        }
        let _ = sc.advance()
      }
      let word = sc.line[start:sc.pos].to_owned()
      let typ = if property_ahead(cfg, sc) {
        PropertyName
      } else if cfg.hyphen_words && word.contains("-") {
        Keyword
      } else {
        classify_word(cfg, word)
      }
      sc.push(start, sc.pos, typ)
      prev_char = sc.code_at(sc.pos - 1)
      prev_word = word
      continue
    }
    if ch_in(cfg.punct_chars, c) {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
      prev_char = c
      prev_word = ""
      continue
    }
    if ch_in(cfg.operator_chars, c) {
      let start = sc.pos
      while ch_in(cfg.operator_chars, sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Operator)
      prev_char = sc.code_at(sc.pos - 1)
      prev_word = ""
      continue
    }
    let start = sc.pos
    let _ = sc.advance()
    sc.push(start, sc.pos, Invalid)
    prev_char = sc.code_at(sc.pos - 1)
    prev_word = ""
  }
  (sc.tokens, st)
}
