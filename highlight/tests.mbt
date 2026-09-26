///|
test "token type constructors" {
  let all : Array[TokenType] = [
    Keyword,
    TypeName,
    VariableName,
    PropertyName,
    Atom,
    Number,
    String,
    Comment,
    Operator,
    Punctuation,
    Meta,
    Tag,
    Attribute,
    Invalid,
  ]
  assert_eq(all.length(), 14)
}

///|
test "json token classification" {
  let lang = json_language()
  let (tokens, state) = lang.tokenize(
    "{\"key\": true, \"n\": -1.2e3, \"s\": \"a\\\"b\"}", 0,
  )
  assert_eq(state, 0)
  let expected = [
    Token::{ from: 0, to: 1, typ: Punctuation, },
    Token::{ from: 1, to: 6, typ: PropertyName, },
    Token::{ from: 6, to: 7, typ: Punctuation, },
    Token::{ from: 8, to: 12, typ: Atom, },
    Token::{ from: 12, to: 13, typ: Punctuation, },
    Token::{ from: 14, to: 17, typ: PropertyName, },
    Token::{ from: 17, to: 18, typ: Punctuation, },
    Token::{ from: 19, to: 25, typ: Number, },
    Token::{ from: 25, to: 26, typ: Punctuation, },
    Token::{ from: 27, to: 30, typ: PropertyName, },
    Token::{ from: 30, to: 31, typ: Punctuation, },
    Token::{ from: 32, to: 38, typ: String, },
    Token::{ from: 38, to: 39, typ: Punctuation, },
  ]
  assert_eq(tokens, expected)
}

///|
test "json atoms and invalid garbage" {
  let lang = json_language()
  let (tokens, state) = lang.tokenize("true false null @@@", 0)
  assert_eq(state, 0)
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0].typ, Atom)
  assert_eq(tokens[1].typ, Atom)
  assert_eq(tokens[2].typ, Atom)
  assert_eq(tokens[3].typ, Invalid)
  assert_eq(tokens[3].from, 16)
  assert_eq(tokens[3].to, 19)
}

///|
test "json unterminated string spans lines" {
  let lang = json_language()
  let (tokens, state) = lang.tokenize("\"abc", 0)
  assert_eq(state, 1)
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0].typ, String)
  assert_eq(tokens[0].from, 0)
  assert_eq(tokens[0].to, 4)
  let (tokens2, state2) = lang.tokenize("def\", \"x\": 1", 1)
  assert_eq(state2, 0)
  assert_eq(tokens2[0].typ, String)
  assert_eq(tokens2[0].to, 4)
  assert_eq(tokens2[1].typ, Punctuation)
  assert_eq(tokens2[2].typ, PropertyName)
  assert_eq(tokens2[2].from, 6)
  assert_eq(tokens2[2].to, 9)
  assert_eq(tokens2[3].typ, Punctuation)
  assert_eq(tokens2[4].typ, Number)
}

///|
test "moonbit nested block comment spans lines" {
  let lang = moonbit_language()
  let (tokens0, state0) = lang.tokenize("/* outer", 0)
  assert_eq(state0, 1)
  assert_eq(tokens0.length(), 1)
  assert_eq(tokens0[0].typ, Comment)
  let (tokens1, state1) = lang.tokenize("  /* inner */", 1)
  assert_eq(state1, 1)
  assert_eq(tokens1.length(), 1)
  assert_eq(tokens1[0].typ, Comment)
  assert_eq(tokens1[0].from, 0)
  assert_eq(tokens1[0].to, 13)
  let (tokens2, state2) = lang.tokenize("still */ let x = 1", 1)
  assert_eq(state2, 0)
  assert_eq(tokens2[0].typ, Comment)
  assert_eq(tokens2[0].from, 0)
  assert_eq(tokens2[0].to, 8)
  assert_eq(tokens2[1].typ, Keyword)
  assert_eq(tokens2[2].typ, VariableName)
  assert_eq(tokens2[3].typ, Operator)
  assert_eq(tokens2[4].typ, Number)
}

///|
test "moonbit keywords types numbers and chars" {
  let lang = moonbit_language()
  let (tokens, state) = lang.tokenize(
    "pub fn add(x: Int) -> Int { x + 0xFF }", 0,
  )
  assert_eq(state, 0)
  assert_eq(tokens.length(), 15)
  assert_eq(tokens[0].typ, Keyword)
  assert_eq(tokens[1].typ, Keyword)
  assert_eq(tokens[2].typ, VariableName)
  assert_eq(tokens[6].typ, TypeName)
  assert_eq(tokens[8].typ, Operator)
  assert_eq(tokens[8].from, 19)
  assert_eq(tokens[8].to, 21)
  assert_eq(tokens[13].typ, Number)
  assert_eq(tokens[13].from, 32)
  assert_eq(tokens[13].to, 36)
  let (comments, _) = lang.tokenize("// note", 0)
  assert_eq(comments.length(), 1)
  assert_eq(comments[0].typ, Comment)
  let (quoted, _) = lang.tokenize("\"🤣\"", 0)
  assert_eq(quoted.length(), 1)
  assert_eq(quoted[0].typ, String)
  assert_eq(quoted[0].from, 0)
  assert_eq(quoted[0].to, 4)
  let (triple, _) = lang.tokenize("\"\"\"raw", 0)
  assert_eq(triple.length(), 1)
  assert_eq(triple[0].typ, String)
}

