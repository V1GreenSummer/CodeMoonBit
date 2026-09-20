///|
pub fn python_language() -> Language {
  generic_language(
    lang_config(
      "python",
      keywords=[
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
        "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
        "import", "in", "is", "lambda", "match", "case", "nonlocal", "not", "or",
        "pass", "raise", "return", "try", "while", "with", "yield",
      ],
      types=[
        "int", "float", "str", "bool", "list", "dict", "tuple", "set", "bytes", "object",
      ],
      atoms=["True", "False", "None"],
      line_comments=["#"],
      quotes=["\"", "'"],
      triples=["\"\"\"", "'''"],
      string_prefixes=[
        "rb", "br", "fr", "rf", "RB", "BR", "FR", "RF", "r", "b", "f", "u", "R",
        "B", "F", "U",
      ],
      at_decorators=true,
      number_suffix_chars="jJ",
      leading_dot_numbers=true,
      operator_chars="+-*/%&|^!~<>=?@",
    ),
  )
}

///|
pub fn ruby_language() -> Language {
  generic_language(
    lang_config(
      "ruby",
      keywords=[
        "alias", "and", "begin", "break", "case", "class", "def", "defined", "do",
        "else", "elsif", "end", "ensure", "for", "if", "in", "module", "next", "not",
        "or", "redo", "rescue", "retry", "return", "self", "super", "then", "undef",
        "unless", "until", "when", "while", "yield",
      ],
      atoms=["true", "false", "nil"],
      line_comments=["#"],
      quotes=["\"", "'"],
      colon_atoms=true,
      sigil_chars="$@",
      shebang=true,
      ruby_begin=true,
      allow_regex=true,
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn perl_language() -> Language {
  generic_language(
    lang_config(
      "perl",
      keywords=[
        "and", "cmp", "default", "do", "else", "elsif", "eq", "for", "foreach", "ge",
        "given", "goto", "gt", "if", "last", "le", "local", "lt", "my", "ne", "next",
        "not", "or", "our", "package", "redo", "require", "return", "state", "sub",
        "unless", "until", "use", "when", "while", "xor",
      ],
      atoms=["undef"],
      line_comments=["#"],
      quotes=["\"", "'"],
      sigil_chars="$@%",
      shebang=true,
      allow_regex=true,
      operator_chars="+-*/%&|^!~<>=?:.",
    ),
  )
}

///|
pub fn lua_language() -> Language {
  generic_language(
    lang_config(
      "lua",
      keywords=[
        "and", "break", "do", "else", "elseif", "end", "for", "function", "goto",
        "if", "in", "local", "not", "or", "repeat", "return", "then", "until", "while",
      ],
      atoms=["true", "false", "nil"],
      line_comments=["--"],
      block_comments=[("--[[", "]]")],
      quotes=["\"", "'"],
      number_suffix_chars="",
      operator_chars="+-*/%^#&|~<>=?",
    ),
  )
}

///|
pub fn r_language() -> Language {
  generic_language(
    lang_config(
      "r",
      keywords=[
        "break", "else", "for", "function", "if", "in", "next", "repeat", "while",
      ],
      types=[
        "character", "numeric", "integer", "logical", "complex", "list", "vector",
      ],
      atoms=["TRUE", "FALSE", "NULL", "NA", "NaN", "Inf"],
      line_comments=["#"],
      quotes=["\"", "'"],
      capitalized_types=false,
      operator_chars="+-*/^%&|!~<>=?:@$",
    ),
  )
}

///|
pub fn julia_language() -> Language {
  generic_language(
    lang_config(
      "julia",
      keywords=[
        "baremodule", "begin", "break", "catch", "const", "continue", "do", "else",
        "elseif", "end", "export", "finally", "for", "function", "global", "if",
        "import", "let", "local", "macro", "module", "quote", "return", "struct",
        "try", "using", "while", "where",
      ],
      types=[
        "Any", "Array", "Bool", "Char", "Dict", "Float32", "Float64", "Int", "Int32",
        "Int64", "Nothing", "String", "Tuple", "Vector",
      ],
      atoms=["true", "false", "nothing", "missing"],
      line_comments=["#"],
      block_comments=[("#=", "=#")],
      nested_comments=true,
      quotes=["\""],
      triples=["\"\"\""],
      char_literals=true,
      dollar_vars=true,
      operator_chars="+-*/\\^%&|!~<>=?:'",
    ),
  )
}

///|
pub fn elixir_language() -> Language {
  generic_language(
    lang_config(
      "elixir",
      keywords=[
        "after", "and", "case", "catch", "cond", "def", "defmacro", "defmodule",
        "defp", "defstruct", "do", "else", "end", "fn", "for", "if", "import", "in",
        "not", "or", "quote", "raise", "receive", "require", "rescue", "try", "unless",
        "unquote", "use", "when", "with",
      ],
      atoms=["true", "false", "nil"],
      line_comments=["#"],
      quotes=["\"", "'"],
      triples=["\"\"\"", "'''"],
      colon_atoms=true,
      at_decorators=true,
      operator_chars="+-*/\\^&|!~<>=?@",
    ),
  )
}

///|
pub fn erlang_language() -> Language {
  generic_language(
    lang_config(
      "erlang",
      keywords=[
        "after", "and", "andalso", "band", "begin", "bnot", "bor", "bsl", "bsr",
        "bxor", "case", "catch", "cond", "div", "end", "fun", "if", "let", "not",
        "of", "or", "orelse", "receive", "rem", "try", "when", "xor",
      ],
      atoms=["true", "false"],
      line_comments=["%"],
      quotes=["\""],
      capitalized_types=false,
      operator_chars="+-*/&|!~<>=?:@",
    ),
  )
}

///|
pub fn haskell_language() -> Language {
  generic_language(
    lang_config(
      "haskell",
      keywords=[
        "case", "class", "data", "default", "deriving", "do", "else", "foreign",
        "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "module",
        "newtype", "of", "then", "type", "where", "forall", "mdo",
      ],
      atoms=["True", "False"],
      line_comments=["--"],
      block_comments=[("{-", "-}")],
      nested_comments=true,
      quotes=["\""],
      char_literals=true,
      operator_chars="+-*/\\^%&|!~<>=?:$.",
    ),
  )
}

///|
pub fn ocaml_language() -> Language {
  generic_language(
    lang_config(
      "ocaml",
      keywords=[
        "and", "as", "assert", "begin", "class", "constraint", "do", "done", "downto",
        "else", "end", "exception", "external", "for", "fun", "function", "functor",
        "if", "in", "include", "inherit", "initializer", "lazy", "let", "match",
        "method", "module", "mutable", "new", "nonrec", "object", "of", "open", "or",
        "private", "rec", "sig", "struct", "then", "to", "try", "type", "val", "virtual",
        "when", "while", "with",
      ],
      types=[
        "int", "float", "string", "char", "bool", "list", "option", "array", "unit",
        "bytes",
      ],
      atoms=["true", "false"],
      block_comments=[("(*", "*)")],
      nested_comments=true,
      quotes=["\""],
      char_literals=true,
      punct_chars="()[]{};,.:",
      operator_chars="+-*/=<>@^|&!~?",
    ),
  )
}

///|
pub fn clojure_language() -> Language {
  generic_language(
    lang_config(
      "clojure",
      keywords=[
        "def", "defn", "defmacro", "defmethod", "defmulti", "defprotocol", "defrecord",
        "deftype", "do", "doseq", "dotimes", "fn", "if", "if-let", "if-not", "import",
        "in-ns", "let", "loop", "ns", "quote", "recur", "require", "set!", "throw",
        "try", "use", "var", "when", "when-let", "when-not",
      ],
      atoms=["true", "false", "nil"],
      line_comments=[";"],
      quotes=["\""],
      colon_atoms=true,
      punct_chars="()[]{},'",
      operator_chars="#@^`~\\",
    ),
  )
}

///|
pub fn lisp_language() -> Language {
  generic_language(
    lang_config(
      "lisp",
      keywords=[
        "append", "begin", "car", "cdr", "cond", "cons", "define", "define-syntax",
        "else", "for-each", "if", "lambda", "let", "let*", "letrec", "list", "map",
        "quasiquote", "quote", "set!", "unless", "unquote", "when",
      ],
      atoms=["nil"],
      line_comments=[";"],
      block_comments=[("#|", "|#")],
      nested_comments=true,
      quotes=["\""],
      brackets=[("(", ")")],
      punct_chars="()[]{}",
      operator_chars="'`#,;@^~\\",
    ),
  )
}
