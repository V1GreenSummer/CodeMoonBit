///|
/// JavaScript / TypeScript family keywords shared by the generic tokenizer.
fn js_keywords() -> Array[String] {
  [
    "break", "case", "catch", "class", "const", "continue", "debugger", "default",
    "delete", "do", "else", "export", "extends", "finally", "for", "function", "if",
    "import", "in", "instanceof", "let", "new", "return", "super", "switch", "this",
    "throw", "try", "typeof", "var", "void", "while", "with", "yield", "async", "await",
    "static", "of",
  ]
}

///|
pub fn javascript_language() -> Language {
  generic_language(
    lang_config(
      "javascript",
      keywords=js_keywords(),
      capitalized_types=true,
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\"", "'"],
      templates=["`"],
      allow_regex=true,
      state_template_base=2,
      operator_chars="+-*/%&|^!~<>=?@#\\",
    ),
  )
}

///|
pub fn typescript_language() -> Language {
  generic_language(
    lang_config(
      "typescript",
      keywords=js_keywords() +
        [
          "interface", "type", "enum", "namespace", "declare", "abstract", "implements",
          "readonly", "public", "private", "protected", "as", "satisfies", "keyof",
          "infer", "is", "asserts", "module", "global", "override",
        ],
      types=[
        "any", "unknown", "never", "object", "symbol", "bigint", "string", "number",
        "boolean", "void",
      ],
      capitalized_types=true,
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\"", "'"],
      templates=["`"],
      allow_regex=true,
      at_decorators=true,
      state_template_base=2,
      operator_chars="+-*/%&|^!~<>=?@#\\",
    ),
  )
}

///|
pub fn c_language() -> Language {
  generic_language(
    lang_config(
      "c",
      keywords=[
        "auto", "break", "case", "const", "continue", "default", "do", "else", "enum",
        "extern", "for", "goto", "if", "inline", "register", "restrict", "return",
        "sizeof", "static", "struct", "switch", "typedef", "union", "volatile", "while",
        "_Bool", "_Static_assert",
      ],
      types=[
        "char", "double", "float", "int", "long", "short", "signed", "unsigned",
        "void", "size_t", "ssize_t", "ptrdiff_t", "int8_t", "int16_t", "int32_t",
        "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "bool",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\""],
      char_literals=true,
      preprocessor=true,
      shebang=true,
      number_suffix_chars="uUlLfF",
      operator_chars="+-*/%&|^!~<>=?",
    ),
  )
}

