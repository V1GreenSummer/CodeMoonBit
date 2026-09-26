///|
test "literal search case sensitive" {
  let doc = @core.Text::of("Hello world hello")
  let matches = find_matches(
    doc,
    SearchQuery::new(text="hello", case_sensitive=true),
  )
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].from, 12)
  assert_eq(matches[0].to, 17)
}

///|
test "literal search case insensitive" {
  let doc = @core.Text::of("Hello world hello")
  let matches = find_matches(doc, SearchQuery::new(text="hello"))
  assert_eq(matches.length(), 2)
  assert_eq(matches[0].from, 0)
  assert_eq(matches[0].to, 5)
  assert_eq(matches[1].from, 12)
  assert_eq(matches[1].to, 17)
}

///|
test "literal whole word" {
  let doc = @core.Text::of("cat category cat.")
  let loose = find_matches(doc, SearchQuery::new(text="cat"))
  assert_eq(loose.length(), 3)
  let strict = find_matches(doc, SearchQuery::new(text="cat", whole_word=true))
  assert_eq(strict.length(), 2)
  assert_eq(strict[0].from, 0)
  assert_eq(strict[1].from, 13)
  let strict_case = find_matches(
    doc,
    SearchQuery::new(text="CAT", whole_word=true, case_sensitive=true),
  )
  assert_eq(strict_case.length(), 0)
}

///|
test "literal search across lines and limit" {
  let doc = @core.Text::of("ab\ncd\nab\nab")
  let matches = find_matches(doc, SearchQuery::new(text="ab"))
  assert_eq(matches.length(), 3)
  assert_eq(matches[1].from, 6)
  assert_eq(matches[2].from, 9)
  let limited = find_matches(doc, SearchQuery::new(text="ab"), limit=2)
  assert_eq(limited.length(), 2)
}

///|
test "empty query matches nothing" {
  let doc = @core.Text::of("abc")
  assert_eq(find_matches(doc, SearchQuery::new(text="")).length(), 0)
}

///|
test "search offsets are code units" {
  let doc = @core.Text::of("a🤣b")
  let emoji = find_matches(doc, SearchQuery::new(text="🤣"))
  assert_eq(emoji.length(), 1)
  assert_eq(emoji[0].from, 1)
  assert_eq(emoji[0].to, 3)
  let after = find_matches(doc, SearchQuery::new(text="b"))
  assert_eq(after.length(), 1)
  assert_eq(after[0].from, 3)
}

///|
test "regex classes and quantifiers" {
  let doc = @core.Text::of("abc 123\nxy 45")
  let letters = find_matches(doc, SearchQuery::new(text="[a-z]+", regex=true))
  assert_eq(letters.length(), 2)
  assert_eq(letters[0].from, 0)
  assert_eq(letters[0].to, 3)
  assert_eq(letters[1].from, 8)
  assert_eq(letters[1].to, 10)
  let digits = find_matches(doc, SearchQuery::new(text="\\d+", regex=true))
  assert_eq(digits.length(), 2)
  assert_eq(digits[0].from, 4)
  assert_eq(digits[0].to, 7)
  assert_eq(digits[1].from, 11)
  assert_eq(digits[1].to, 13)
}

///|
test "regex alternation and anchors" {
  let doc = @core.Text::of("abc123")
  let ab = find_matches(doc, SearchQuery::new(text="a|b", regex=true))
  assert_eq(ab.length(), 2)
  assert_eq(ab[0].from, 0)
  assert_eq(ab[0].to, 1)
  assert_eq(ab[1].from, 1)
  assert_eq(ab[1].to, 2)
  let head = find_matches(doc, SearchQuery::new(text="^abc", regex=true))
  assert_eq(head.length(), 1)
  assert_eq(head[0].from, 0)
  assert_eq(head[0].to, 3)
  let tail = find_matches(doc, SearchQuery::new(text="123$", regex=true))
  assert_eq(tail.length(), 1)
  assert_eq(tail[0].from, 3)
  assert_eq(tail[0].to, 6)
  assert_eq(
    find_matches(doc, SearchQuery::new(text="abc$", regex=true)).length(),
    0,
  )
}

///|
test "regex groups and optionals" {
  let doc = @core.Text::of("abab colour color")
  let group = find_matches(doc, SearchQuery::new(text="(ab)+", regex=true))
  assert_eq(group.length(), 1)
  assert_eq(group[0].from, 0)
  assert_eq(group[0].to, 4)
  let option = find_matches(doc, SearchQuery::new(text="colou?r", regex=true))
  assert_eq(option.length(), 2)
  assert_eq(option[0].from, 5)
  assert_eq(option[0].to, 11)
  assert_eq(option[1].from, 12)
  assert_eq(option[1].to, 17)
}