///|
test "markdown fence state and heading" {
  let lang = markdown_language()
  let (tokens0, state0) = lang.tokenize("```moonbit", 0)
  assert_eq(state0, 1)
  assert_eq(tokens0.length(), 2)
  assert_eq(tokens0[0].typ, Meta)
  assert_eq(tokens0[0].from, 0)
  assert_eq(tokens0[0].to, 3)
  assert_eq(tokens0[1].typ, VariableName)
  let (tokens1, state1) = lang.tokenize("let x = 1", 1)
  assert_eq(state1, 1)
  assert_eq(tokens1.length(), 1)
  assert_eq(tokens1[0].typ, Comment)
  assert_eq(tokens1[0].to, 9)
  let (tokens2, state2) = lang.tokenize("```", 1)
  assert_eq(state2, 0)
  assert_eq(tokens2.length(), 1)
  assert_eq(tokens2[0].typ, Meta)
  let (heading, state3) = lang.tokenize("# Title", 0)
  assert_eq(state3, 0)
  assert_eq(heading.length(), 2)
  assert_eq(heading[0].typ, Punctuation)
  assert_eq(heading[0].to, 1)
  assert_eq(heading[1].typ, Keyword)
  assert_eq(heading[1].from, 2)
  assert_eq(heading[1].to, 7)
  let (tilde, tilde_state) = lang.tokenize("~~~", 0)
  assert_eq(tilde_state, 2)
  assert_eq(tilde[0].typ, Meta)
  let (code, code_state) = lang.tokenize("anything", 2)
  assert_eq(code_state, 2)
  assert_eq(code[0].typ, Comment)
}

///|
test "markdown links emphasis and code spans" {
  let lang = markdown_language()
  let (tokens, _) = lang.tokenize("a [text](url) `code` **bold**", 0)
  let types = tokens.map(fn(t) { t.typ })
  assert_true(types.contains(String))
  assert_true(types.contains(Comment))
  assert_true(types.contains(Keyword))
  assert_true(types.contains(Punctuation))
}

///|
test "javascript regex heuristic contexts" {
  let lang = javascript_language()
  let (after_return, _) = lang.tokenize("return /x/g", 0)
  assert_eq(after_return[0].typ, Keyword)
  assert_eq(after_return[1].typ, String)
  assert_eq(after_return[1].from, 7)
  assert_eq(after_return[1].to, 11)
  let (after_paren, _) = lang.tokenize("f(/x/)", 0)
  assert_eq(after_paren[2].typ, String)
  let (after_comma, _) = lang.tokenize("a, /x/", 0)
  assert_eq(after_comma[2].typ, String)
  let (after_eq, _) = lang.tokenize("x = /y/", 0)
  assert_eq(after_eq[2].typ, String)
}

///|
test "moonbit radix and float numbers" {
  let lang = moonbit_language()
  let (tokens, _) = lang.tokenize("0xFF 0b1010 0o17 1_000.5e-2", 0)
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0].typ, Number)
  assert_eq(tokens[0].to, 4)
  assert_eq(tokens[1].typ, Number)
  assert_eq(tokens[1].to, 11)
  assert_eq(tokens[2].typ, Number)
  assert_eq(tokens[2].to, 16)
  assert_eq(tokens[3].typ, Number)
  assert_eq(tokens[3].from, 17)
  assert_eq(tokens[3].to, 27)
}

///|
test "markdown block constructs" {
  let lang = markdown_language()
  let (quote, _) = lang.tokenize("> quoted", 0)
  assert_eq(quote[0].typ, Punctuation)
  assert_eq(quote[0].to, 1)
  let (item, _) = lang.tokenize("- item", 0)
  assert_eq(item[0].typ, Punctuation)
  assert_eq(item[0].to, 1)
  let (hr, _) = lang.tokenize("---", 0)
  assert_eq(hr[0].typ, Meta)
  assert_eq(hr[0].to, 3)
  let (link, _) = lang.tokenize("[text](url)", 0)
  assert_eq(link.length(), 6)
  assert_eq(link[0].typ, Punctuation)
  assert_eq(link[1].typ, String)
  assert_eq(link[1].from, 1)
  assert_eq(link[1].to, 5)
  assert_eq(link[3].typ, Punctuation)
  assert_eq(link[4].typ, String)
  assert_eq(link[4].from, 7)
  assert_eq(link[4].to, 10)
  assert_eq(link[5].typ, Punctuation)
}