///|
pub fn cpp_language() -> Language {
  generic_language(
    lang_config(
      "cpp",
      keywords=[
        "alignas", "alignof", "asm", "auto", "break", "case", "catch", "class", "co_await",
        "co_return", "co_yield", "concept", "const", "consteval", "constexpr", "constinit",
        "const_cast", "continue", "decltype", "default", "delete", "do", "dynamic_cast",
        "else", "enum", "explicit", "export", "extern", "final", "for", "friend",
        "goto", "if", "inline", "mutable", "namespace", "new", "noexcept", "operator",
        "override", "private", "protected", "public", "register", "reinterpret_cast",
        "requires", "return", "sizeof", "static", "static_assert", "static_cast",
        "struct", "switch", "template", "this", "thread_local", "throw", "try", "typedef",
        "typeid", "typename", "union", "using", "virtual", "volatile", "while",
      ],
      types=[
        "bool", "char", "char8_t", "char16_t", "char32_t", "double", "float", "int",
        "long", "short", "signed", "unsigned", "void", "wchar_t", "size_t", "string",
        "vector", "map", "set", "pair", "unique_ptr", "shared_ptr",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\""],
      char_literals=true,
      cpp_raw=true,
      preprocessor=true,
      shebang=true,
      number_suffix_chars="uUlLfF",
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn java_language() -> Language {
  generic_language(
    lang_config(
      "java",
      keywords=[
        "abstract", "assert", "break", "case", "catch", "class", "const", "continue",
        "default", "do", "else", "enum", "extends", "final", "finally", "for", "goto",
        "if", "implements", "import", "instanceof", "interface", "native", "new",
        "package", "private", "protected", "public", "record", "return", "sealed",
        "permits", "static", "strictfp", "super", "switch", "synchronized", "this",
        "throw", "throws", "transient", "try", "var", "volatile", "while", "yield",
      ],
      types=[
        "boolean", "byte", "char", "double", "float", "int", "long", "short", "void",
        "String", "Object", "Integer", "Long", "Double", "Float", "Boolean", "Character",
        "Byte", "Short", "List", "Map", "Set", "Optional", "Stream",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\""],
      triples=["\"\"\""],
      char_literals=true,
      at_decorators=true,
      number_suffix_chars="fFdDlL",
      operator_chars="+-*/%&|^!~<>=?@",
    ),
  )
}

///|
pub fn csharp_language() -> Language {
  generic_language(
    lang_config(
      "csharp",
      keywords=[
        "abstract", "as", "async", "await", "base", "break", "case", "catch", "checked",
        "class", "const", "continue", "default", "delegate", "do", "else", "enum",
        "event", "explicit", "extern", "file", "finally", "fixed", "for", "foreach",
        "goto", "if", "implicit", "in", "init", "interface", "internal", "is", "lock",
        "namespace", "new", "operator", "out", "override", "params", "partial", "private",
        "protected", "public", "readonly", "record", "ref", "required", "return",
        "scoped", "sealed", "sizeof", "stackalloc", "static", "struct", "switch",
        "this", "throw", "try", "typeof", "unchecked", "unsafe", "using", "virtual",
        "volatile", "when", "where", "while", "yield",
      ],
      types=[
        "bool", "byte", "char", "decimal", "double", "dynamic", "float", "int", "long",
        "nint", "nuint", "object", "sbyte", "short", "string", "uint", "ulong", "ushort",
        "void", "var",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\""],
      triples=["\"\"\""],
      char_literals=true,
      csharp_verbatim=true,
      preprocessor=true,
      number_suffix_chars="fFdDlLuUmM",
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn go_language() -> Language {
  generic_language(
    lang_config(
      "go",
      keywords=[
        "break", "case", "chan", "const", "continue", "default", "defer", "else",
        "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
        "map", "package", "range", "return", "select", "struct", "switch", "type",
        "var",
      ],
      types=[
        "bool", "byte", "complex64", "complex128", "error", "float32", "float64",
        "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8",
        "uint16", "uint32", "uint64", "uintptr", "any",
      ],
      atoms=["true", "false", "nil", "iota"],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\""],
      char_literals=true,
      templates=["`"],
      template_escapes=false,
      number_suffix_chars="i",
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn rust_language() -> Language {
  generic_language(
    lang_config(
      "rust",
      keywords=[
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
        "enum", "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match",
        "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct",
        "super", "trait", "type", "unsafe", "use", "where", "while", "macro_rules",
      ],
      types=[
        "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize",
        "str", "u8", "u16", "u32", "u64", "u128", "usize", "String", "Vec", "Option",
        "Result", "Box", "Rc", "Arc", "HashMap", "BTreeMap",
      ],
      atoms=["true", "false", "None", "Some", "Ok", "Err"],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      nested_comments=true,
      quotes=["\""],
      char_literals=true,
      rust_lifetimes=true,
      rust_raw=true,
      hash_attributes=true,
      number_suffix_chars="uif",
      operator_chars="+-*/%&|^!~<>=?@",
    ),
  )
}

///|
pub fn php_language() -> Language {
  generic_language(
    lang_config(
      "php",
      keywords=[
        "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class",
        "clone", "const", "continue", "declare", "default", "do", "echo", "else",
        "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch",
        "endwhile", "enum", "extends", "final", "finally", "fn", "for", "foreach",
        "function", "global", "goto", "if", "implements", "include", "include_once",
        "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace",
        "new", "or", "print", "private", "protected", "public", "readonly", "require",
        "require_once", "return", "static", "switch", "throw", "trait", "try", "unset",
        "use", "var", "while", "xor", "yield",
      ],
      types=[
        "bool", "int", "float", "string", "mixed", "void", "never", "object", "iterable",
        "self", "parent",
      ],
      line_comments=["//", "#"],
      block_comments=[("/*", "*/")],
      quotes=["\"", "'"],
      multiline_quotes=true,
      dollar_vars=true,
      number_suffix_chars="",
      operator_chars="+-*/%&|^!~<>=?:@\\",
    ),
  )
}

///|
pub fn swift_language() -> Language {
  generic_language(
    lang_config(
      "swift",
      keywords=[
        "actor", "as", "associatedtype", "async", "await", "break", "case", "catch",
        "class", "continue", "default", "defer", "deinit", "do", "else", "enum",
        "extension", "fallthrough", "fileprivate", "for", "func", "guard", "if",
        "import", "in", "init", "inout", "internal", "is", "let", "nonisolated",
        "open", "operator", "private", "protocol", "public", "repeat", "rethrows",
        "return", "some", "static", "struct", "subscript", "switch", "throw", "throws",
        "try", "typealias", "var", "where", "while",
      ],
      types=[
        "Any", "AnyObject", "Array", "Bool", "Character", "Dictionary", "Double",
        "Error", "Float", "Int", "Int8", "Int16", "Int32", "Int64", "Never", "Optional",
        "Set", "String", "Substring", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Void",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      nested_comments=true,
      quotes=["\""],
      triples=["\"\"\""],
      dollar_vars=true,
      at_decorators=true,
      operator_chars="+-*/%&|^!~<>=?",
    ),
  )
}

///|
pub fn kotlin_language() -> Language {
  generic_language(
    lang_config(
      "kotlin",
      keywords=[
        "abstract", "actual", "annotation", "as", "break", "by", "catch", "class",
        "companion", "const", "constructor", "continue", "crossinline", "data", "delegate",
        "do", "dynamic", "else", "enum", "expect", "external", "field", "file", "final",
        "finally", "for", "fun", "get", "if", "import", "in", "infix", "init", "inline",
        "inner", "interface", "internal", "is", "lateinit", "noinline", "object",
        "open", "operator", "out", "override", "package", "param", "private", "property",
        "protected", "public", "receiver", "reified", "return", "sealed", "set",
        "setparam", "suspend", "tailrec", "this", "throw", "try", "typealias", "typeof",
        "val", "var", "vararg", "when", "where", "while",
      ],
      types=[
        "Any", "Boolean", "Byte", "Char", "Double", "Float", "Int", "Long", "Nothing",
        "Short", "String", "Unit", "List", "Map", "Set",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      nested_comments=true,
      quotes=["\""],
      triples=["\"\"\""],
      char_literals=true,
      dollar_vars=true,
      at_decorators=true,
      number_suffix_chars="fFLuU",
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn scala_language() -> Language {
  generic_language(
    lang_config(
      "scala",
      keywords=[
        "abstract", "case", "catch", "class", "def", "do", "else", "enum", "export",
        "extends", "final", "finally", "for", "forSome", "given", "if", "implicit",
        "import", "lazy", "match", "new", "object", "override", "package", "private",
        "protected", "return", "sealed", "super", "then", "this", "throw", "trait",
        "try", "type", "using", "val", "var", "while", "with", "yield",
      ],
      types=[
        "Any", "AnyRef", "Boolean", "Byte", "Char", "Double", "Float", "Int", "List",
        "Long", "Map", "Option", "Seq", "Set", "Short", "String", "Unit",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      nested_comments=true,
      quotes=["\""],
      triples=["\"\"\""],
      char_literals=true,
      at_decorators=true,
      number_suffix_chars="fFdDlL",
      operator_chars="+-*/%&|^!~<>=?:@",
    ),
  )
}

///|
pub fn dart_language() -> Language {
  generic_language(
    lang_config(
      "dart",
      keywords=[
        "abstract", "as", "assert", "async", "await", "break", "case", "catch", "class",
        "const", "continue", "covariant", "default", "deferred", "do", "dynamic",
        "else", "enum", "export", "extends", "extension", "external", "factory",
        "final", "finally", "for", "Function", "get", "hide", "if", "implements",
        "import", "in", "interface", "is", "late", "library", "mixin", "new", "on",
        "operator", "part", "required", "rethrow", "return", "set", "show", "static",
        "super", "switch", "sync", "this", "throw", "try", "typedef", "var", "void",
        "while", "with", "yield",
      ],
      types=[
        "bool", "double", "int", "num", "String", "Object", "List", "Map", "Set",
        "Future", "Stream",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      nested_comments=true,
      quotes=["\"", "'"],
      triples=["\"\"\"", "'''"],
      string_prefixes=["r"],
      dollar_vars=true,
      at_decorators=true,
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn groovy_language() -> Language {
  generic_language(
    lang_config(
      "groovy",
      keywords=[
        "abstract", "as", "assert", "break", "case", "catch", "class", "const", "continue",
        "def", "default", "do", "else", "enum", "extends", "final", "finally", "for",
        "goto", "if", "implements", "import", "in", "instanceof", "interface", "new",
        "package", "return", "static", "super", "switch", "this", "throw", "throws",
        "trait", "try", "var", "while",
      ],
      types=[
        "boolean", "byte", "char", "double", "float", "int", "long", "short", "void",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\"", "'"],
      triples=["\"\"\"", "'''"],
      dollar_vars=true,
      at_decorators=true,
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn solidity_language() -> Language {
  generic_language(
    lang_config(
      "solidity",
      keywords=[
        "abstract", "after", "alias", "apply", "as", "assembly", "break", "case",
        "catch", "constant", "constructor", "continue", "contract", "default", "delete",
        "do", "else", "emit", "enum", "error", "event", "external", "fallback", "for",
        "function", "if", "immutable", "import", "indexed", "interface", "internal",
        "is", "library", "mapping", "memory", "modifier", "new", "override", "payable",
        "pragma", "private", "public", "pure", "receive", "require", "return", "returns",
        "revert", "storage", "struct", "super", "this", "throw", "try", "type", "unchecked",
        "using", "view", "virtual", "while",
      ],
      types=[
        "address", "bool", "byte", "bytes", "bytes32", "int", "int256", "string",
        "uint", "uint256",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\"", "'"],
      capitalized_types=true,
      operator_chars="+-*/%&|^!~<>=?",
    ),
  )
}

///|
pub fn protobuf_language() -> Language {
  generic_language(
    lang_config(
      "protobuf",
      keywords=[
        "syntax", "package", "import", "option", "message", "enum", "service", "rpc",
        "returns", "repeated", "optional", "required", "oneof", "map", "reserved",
        "extend", "extensions", "to", "max", "stream", "group",
      ],
      types=[
        "double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64",
        "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string", "bytes",
      ],
      line_comments=["//"],
      block_comments=[("/*", "*/")],
      quotes=["\"", "'"],
      capitalized_types=true,
      operator_chars="+-*/%&|^!~<>=?",
    ),
  )
}

///|
pub fn graphql_language() -> Language {
  generic_language(
    lang_config(
      "graphql",
      keywords=[
        "query", "mutation", "subscription", "fragment", "on", "type", "schema",
        "scalar", "interface", "union", "enum", "input", "extend", "directive", "implements",
        "repeatable",
      ],
      atoms=["true", "false", "null"],
      line_comments=["#"],
      quotes=["\""],
      triples=["\"\"\""],
      dollar_vars=true,
      at_decorators=true,
      punct_chars="{}()[],:",
      operator_chars="!|&=@$.",
    ),
  )
}

///|
pub fn hcl_language() -> Language {
  generic_language(
    lang_config(
      "hcl",
      keywords=[
        "resource", "data", "variable", "output", "module", "provider", "terraform",
        "locals", "backend", "provisioner", "connection", "dynamic", "for", "in",
        "if", "else",
      ],
      types=[
        "string", "number", "bool", "list", "map", "set", "object", "tuple", "any",
      ],
      atoms=["true", "false", "null"],
      line_comments=["#", "//"],
      block_comments=[("/*", "*/")],
      quotes=["\""],
      property_before=[61],
      dollar_vars=true,
      operator_chars="+-*/%&|^!~<>=?:",
    ),
  )
}

///|
pub fn nix_language() -> Language {
  generic_language(
    lang_config(
      "nix",
      keywords=[
        "let", "in", "with", "rec", "inherit", "if", "then", "else", "assert", "or",
        "import", "builtins",
      ],
      atoms=["true", "false", "null"],
      line_comments=["#"],
      block_comments=[("/*", "*/")],
      quotes=["\"", "''"],
      multiline_quotes=true,
      dollar_vars=true,
      punct_chars="{}()[];,:.@",
      operator_chars="=+-*/!<>?|&",
    ),
  )
}