///|
test "regex star and escapes" {
  let doc = @core.Text::of("a.b axb a.b")
  let escaped = find_matches(doc, SearchQuery::new(text="a\\.b", regex=true))
  assert_eq(escaped.length(), 2)
  assert_eq(escaped[0].from, 0)
  assert_eq(escaped[0].to, 3)
  assert_eq(escaped[1].from, 8)
  assert_eq(escaped[1].to, 11)
  let star = find_matches(doc, SearchQuery::new(text="a.*b", regex=true))
  assert_eq(star.length(), 1)
  assert_eq(star[0].from, 0)
  assert_eq(star[0].to, 11)
  let words = find_matches(doc, SearchQuery::new(text="\\w+", regex=true))
  assert_eq(words.length(), 5)
}

///|
test "regex anchors per line" {
  let doc = @core.Text::of("ab\ncd\nab")
  let starts = find_matches(doc, SearchQuery::new(text="^ab", regex=true))
  assert_eq(starts.length(), 2)
  assert_eq(starts[0].from, 0)
  assert_eq(starts[1].from, 6)
  let ends = find_matches(doc, SearchQuery::new(text="cd$", regex=true))
  assert_eq(ends.length(), 1)
  assert_eq(ends[0].from, 3)
  assert_eq(ends[0].to, 5)
}

///|
test "regex empty matches are skipped" {
  let doc = @core.Text::of("ab")
  let matches = find_matches(doc, SearchQuery::new(text="a*", regex=true))
  assert_eq(matches.length(), 1)
  assert_eq(matches[0].from, 0)
  assert_eq(matches[0].to, 1)
}

///|
test "regex negated class and word boundary" {
  let doc = @core.Text::of("foo bar_baz qux")
  let word = find_matches(doc, SearchQuery::new(text="\\bfoo\\b", regex=true))
  assert_eq(word.length(), 1)
  assert_eq(word[0].from, 0)
  assert_eq(word[0].to, 3)
  assert_eq(
    find_matches(doc, SearchQuery::new(text="\\bbar\\b", regex=true)).length(),
    0,
  )
  let negated = find_matches(doc, SearchQuery::new(text="[^a-z ]+", regex=true))
  assert_eq(negated.length(), 1)
  assert_eq(negated[0].from, 7)
  assert_eq(negated[0].to, 8)
}

///|
test "regex case insensitive and whole word" {
  let doc = @core.Text::of("AbC abcX")
  let insensitive = find_matches(doc, SearchQuery::new(text="abc", regex=true))
  assert_eq(insensitive.length(), 2)
  assert_eq(insensitive[0].to, 3)
  let cached = find_matches(
    doc,
    SearchQuery::new(text="abc", regex=true, case_sensitive=true),
  )
  assert_eq(cached.length(), 1)
  assert_eq(cached[0].from, 4)
  let whole = find_matches(
    doc,
    SearchQuery::new(text="abc", regex=true, whole_word=true),
  )
  assert_eq(whole.length(), 1)
  assert_eq(whole[0].to, 3)
}

///|
test "regex dot does not cross lines" {
  let doc = @core.Text::of("a\nb")
  let matches = find_matches(doc, SearchQuery::new(text="a.b", regex=true))
  assert_eq(matches.length(), 0)
}

///|
test "search field tracks query and document" {
  let doc = @core.Text::of("one two one")
  let st0 = @state.EditorState::create(config=[search_field.extension()], doc~)
  assert_false(st0.field(search_field).open)
  assert_false(is_search_open(st0))
  let st1 = st0.apply(open_search())
  assert_true(is_search_open(st1))
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="one")))
  let search = st2.field(search_field)
  assert_eq(search.matches.length(), 2)
  assert_eq(search.current, 0)
  assert_eq(search.query.text, "one")
  assert_eq(st2.selection().main_range().from(), 0)
  assert_eq(st2.selection().main_range().to(), 3)
  let st3 = st2.apply(
    @state.TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(0, "one ")]),
    ),
  )
  assert_eq(st3.field(search_field).matches.length(), 3)
  let st4 = st3.apply(close_search(st3))
  assert_false(st4.field(search_field).open)
  assert_eq(st4.field(search_field).matches.length(), 0)
}

