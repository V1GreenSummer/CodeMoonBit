///|
/// Everything the generic tokenizer needs to know about a language. Built once
/// per language at construction so that tokenizing a line never allocates
/// lookup structures.
priv struct LangConfig {
  name : String
  words : Map[String, TokenType]
  case_insensitive : Bool
  capitalized_types : Bool
  line_comments : Array[String]
  block_comments : Array[(String, String)]
  nested_comments : Bool
  quotes : Array[String]
  quote_escapes : Bool
  multiline_quotes : Bool
  doubled_quotes : Bool
  triples : Array[String]
  templates : Array[String]
  template_escapes : Bool
  string_prefixes : Array[String]
  char_literals : Bool
  rust_lifetimes : Bool
  escape : Int
  allow_regex : Bool
  preprocessor : Bool
  hash_attributes : Bool
  at_decorators : Bool
  at_keywords : Bool
  dollar_vars : Bool
  sigil_chars : String
  shebang : Bool
  colon_atoms : Bool
  property_before : Array[Int]
  table_headers : Bool
  rust_raw : Bool
  cpp_raw : Bool
  csharp_verbatim : Bool
  number_suffix_chars : String
  leading_dot_numbers : Bool
  ruby_begin : Bool
  hash_hex_colors : Bool
  hyphen_words : Bool
  state_template_base : Int
  punct_chars : String
  operator_chars : String
  brackets : Array[(String, String)]
}

///|
/// Builds a `LangConfig` with sensible defaults, so per-language definitions
/// stay mostly data.
fn lang_config(
  name : String,
  keywords? : Array[String] = [],
  types? : Array[String] = [],
  atoms? : Array[String] = ["true", "false", "null", "nil", "none", "undefined"],
  extra_words? : Array[(String, TokenType)] = [],
  case_insensitive? : Bool = false,
  capitalized_types? : Bool = false,
  line_comments? : Array[String] = [],
  block_comments? : Array[(String, String)] = [],
  nested_comments? : Bool = false,
  quotes? : Array[String] = ["\"", "'"],
  quote_escapes? : Bool = true,
  multiline_quotes? : Bool = false,
  doubled_quotes? : Bool = false,
  triples? : Array[String] = [],
  templates? : Array[String] = [],
  template_escapes? : Bool = true,
  string_prefixes? : Array[String] = [],
  char_literals? : Bool = false,
  rust_lifetimes? : Bool = false,
  escape? : Int = 92,
  allow_regex? : Bool = false,
  preprocessor? : Bool = false,
  hash_attributes? : Bool = false,
  at_decorators? : Bool = false,
  at_keywords? : Bool = false,
  dollar_vars? : Bool = false,
  sigil_chars? : String = "",
  shebang? : Bool = false,
  colon_atoms? : Bool = false,
  property_before? : Array[Int] = [],
  table_headers? : Bool = false,
  rust_raw? : Bool = false,
  cpp_raw? : Bool = false,
  csharp_verbatim? : Bool = false,
  number_suffix_chars? : String = "",
  leading_dot_numbers? : Bool = false,
  ruby_begin? : Bool = false,
  hash_hex_colors? : Bool = false,
  hyphen_words? : Bool = false,
  state_template_base? : Int = STATE_TEMPLATE_BASE,
  punct_chars? : String = "()[]{}.,;:",
  operator_chars? : String = "+-*/%&|^!~<>=?@#$\\",
  brackets? : Array[(String, String)] = [("(", ")"), ("[", "]"), ("{", "}")],
) -> LangConfig {
  let words : Map[String, TokenType] = Map([])
  let add = fn(list : Array[String], typ : TokenType) {
    for w in list {
      words.set(if case_insensitive { w.to_lower() } else { w }, typ)
    }
  }
  add(keywords, Keyword)
  add(types, TypeName)
  add(atoms, Atom)
  for entry in extra_words {
    let (w, t) = entry
    words.set(if case_insensitive { w.to_lower() } else { w }, t)
  }
  {
    name,
    words,
    case_insensitive,
    capitalized_types,
    line_comments,
    block_comments,
    nested_comments,
    quotes,
    quote_escapes,
    multiline_quotes,
    doubled_quotes,
    triples,
    templates,
    template_escapes,
    string_prefixes,
    char_literals,
    rust_lifetimes,
    escape,
    allow_regex,
    preprocessor,
    hash_attributes,
    at_decorators,
    at_keywords,
    dollar_vars,
    sigil_chars,
    shebang,
    colon_atoms,
    property_before,
    table_headers,
    rust_raw,
    cpp_raw,
    csharp_verbatim,
    number_suffix_chars,
    leading_dot_numbers,
    ruby_begin,
    hash_hex_colors,
    hyphen_words,
    state_template_base,
    punct_chars,
    operator_chars,
    brackets,
  }
}

///|
/// Wraps a config into the public `Language` record, wiring up the comment
/// metadata exposed to the editor.
fn generic_language(cfg : LangConfig) -> Language {
  {
    name: cfg.name,
    tokenizer: fn(line, state) { generic_tokenize(cfg, line, state) },
    indent_fn: None,
    brackets: cfg.brackets.copy(),
    comment_tokens: if cfg.block_comments.length() > 0 {
      Some(cfg.block_comments[0])
    } else {
      None
    },
    comment_line: if cfg.line_comments.length() > 0 {
      Some(cfg.line_comments[0])
    } else {
      None
    },
  }
}