///|
test "highlight cache uses previous line state" {
  let doc = @core.Text::of("/*\ncode */ let x")
  let cache = HighlightCache::new(moonbit_language())
  let line1 = cache.tokens_for_line(doc, 1)
  assert_eq(line1[0].typ, Comment)
  assert_eq(line1[0].from, 0)
  assert_eq(line1[0].to, 7)
  assert_eq(line1[1].typ, Keyword)
  assert_true(cache.lines[0] is Some(_))
  assert_eq(cache.states[0], Some(0))
  assert_eq(cache.states[1], Some(1))
  assert_eq(cache.states[2], Some(0))
}

///|
test "highlight cache invalidate recomputes" {
  let doc = @core.Text::of("/*\ncode */ let x")
  let cache = HighlightCache::new(moonbit_language())
  let before = cache.tokens_for_line(doc, 1)
  assert_true(cache.lines[1] is Some(_))
  cache.invalidate(0)
  assert_true(cache.lines[0] is None)
  assert_true(cache.lines[1] is None)
  assert_true(cache.states[0] is None)
  assert_true(cache.states[1] is None)
  let after = cache.tokens_for_line(doc, 1)
  assert_eq(after, before)
  cache.invalidate(1)
  assert_true(cache.lines[0] is Some(_))
  let again = cache.tokens_for_line(doc, 1)
  assert_eq(again, before)
}

///|
test "highlight cache caches empty token lines" {
  let doc = @core.Text::of("   \n\"a\": 1")
  let cache = HighlightCache::new(json_language())
  let empty = cache.tokens_for_line(doc, 0)
  assert_eq(empty.length(), 0)
  assert_true(cache.lines[0] is Some(_))
  assert_eq(cache.states[0], Some(0))
  let second = cache.tokens_for_line(doc, 1)
  assert_eq(second[0].typ, PropertyName)
}

///|
test "highlight cache clamps line index" {
  let doc = @core.Text::of("let a = 1")
  let cache = HighlightCache::new(moonbit_language())
  let last = cache.tokens_for_line(doc, 99)
  assert_eq(last[0].typ, Keyword)
  let first = cache.tokens_for_line(doc, -5)
  assert_eq(first, last)
}

///|
test "plain language and lookup" {
  let lang = plain_language()
  assert_eq(lang.name(), "plain")
  let (tokens, state) = lang.tokenize("hello", 0)
  assert_eq(state, 0)
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0].typ, VariableName)
  assert_eq(tokens[0].from, 0)
  assert_eq(tokens[0].to, 5)
  let (empty, _) = lang.tokenize("", 0)
  assert_eq(empty.length(), 0)
  assert_eq(language_by_name("json").name(), "json")
  assert_eq(language_by_name("markdown").name(), "markdown")
  assert_eq(language_by_name("moonbit").name(), "moonbit")
  assert_eq(language_by_name("javascript").name(), "javascript")
  assert_eq(language_by_name("js").name(), "javascript")
  assert_eq(language_by_name("nope").name(), "plain")
  let json = json_language()
  assert_eq(json.brackets().length(), 2)
  assert_eq(json.line_comment(), None)
  let moonbit = moonbit_language()
  assert_eq(moonbit.line_comment(), Some("//"))
  assert_eq(moonbit.block_comment(), Some(("/*", "*/")))
  assert_eq(moonbit.indent("let x = 1", 0, 3), 3)
  assert_eq(moonbit.brackets().length(), 3)
}

///|
test "javascript keywords regex and template" {
  let lang = javascript_language()
  let (tokens, state) = lang.tokenize("const x = /ab+c/gi; // c", 0)
  assert_eq(state, 0)
  assert_eq(tokens.length(), 6)
  assert_eq(tokens[0].typ, Keyword)
  assert_eq(tokens[1].typ, VariableName)
  assert_eq(tokens[2].typ, Operator)
  assert_eq(tokens[3].typ, String)
  assert_eq(tokens[3].from, 10)
  assert_eq(tokens[3].to, 18)
  assert_eq(tokens[4].typ, Punctuation)
  assert_eq(tokens[5].typ, Comment)
  let (division, _) = lang.tokenize("a / b", 0)
  assert_eq(division[1].typ, Operator)
  let (template, template_state) = lang.tokenize("`abc", 0)
  assert_eq(template_state, 2)
  assert_eq(template[0].typ, String)
  let (rest, rest_state) = lang.tokenize("def` + 1", 2)
  assert_eq(rest_state, 0)
  assert_eq(rest[0].typ, String)
  assert_eq(rest[0].to, 4)
  let (klass, _) = lang.tokenize("new Promise(fn)", 0)
  assert_eq(klass[1].typ, TypeName)
  let (comment, comment_state) = lang.tokenize("/* partial", 0)
  assert_eq(comment_state, 1)
  assert_eq(comment[0].typ, Comment)
  let (closed, closed_state) = lang.tokenize("done */ x", 1)
  assert_eq(closed_state, 0)
  assert_eq(closed[0].typ, Comment)
  assert_eq(closed[0].to, 7)
}