///|
test "search field clamps current" {
  let doc = @core.Text::of("one two one")
  let st0 = @state.EditorState::create(config=[search_field.extension()], doc~)
  let st1 = st0.apply(open_search())
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="one")))
  let st3 = st2.apply(
    @state.TransactionSpec::new(effects=[set_current_effect.of(99)]),
  )
  assert_eq(st3.field(search_field).current, 1)
}

///|
test "select next and prev wrap around" {
  let doc = @core.Text::of("one two one")
  let st0 = @state.EditorState::create(config=[search_field.extension()], doc~)
  let st1 = st0.apply(open_search())
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="one")))
  let st3 = st2.apply(select_next(st2).unwrap())
  assert_eq(st3.field(search_field).current, 1)
  assert_eq(st3.selection().main_range().from(), 8)
  assert_eq(st3.selection().main_range().to(), 11)
  let st4 = st3.apply(select_next(st3).unwrap())
  assert_eq(st4.field(search_field).current, 0)
  assert_eq(st4.selection().main_range().from(), 0)
  let st5 = st4.apply(select_prev(st4).unwrap())
  assert_eq(st5.field(search_field).current, 1)
}

///|
test "replace current" {
  let doc = @core.Text::of("one two one")
  let st0 = @state.EditorState::create(config=[search_field.extension()], doc~)
  let st1 = st0.apply(open_search())
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="one")))
  let st3 = st2.apply(select_next(st2).unwrap())
  let st4 = st3.apply(replace_current(st3, "1").unwrap())
  assert_eq(st4.doc().to_string(), "one two 1")
  assert_eq(st4.field(search_field).replace_text, "1")
  assert_eq(st4.selection().main_range().from(), 8)
  assert_eq(st4.selection().main_range().to(), 9)
  assert_eq(st4.field(search_field).matches.length(), 1)
}

///|
test "replace all builds change set" {
  let doc = @core.Text::of("a b a")
  let st0 = @state.EditorState::create(config=[search_field.extension()], doc~)
  let st1 = st0.apply(open_search())
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="a")))
  let st3 = st2.apply(replace_all(st2, "XY").unwrap())
  assert_eq(st3.doc().to_string(), "XY b XY")
  assert_eq(st3.selection().main_range().from(), 0)
  assert_eq(st3.selection().main_range().to(), 7)
  assert_eq(st3.field(search_field).matches.length(), 0)
  assert_eq(st3.field(search_field).replace_text, "XY")
}

///|
test "replace transactions are undoable" {
  let doc = @core.Text::of("a b a")
  let st0 = @state.EditorState::create(
    config=[search_field.extension(), @state.history_field.extension()],
    doc~,
  )
  let st1 = st0.apply(open_search())
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="a")))
  let st3 = st2.apply(replace_all(st2, "XY").unwrap())
  assert_eq(st3.doc().to_string(), "XY b XY")
  let st4 = st3.apply(@state.undo_spec(st3).unwrap())
  assert_eq(st4.doc().to_string(), "a b a")
  assert_eq(st4.field(search_field).matches.length(), 2)
}

///|
test "replace all scans past the display limit" {
  let original = "a ".repeat(1001)
  let doc = @core.Text::of(original)
  let st0 = @state.EditorState::create(
    config=[search_field.extension(), @state.history_field.extension()],
    doc~,
  )
  let st1 = st0.apply(open_search())
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="a")))
  assert_eq(st2.field(search_field).matches.length(), 1000)
  let st3 = st2.apply(replace_all(st2, "b").unwrap())
  assert_eq(st3.doc().to_string(), "b ".repeat(1001))
  let done = st3.field(@state.history_field).done
  assert_eq(done.length(), 1)
  assert_eq(done[0].event, "replace")
  let st4 = st3.apply(@state.undo_spec(st3).unwrap())
  assert_eq(st4.doc().to_string(), original)
}

///|
test "replace commands are no-ops without matches" {
  let doc = @core.Text::of("abc")
  let st0 = @state.EditorState::create(config=[search_field.extension()], doc~)
  let st1 = st0.apply(open_search())
  let st2 = st1.apply(set_query(st1, SearchQuery::new(text="zzz")))
  assert_true(select_next(st2) is None)
  assert_true(select_prev(st2) is None)
  assert_true(replace_current(st2, "x") is None)
  assert_true(replace_all(st2, "x") is None)
  let plain = @state.EditorState::create(doc~)
  assert_false(is_search_open(plain))
  assert_true(select_next(plain) is None)
}

///|
test "fold braces" {
  let doc = @core.Text::of("{\n  a;\n  b;\n}\n")
  let folds = compute_folds(doc, [("{", "}"), ("(", ")")], None)
  assert_eq(folds.length(), 1)
  assert_eq(folds[0].from_line, 0)
  assert_eq(folds[0].to_line, 3)
}

