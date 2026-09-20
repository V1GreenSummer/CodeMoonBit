///|
fn yaml_key_char(c : Int) -> Bool {
  is_word(c) || c == 45 || c == 46 || c == 47
}

///|
fn scan_decimal_number(sc : Scanner) -> Unit {
  let start = sc.pos
  if sc.peek(0) == 45 || sc.peek(0) == 43 {
    let _ = sc.advance()
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
      while is_digit(sc.peek(0)) {
        let _ = sc.advance()
      }
    } else {
      sc.pos = save
    }
  }
  sc.push(start, sc.pos, Number)
}

///|
/// YAML: comments, `key:` property names, list markers, flow collections,
/// anchors/aliases/tags and quoted or scalar values.
fn yaml_tokenizer(line : String, _state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  let mut i = 0
  while i < sc.len && sc.code_at(i) == 32 {
    i = i + 1
  }
  if sc.code_at(i) == 37 {
    sc.push(i, sc.len, Meta)
    return (sc.tokens, 0)
  }
  let is_doc_marker = (
      sc.code_at(i) == 45 && sc.code_at(i + 1) == 45 && sc.code_at(i + 2) == 45
    ) ||
    (sc.code_at(i) == 46 && sc.code_at(i + 1) == 46 && sc.code_at(i + 2) == 46)
  if is_doc_marker {
    sc.push(i, i + 3, Meta)
    sc.pos = i + 3
  } else {
    sc.pos = i
  }
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
    } else if c == 45 && (is_whitespace(sc.peek(1)) || sc.peek(1) == -1) {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
    } else if (c == 45 && is_digit(sc.peek(1))) || is_digit(c) {
      scan_decimal_number(sc)
    } else if c == 91 || c == 93 || c == 123 || c == 125 || c == 44 || c == 58 {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
    } else if c == 38 || c == 42 {
      let start = sc.pos
      let _ = sc.advance()
      while yaml_key_char(sc.peek(0)) {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, VariableName)
    } else if c == 33 {
      let start = sc.pos
      let _ = sc.advance()
      while yaml_key_char(sc.peek(0)) || sc.peek(0) == 33 {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Meta)
    } else if yaml_key_char(c) {
      let start = sc.pos
      while yaml_key_char(sc.peek(0)) {
        let _ = sc.advance()
      }
      let word = line[start:sc.pos].to_owned()
      let mut look = sc.pos
      while look < sc.len && sc.code_at(look) == 32 {
        look = look + 1
      }
      let typ = if sc.code_at(look) == 58 {
        PropertyName
      } else if word == "true" ||
        word == "false" ||
        word == "null" ||
        word == "~" ||
        word == "yes" ||
        word == "no" {
        Atom
      } else {
        VariableName
      }
      sc.push(start, sc.pos, typ)
    } else {
      let start = sc.pos
      let _ = sc.advance()
      sc.push(start, sc.pos, Invalid)
    }
  }
  (sc.tokens, 0)
}

///|
pub fn yaml_language() -> Language {
  {
    name: "yaml",
    tokenizer: yaml_tokenizer,
    indent_fn: None,
    brackets: [("[", "]"), ("{", "}")],
    comment_tokens: None,
    comment_line: Some("#"),
  }
}

///|
pub fn toml_language() -> Language {
  generic_language(
    lang_config(
      "toml",
      atoms=["true", "false"],
      line_comments=["#"],
      quotes=["\"", "'"],
      triples=["\"\"\"", "'''"],
      property_before=[61],
      table_headers=true,
      leading_dot_numbers=true,
      punct_chars="[]{}.,:",
      operator_chars="=+-",
    ),
  )
}

///|
pub fn ini_language() -> Language {
  generic_language(
    lang_config(
      "ini",
      atoms=["true", "false", "yes", "no", "on", "off"],
      line_comments=["#", ";"],
      quotes=["\"", "'"],
      property_before=[61],
      table_headers=true,
      punct_chars="[].,:",
      operator_chars="=",
    ),
  )
}

