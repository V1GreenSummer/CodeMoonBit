///|
fn tok_has(tokens : Array[Token], typ : TokenType) -> Bool {
  let mut found = false
  for t in tokens {
    if t.typ == typ {
      found = true
    }
  }
  found
}

///|
/// Tokenizes `snippet` with the named language and checks that every required
/// token type appears. Aborts with the offending language/snippet otherwise.
fn check_lang(
  name : String,
  snippet : String,
  required : Array[TokenType],
) -> Unit {
  let lang = language_by_name(name)
  let (tokens, _) = lang.tokenize(snippet, 0)
  for typ in required {
    if !tok_has(tokens, typ) {
      abort("missing token type in " + name + ": " + snippet)
    }
  }
}

///|
test "c-like family token classes" {
  check_lang("c", "int main(void) { return \"x\"; } // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("cpp", "class A { public: string s = \"x\"; }; // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("java", "@Override public class A { String s = \"x\"; } // c", [
    Keyword,
    TypeName,
    String,
    Comment,
    Attribute,
  ])
  check_lang("csharp", "public class A { string s = @\"x\"; } // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("go", "func main() { var s string = \"x\" } // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("rust", "fn main() { let s = r#\"x\"#; } // c", [
    Keyword,
    String,
    Comment,
  ])
  check_lang("typescript", "let s: string = \"x\"; // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("javascript", "const s = \"x\"; // c", [Keyword, String, Comment])
  check_lang("php", "function f() { $s = \"x\"; } // c", [
    Keyword,
    VariableName,
    String,
    Comment,
  ])
  check_lang("swift", "let s: String = \"x\" // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("kotlin", "val s: String = \"x\" // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("scala", "def f(): String = \"x\" // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("dart", "int main() { var s = \"x\"; } // c", [
    Keyword,
    TypeName,
    String,
    Comment,
  ])
  check_lang("groovy", "def f() { def s = \"x\" } // c", [
    Keyword,
    String,
    Comment,
  ])
  check_lang(
    "solidity",
    "pragma solidity ^0.8.0; contract A { function f() public { string memory s = \"x\"; } } // c",
    [Keyword, TypeName, String, Comment],
  )
  check_lang(
    "protobuf",
    "syntax = \"proto3\"; message A { string s = 1; } // c",
    [Keyword, TypeName, String, Comment],
  )
  check_lang("graphql", "query Q { a(s: \"x\") } # c", [
    Keyword,
    String,
    Comment,
  ])
  check_lang("hcl", "resource \"aws_instance\" \"x\" { count = 1 } # c", [
    Keyword,
    String,
    Comment,
    PropertyName,
  ])
  check_lang("nix", "let x = \"y\"; in x # c", [Keyword, String, Comment])
  check_lang("diff", "@@ -1 +1 @@", [Meta])
  check_lang("diff", "+added text", [Operator, VariableName])
}

///|
test "scripting family token classes" {
  check_lang("python", "def f(x): return \"s\"  # c", [Keyword, String, Comment])
  check_lang("ruby", "def f(x) \"s\" end # c", [Keyword, String, Comment])
  check_lang("perl", "my $x = \"s\"; # c", [
    Keyword,
    VariableName,
    String,
    Comment,
  ])
  check_lang("lua", "local x = \"s\" -- c", [Keyword, String, Comment])
  check_lang("r", "if (TRUE) x <- \"s\" # c", [Keyword, Atom, String, Comment])
  check_lang("julia", "function f() \"s\" end # c", [Keyword, String, Comment])
  check_lang("elixir", "defmodule A do \"s\" end # c", [
    Keyword,
    String,
    Comment,
  ])
  check_lang("erlang", "case X of ok -> \"s\" end. % c", [
    Keyword,
    String,
    Comment,
  ])
  check_lang("haskell", "let x = \"s\" -- c", [Keyword, String, Comment])
  check_lang("ocaml", "let x = \"s\" (* c *)", [Keyword, String, Comment])
  check_lang("clojure", "(def x \"s\") ; c", [Keyword, String, Comment])
  check_lang("lisp", "(define x \"s\") ; c", [Keyword, String, Comment])
}

///|
test "shell and build family token classes" {
  check_lang("shell", "if [ -f \"$x\" ]; then echo \"s\"; fi # c", [
    Keyword,
    String,
    Comment,
  ])
  check_lang("powershell", "function F { $x = \"s\" } # c", [
    Keyword,
    VariableName,
    String,
    Comment,
  ])
  check_lang("makefile", "all: main.o \"s\" # c", [Meta, String, Comment])
  check_lang("makefile", "VAR := value", [PropertyName, Operator])
  check_lang("dockerfile", "FROM alpine # c", [Keyword, Comment])
  check_lang("dockerfile", "RUN echo \"s\"", [Keyword, String])
}

///|
test "data and config family token classes" {
  check_lang("yaml", "key: \"s\" # c", [PropertyName, String, Comment])
  check_lang("yaml", "---", [Meta])
  check_lang("toml", "name = \"s\" # c", [PropertyName, String, Comment])
  check_lang("toml", "[server]", [Keyword])
  check_lang("ini", "key = \"s\" ; c", [PropertyName, String, Comment])
  check_lang("ini", "[main]", [Keyword])
  check_lang("sql", "SELECT name FROM t WHERE x = 's'; -- c", [
    Keyword,
    String,
    Comment,
  ])
  check_lang("latex", "\\section{Intro} $x$ % c", [Keyword, String, Comment])
}

///|
test "web family token classes" {
  check_lang("html", "<div class=\"a\">hi</div> <!-- c -->", [
    Tag,
    Attribute,
    String,
    Comment,
  ])
  check_lang("xml", "<note id=\"1\">x</note><!-- c -->", [
    Tag,
    Attribute,
    String,
    Comment,
  ])
  check_lang("vue", "<template><p v-if=\"ok\">hi</p></template>", [
    Tag,
    Attribute,
    String,
  ])
  check_lang("css", "@media screen { color: red; content: \"x\"; } /* c */", [
    Keyword,
    PropertyName,
    String,
    Comment,
  ])
  check_lang("scss", "$c: \"x\" !important; // c", [
    VariableName,
    String,
    Comment,
    Keyword,
  ])
  check_lang("less", "@base: \"x\"; // c", [Keyword, String, Comment])
}

///|
test "generic config knobs" {
  check_lang("c", "#include <stdio.h>", [Meta])
  check_lang("c", "char c = 'x';", [TypeName, String])
  check_lang("cpp", "auto s = R\"(raw)\";", [Keyword, String])
  check_lang("rust", "#[derive(Debug)] struct S;", [Attribute, Keyword])
  check_lang("python", "@staticmethod", [Attribute])
  check_lang("php", "# hash comment", [Comment])
  check_lang("sql", "SELECT '' FROM t", [Keyword, String])
  check_lang("nix", "x = ''raw'';", [String])
  check_lang("erlang", "% percent", [Comment])
  check_lang("lua", "local x = [[raw]]", [Keyword])
  check_lang("powershell", "Get-ChildItem -Path .", [Keyword, VariableName])
  check_lang("python", "r\"\\d+\"", [String])
  check_lang("python", "f\"{x}\"", [String])
}

///|
test "rust nested comments and raw string state" {
  let lang = language_by_name("rust")
  let (first, state) = lang.tokenize("/* outer", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (second, state2) = lang.tokenize("/* inner */ still", state)
  assert_true(state2 != 0)
  assert_eq(second[0].typ, Comment)
  let (third, state3) = lang.tokenize("done */ let x", state2)
  assert_eq(state3, 0)
  assert_eq(third[0].typ, Comment)
  assert_eq(third[1].typ, Keyword)
  let (raw1, raw_state) = lang.tokenize("let s = r#\"first", 0)
  assert_true(raw_state != 0)
  assert_eq(raw1[raw1.length() - 1].typ, String)
  let (raw2, raw_state2) = lang.tokenize("second\"#;", raw_state)
  assert_eq(raw_state2, 0)
  assert_eq(raw2[0].typ, String)
  assert_eq(raw2[0].to, 8)
}

///|
test "ocaml nested comment state" {
  let lang = language_by_name("ocaml")
  let (first, state) = lang.tokenize("(* outer", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (second, state2) = lang.tokenize("(* inner *)", state)
  assert_true(state2 != 0)
  assert_eq(second[0].typ, Comment)
  let (third, state3) = lang.tokenize("done *) let x", state2)
  assert_eq(state3, 0)
  assert_eq(third[0].typ, Comment)
  assert_eq(third[0].to, 7)
  assert_eq(third[1].typ, Keyword)
}

///|
test "tokens stay in bounds and never split surrogates" {
  let samples = [
    ("c", "int x = 1; /* c */"),
    ("python", "x = \"🤣\"  # c"),
    ("html", "<p a=\"🤣\">text</p><!-- c -->"),
    ("javascript", "const s = `a${x}b`; // c"),
    ("yaml", "k: \"v\" # c"),
    ("shell", "echo \"$HOME\" # c"),
    ("rust", "let s = r#\"a\"#; // c"),
    ("haskell", "x = \"🤣\" -- c"),
  ]
  for sample in samples {
    let (name, line) = sample
    let lang = language_by_name(name)
    let (tokens, _) = lang.tokenize(line, 0)
    let mut prev = 0
    for t in tokens {
      assert_true(t.from >= prev)
      assert_true(t.to > t.from)
      assert_true(t.to <= line.length())
      if t.from > 0 {
        let before = line.unsafe_get(t.from - 1).to_int()
        let at = line.unsafe_get(t.from).to_int()
        assert_true(
          !(before >= 0xD800 && before <= 0xDBFF && at >= 0xDC00 && at <= 0xDFFF),
        )
      }
      if t.to < line.length() {
        let before = line.unsafe_get(t.to - 1).to_int()
        let at = line.unsafe_get(t.to).to_int()
        assert_true(
          !(before >= 0xD800 && before <= 0xDBFF && at >= 0xDC00 && at <= 0xDFFF),
        )
      }
      prev = t.to
    }
  }
}

///|
test "python triple string state" {
  let lang = language_by_name("python")
  let (first, state) = lang.tokenize("\"\"\"doc", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, String)
  let (second, state2) = lang.tokenize("more\"\"\" x = 1", state)
  assert_eq(state2, 0)
  assert_eq(second[0].typ, String)
  assert_eq(second[0].from, 0)
  assert_eq(second[0].to, 7)
}

///|
test "c block comment state" {
  let lang = language_by_name("c")
  let (first, state) = lang.tokenize("/* open", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (second, state2) = lang.tokenize("still */ int x", state)
  assert_eq(state2, 0)
  assert_eq(second[0].typ, Comment)
  assert_eq(second[0].to, 8)
  assert_eq(second[1].typ, TypeName)
}

///|
test "haskell nested comment state" {
  let lang = language_by_name("haskell")
  let (first, state) = lang.tokenize("{- outer", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (second, state2) = lang.tokenize("  {- inner -}", state)
  assert_true(state2 != 0)
  assert_eq(second[0].typ, Comment)
  let (third, state3) = lang.tokenize("still -} let x", state2)
  assert_eq(state3, 0)
  assert_eq(third[0].typ, Comment)
  assert_eq(third[0].to, 8)
  assert_eq(third[1].typ, Keyword)
}

///|
test "html comment state" {
  let lang = language_by_name("html")
  let (first, state) = lang.tokenize("<!-- open", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (second, state2) = lang.tokenize("close --> <p>", state)
  assert_eq(state2, 0)
  assert_eq(second[0].typ, Comment)
  assert_eq(second[0].to, 9)
  assert_true(tok_has(second, Tag))
}

///|
test "lua block comment state" {
  let lang = language_by_name("lua")
  let (first, state) = lang.tokenize("--[[ open", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (second, state2) = lang.tokenize("still ]] local x", state)
  assert_eq(state2, 0)
  assert_eq(second[0].typ, Comment)
  assert_eq(second[1].typ, Keyword)
}

///|
test "powershell block comment state" {
  let lang = language_by_name("powershell")
  let (first, state) = lang.tokenize("<# open", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (second, state2) = lang.tokenize("still #> $x", state)
  assert_eq(state2, 0)
  assert_eq(second[0].typ, Comment)
  assert_eq(second[1].typ, VariableName)
}

///|
test "ruby =begin state" {
  let lang = language_by_name("ruby")
  let (first, state) = lang.tokenize("=begin", 0)
  assert_true(state != 0)
  assert_eq(first[0].typ, Comment)
  let (_, state2) = lang.tokenize("inside docs", state)
  assert_true(state2 != 0)
  let (third, state3) = lang.tokenize("=end", state2)
  assert_eq(state3, 0)
  assert_eq(third[0].typ, Comment)
}

///|
test "javascript generic compatibility" {
  let lang = language_by_name("js")
  let (tokens, state) = lang.tokenize("const x = /ab+c/gi; // c", 0)
  assert_eq(state, 0)
  assert_eq(tokens.length(), 6)
  assert_eq(tokens[3].typ, String)
  assert_eq(tokens[3].from, 10)
  assert_eq(tokens[3].to, 18)
  let (template, template_state) = lang.tokenize("`abc", 0)
  assert_eq(template_state, 2)
  assert_eq(template[0].typ, String)
  let (rest, rest_state) = lang.tokenize("def` + 1", template_state)
  assert_eq(rest_state, 0)
  assert_eq(rest[0].typ, String)
  assert_eq(rest[0].to, 4)
  let (klass, _) = lang.tokenize("new Promise(fn)", 0)
  assert_eq(klass[1].typ, TypeName)
  let (comment, comment_state) = lang.tokenize("/* partial", 0)
  assert_eq(comment_state, 1)
  assert_eq(comment[0].typ, Comment)
  let (closed, closed_state) = lang.tokenize("done */ x", comment_state)
  assert_eq(closed_state, 0)
  assert_eq(closed[0].typ, Comment)
  assert_eq(closed[0].to, 7)
}

///|
test "language names and aliases" {
  let names = language_names()
  assert_true(names.length() >= 45)
  for
    wanted in [
      "c", "clojure", "css", "diff", "go", "haskell", "html", "javascript", "json",
      "markdown", "moonbit", "python", "rust", "shell", "typescript", "yaml",
    ] {
    assert_true(names.contains(wanted))
  }
  let mut i = 1
  while i < names.length() {
    assert_true(names[i - 1].compare(names[i]) <= 0)
    i = i + 1
  }
  for name in names {
    assert_eq(language_by_name(name).name(), name)
  }
  assert_eq(language_by_name("py").name(), "python")
  assert_eq(language_by_name("js").name(), "javascript")
  assert_eq(language_by_name("yml").name(), "yaml")
  assert_eq(language_by_name("sh").name(), "shell")
  assert_eq(language_by_name("rs").name(), "rust")
  assert_eq(language_by_name("kt").name(), "kotlin")
  assert_eq(language_by_name("tf").name(), "hcl")
  assert_eq(language_by_name("md").name(), "markdown")
  assert_eq(language_by_name("html").name(), "html")
  assert_eq(language_by_name("c++").name(), "cpp")
  assert_eq(language_by_name("C++").name(), "cpp")
  assert_eq(language_by_name("unknown-language").name(), "plain")
}
