///|
/// Canonical language names, sorted alphabetically. Kept in sync with the
/// registry by `language_names()`.
fn canonical_language_names() -> Array[String] {
  let names = [
    "c", "clojure", "cpp", "csharp", "css", "dart", "diff", "dockerfile", "elixir",
    "erlang", "go", "graphql", "groovy", "haskell", "hcl", "html", "ini", "java",
    "javascript", "json", "julia", "kotlin", "latex", "less", "lisp", "lua", "makefile",
    "markdown", "moonbit", "nix", "ocaml", "perl", "php", "plain", "powershell",
    "protobuf", "python", "r", "ruby", "rust", "scala", "scss", "shell", "solidity",
    "sql", "swift", "toml", "typescript", "vue", "xml", "yaml",
  ]
  names.sort()
  names
}

///|
let canonical_names : Array[String] = canonical_language_names()

///|
/// Builds the name/alias table once at module initialization. Every language
/// config builds its own lookup structures at construction; tokenizing never
/// allocates them again.
fn build_registry() -> Map[String, Language] {
  let m : Map[String, Language] = Map([])
  let add = fn(names : Array[String], lang : Language) {
    for n in names {
      m.set(n, lang)
    }
  }
  add(["plain", "text", "txt"], plain_language())
  add(["moonbit", "mbt"], moonbit_language())
  add(["json"], json_language())
  add(["markdown", "md", "mdown"], markdown_language())
  add(["javascript", "js", "mjs", "cjs"], javascript_language())
  add(["typescript", "ts", "tsx"], typescript_language())
  add(["c", "h"], c_language())
  add(["cpp", "cc", "cxx", "hpp", "c++"], cpp_language())
  add(["java"], java_language())
  add(["csharp", "cs", "c#"], csharp_language())
  add(["go", "golang"], go_language())
  add(["rust", "rs"], rust_language())
  add(["php"], php_language())
  add(["swift"], swift_language())
  add(["kotlin", "kt", "kts"], kotlin_language())
  add(["scala"], scala_language())
  add(["dart"], dart_language())
  add(["groovy", "gradle"], groovy_language())
  add(["solidity", "sol"], solidity_language())
  add(["protobuf", "proto"], protobuf_language())
  add(["graphql", "gql"], graphql_language())
  add(["hcl", "tf", "terraform"], hcl_language())
  add(["nix"], nix_language())
  add(["diff", "patch"], diff_language())
  add(["python", "py", "python3"], python_language())
  add(["ruby", "rb"], ruby_language())
  add(["perl", "pl", "pm"], perl_language())
  add(["lua"], lua_language())
  add(["r"], r_language())
  add(["julia", "jl"], julia_language())
  add(["elixir", "ex", "exs"], elixir_language())
  add(["erlang", "erl"], erlang_language())
  add(["haskell", "hs"], haskell_language())
  add(["ocaml", "ml", "mli", "sml"], ocaml_language())
  add(["clojure", "clj", "cljs", "cljc", "edn"], clojure_language())
  add(["lisp", "el", "scm", "scheme"], lisp_language())
  add(["shell", "sh", "bash", "zsh", "ksh"], shell_language())
  add(["powershell", "ps1", "pwsh"], powershell_language())
  add(["makefile", "mk", "make", "gmake"], makefile_language())
  add(["dockerfile", "docker"], dockerfile_language())
  add(["yaml", "yml"], yaml_language())
  add(["toml"], toml_language())
  add(["ini", "cfg", "conf"], ini_language())
  add(["xml"], xml_language())
  add(["sql"], sql_language())
  add(["latex", "tex"], latex_language())
  add(["html", "htm", "svg"], html_language())
  add(["css"], css_language())
  add(["scss"], scss_language())
  add(["less"], less_language())
  add(["vue"], vue_language())
  m
}

///|
let registry : Map[String, Language] = build_registry()

///|
/// Looks up a language by canonical name or alias, case-insensitively.
/// Unknown names fall back to `plain`.
pub fn language_by_name(name : String) -> Language {
  match registry.get(name.to_lower()) {
    Some(lang) => lang
    None => plain_language()
  }
}

///|
/// The canonical registered language names, sorted alphabetically.
pub fn language_names() -> Array[String] {
  canonical_names.copy()
}