///|
pub fn sql_language() -> Language {
  generic_language(
    lang_config(
      "sql",
      keywords=[
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
        "create", "table", "alter", "drop", "index", "view", "join", "inner", "left",
        "right", "outer", "full", "cross", "on", "group", "by", "order", "having",
        "limit", "offset", "union", "all", "distinct", "as", "and", "or", "not",
        "is", "in", "like", "between", "exists", "case", "when", "then", "else",
        "end", "primary", "key", "foreign", "references", "constraint", "default",
        "unique", "check", "cascade", "database", "schema", "grant", "revoke", "begin",
        "commit", "rollback", "transaction", "with", "returning", "if", "replace",
        "trigger", "function", "procedure",
      ],
      types=[
        "int", "integer", "bigint", "smallint", "tinyint", "decimal", "numeric",
        "float", "real", "double", "precision", "char", "varchar", "text", "date",
        "time", "timestamp", "boolean", "bool", "blob", "json", "uuid", "serial",
      ],
      atoms=["null", "true", "false"],
      case_insensitive=true,
      line_comments=["--"],
      block_comments=[("/*", "*/")],
      quotes=["'", "\""],
      doubled_quotes=true,
      operator_chars="+-*/%&|^!~<>=?",
    ),
  )
}

///|
/// LaTeX: `%` comments, `\commands`, `$math$`, braces and plain text.
fn latex_tokenizer(line : String, _state : Int) -> (Array[Token], Int) {
  let sc = Scanner::new(line)
  while !sc.eof() {
    let c = sc.peek(0)
    if is_whitespace(c) {
      let _ = sc.advance()
    } else if c == 37 {
      let start = sc.pos
      while !sc.eof() {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, Comment)
    } else if c == 92 {
      let start = sc.pos
      let _ = sc.advance()
      let next = sc.peek(0)
      if is_alpha(next) || next == 64 {
        while is_alpha(sc.peek(0)) || sc.peek(0) == 64 {
          let _ = sc.advance()
        }
        if sc.peek(0) == 42 {
          let _ = sc.advance()
        }
        sc.push(start, sc.pos, Keyword)
      } else {
        let _ = sc.advance()
        sc.push(start, sc.pos, Operator)
      }
    } else if c == 36 {
      let start = sc.pos
      let _ = sc.advance()
      if sc.peek(0) == 36 {
        let _ = sc.advance()
      }
      while !sc.eof() {
        if sc.peek(0) == 92 {
          sc.pos = sc.pos + 1
          if !sc.eof() {
            let _ = sc.advance()
          }
        } else if sc.peek(0) == 36 {
          let _ = sc.advance()
          break
        } else {
          let _ = sc.advance()
        }
      }
      sc.push(start, sc.pos, String)
    } else if c == 123 || c == 125 || c == 91 || c == 93 {
      sc.push(sc.pos, sc.pos + 1, Punctuation)
      sc.pos = sc.pos + 1
    } else if c == 38 ||
      c == 95 ||
      c == 94 ||
      c == 126 ||
      c == 35 ||
      c == 42 ||
      c == 43 ||
      c == 45 ||
      c == 61 {
      let start = sc.pos
      let _ = sc.advance()
      sc.push(start, sc.pos, Operator)
    } else if is_word_start(c) {
      let start = sc.pos
      while is_word(sc.peek(0)) || sc.peek(0) == 45 {
        let _ = sc.advance()
      }
      sc.push(start, sc.pos, VariableName)
    } else if is_digit(c) {
      scan_decimal_number(sc)
    } else {
      let start = sc.pos
      let _ = sc.advance()
      sc.push(start, sc.pos, Invalid)
    }
  }
  (sc.tokens, 0)
}

///|
pub fn latex_language() -> Language {
  {
    name: "latex",
    tokenizer: latex_tokenizer,
    indent_fn: None,
    brackets: [("{", "}"), ("[", "]"), ("(", ")")],
    comment_tokens: None,
    comment_line: Some("%"),
  }
}