///|
test "fold indentation" {
  let doc = @core.Text::of("if x:\n  a\n  b\nc\nd")
  let folds = compute_folds(doc, [], None)
  assert_eq(folds.length(), 1)
  assert_eq(folds[0].from_line, 0)
  assert_eq(folds[0].to_line, 2)
}

///|
test "fold indentation includes blank lines" {
  let doc = @core.Text::of("a\n  b\n\n  c\nd")
  let folds = compute_folds(doc, [], None)
  assert_eq(folds.length(), 1)
  assert_eq(folds[0].from_line, 0)
  assert_eq(folds[0].to_line, 3)
}

///|
test "fold bracket nesting stays non overlapping" {
  let doc = @core.Text::of("{\n  if (x) {\n    y\n  }\n}\n")
  let folds = compute_folds(doc, [("{", "}"), ("(", ")")], None)
  assert_eq(folds.length(), 1)
  assert_eq(folds[0].from_line, 0)
  assert_eq(folds[0].to_line, 4)
}

///|
test "fold respects line comments" {
  let doc = @core.Text::of("{\n  a\n// }\n}\nx")
  let with_comment = compute_folds(doc, [("{", "}")], Some("//"))
  assert_eq(with_comment.length(), 1)
  assert_eq(with_comment[0].from_line, 0)
  assert_eq(with_comment[0].to_line, 3)
  let without_comment = compute_folds(doc, [("{", "}")], None)
  assert_eq(without_comment.length(), 1)
  assert_eq(without_comment[0].from_line, 0)
  assert_eq(without_comment[0].to_line, 2)
}

///|
test "fold commands and visibility" {
  let doc = @core.Text::of("{\n  a\n}\nb")
  let st0 = @state.EditorState::create(config=[fold_field.extension()], doc~)
  let brackets = [("{", "}")]
  assert_false(is_line_hidden(st0, 1))
  let st1 = st0.apply(fold_at(st0, brackets).unwrap())
  assert_true(is_line_hidden(st1, 1))
  assert_true(is_line_hidden(st1, 2))
  assert_false(is_line_hidden(st1, 0))
  assert_eq(next_visible_line(st1, 1), 3)
  assert_eq(prev_visible_line(st1, 1), 0)
  assert_eq(next_visible_line(st1, 0), 0)
  let st2 = st1.apply(unfold_at(st1).unwrap())
  assert_false(is_line_hidden(st2, 1))
  assert_true(unfold_at(st2) is None)
}

///|
test "fold all and unfold all" {
  let doc = @core.Text::of("{\n  a\n}\n{\n  b\n}\n")
  let st0 = @state.EditorState::create(config=[fold_field.extension()], doc~)
  let brackets = [("{", "}")]
  let st1 = st0.apply(fold_all(st0, brackets).unwrap())
  assert_true(is_line_hidden(st1, 1))
  assert_true(is_line_hidden(st1, 2))
  assert_true(is_line_hidden(st1, 4))
  assert_true(is_line_hidden(st1, 5))
  let st2 = st1.apply(unfold_all(st1).unwrap())
  assert_false(is_line_hidden(st2, 1))
  assert_true(unfold_all(st2) is None)
  let empty_doc = @core.Text::of("plain\ntext")
  let plain = @state.EditorState::create(
    config=[fold_field.extension()],
    doc=empty_doc,
  )
  assert_true(fold_all(plain, brackets) is None)
  assert_false(is_line_hidden(plain, 1))
  assert_eq(next_visible_line(plain, 0), 0)
  assert_eq(prev_visible_line(plain, 1), 1)
}

///|
test "fold field update replaces folds" {
  let doc = @core.Text::of("{\n  a\n}\nb")
  let st0 = @state.EditorState::create(config=[fold_field.extension()], doc~)
  let st1 = st0.apply(
    @state.TransactionSpec::new(effects=[
      set_folds_effect.of([FoldRange::{ from_line: 0, to_line: 2, }]),
    ]),
  )
  assert_eq(st1.field(fold_field).folded.length(), 1)
  assert_true(is_line_hidden(st1, 2))
  let st2 = st1.apply(
    @state.TransactionSpec::new(effects=[set_folds_effect.of([])]),
  )
  assert_eq(st2.field(fold_field).folded.length(), 0)
}

///|
test "fold ranges map through document edits" {
  let doc = @core.Text::of("fn main() {\n  a;\n  b;\n}\n")
  let brackets = [("{", "}")]
  let st0 = @state.EditorState::create(config=[fold_field.extension()], doc~)
  let st1 = st0.apply(fold_at(st0, brackets).unwrap())
  assert_true(is_line_hidden(st1, 1))
  assert_true(is_line_hidden(st1, 3))
  let before = st1.doc().slice(st1.doc().line_start(1), st1.doc().line_end(3))
  let st2 = st1.apply(
    @state.TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(0, "\n")]),
    ),
  )
  let folds = st2.field(fold_field).folded
  assert_eq(folds.length(), 1)
  assert_eq(folds[0].from_line, 1)
  assert_eq(folds[0].to_line, 4)
  assert_false(is_line_hidden(st2, 1))
  assert_true(is_line_hidden(st2, 2))
  assert_true(is_line_hidden(st2, 4))
  let after = st2.doc().slice(st2.doc().line_start(2), st2.doc().line_end(4))
  assert_eq(after, before)
}

///|
test "fold line ignores the cursor" {
  let doc = @core.Text::of("fn main() {\n  a;\n  b;\n}\n")
  let brackets = [("{", "}")]
  let st0 = @state.EditorState::create(
    config=[fold_field.extension()],
    doc~,
    selection=@core.EditorSelection::cursor(doc.length()),
  )
  let st1 = st0.apply(fold_line(st0, 0, brackets).unwrap())
  assert_true(is_line_hidden(st1, 1))
  assert_true(is_line_hidden(st1, 3))
  assert_eq(st1.selection().main_range().head_pos(), doc.length())
  let st2 = st0.apply(fold_line(st0, 2, brackets).unwrap())
  assert_true(is_line_hidden(st2, 3))
  assert_eq(st2.selection().main_range().head_pos(), doc.length())
}

///|
test "unfold line ignores the cursor" {
  let doc = @core.Text::of("fn main() {\n  a;\n  b;\n}\n")
  let brackets = [("{", "}")]
  let st0 = @state.EditorState::create(
    config=[fold_field.extension()],
    doc~,
    selection=@core.EditorSelection::cursor(doc.length()),
  )
  let st1 = st0.apply(fold_line(st0, 0, brackets).unwrap())
  assert_true(is_line_hidden(st1, 1))
  assert_true(is_line_hidden(st1, 3))
  let st2 = st1.apply(unfold_line(st1, 0).unwrap())
  assert_false(is_line_hidden(st2, 1))
  assert_false(is_line_hidden(st2, 3))
  assert_eq(st2.selection().main_range().head_pos(), doc.length())
  assert_true(unfold_line(st2, 0) is None)
}

///|
test "matching brackets nested" {
  let doc = @core.Text::of("(a[b])c")
  let brackets = [("(", ")"), ("[", "]"), ("{", "}")]
  let outer = matching_bracket(doc, 0, brackets).unwrap()
  assert_eq(outer.from, 0)
  assert_eq(outer.to, 6)
  let inner = matching_bracket(doc, 2, brackets).unwrap()
  assert_eq(inner.from, 2)
  assert_eq(inner.to, 5)
  let after_close = matching_bracket(doc, 5, brackets).unwrap()
  assert_eq(after_close.from, 2)
  assert_eq(after_close.to, 5)
  let after_outer = matching_bracket(doc, 6, brackets).unwrap()
  assert_eq(after_outer.from, 0)
  assert_eq(after_outer.to, 6)
  assert_true(matching_bracket(doc, 3, brackets) is None)
}

///|
test "matching brackets with same type nesting" {
  let doc = @core.Text::of("((x))")
  let brackets = [("(", ")"), ("[", "]"), ("{", "}")]
  let outer = matching_bracket(doc, 0, brackets).unwrap()
  assert_eq(outer.from, 0)
  assert_eq(outer.to, 5)
  let inner = matching_bracket(doc, 1, brackets).unwrap()
  assert_eq(inner.from, 1)
  assert_eq(inner.to, 4)
  let after_inner = matching_bracket(doc, 4, brackets).unwrap()
  assert_eq(after_inner.from, 1)
  assert_eq(after_inner.to, 4)
}

///|
test "matching brackets mismatched" {
  let brackets = [("(", ")"), ("[", "]"), ("{", "}")]
  let doc = @core.Text::of("(a]")
  assert_true(matching_bracket(doc, 0, brackets) is None)
  assert_true(matching_bracket(doc, 1, brackets) is None)
  let doc2 = @core.Text::of("{a")
  assert_true(matching_bracket(doc2, 0, brackets) is None)
  let empty = @core.Text::of("")
  assert_true(matching_bracket(empty, 0, brackets) is None)
}
