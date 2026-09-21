///|
fn cursor_state(content : String, pos : Int) -> @state.EditorState {
  @state.EditorState::create(
    doc=@core.Text::of(content),
    selection=@core.EditorSelection::cursor(pos),
  )
}

///|
fn state_of(
  content : String,
  selection : @core.EditorSelection,
) -> @state.EditorState {
  @state.EditorState::create(doc=@core.Text::of(content), selection~)
}

///|
fn has_range(sel : @core.EditorSelection, from : Int, to : Int) -> Bool {
  for r in sel.ranges() {
    if r.from() == from && r.to() == to {
      return true
    }
  }
  false
}

///|
test "insert text at cursor and over selection" {
  let st = cursor_state("hello", 5)
  let tr = st.update(insert_text(st, " world"))
  assert_eq(tr.user_event(), Some("input.type"))
  let st2 = tr.state()
  assert_eq(st2.to_string(), "hello world")
  assert_eq(st2.selection().main_range().head, 11)
  let st3 = state_of("hello", @core.EditorSelection::single(1, 4))
  let st4 = st3.apply(insert_text(st3, "i"))
  assert_eq(st4.to_string(), "hio")
  assert_eq(st4.selection().main_range().anchor, 2)
  assert_eq(st4.selection().main_range().head, 2)
}

///|
test "insert newline copies indentation" {
  let st = cursor_state("  foo", 5)
  let st2 = st.apply(insert_newline(st))
  assert_eq(st2.to_string(), "  foo\n  ")
  assert_eq(st2.selection().main_range().head, 8)
}

///|
test "backspace deletes char or selection" {
  let st = cursor_state("abc", 2)
  let tr = st.update(delete_char_backward(st))
  assert_eq(tr.user_event(), Some("input.delete"))
  let st2 = tr.state()
  assert_eq(st2.to_string(), "ac")
  assert_eq(st2.selection().main_range().head, 1)
  let st3 = state_of("abc", @core.EditorSelection::single(0, 3))
  let st4 = st3.apply(delete_char_backward(st3))
  assert_eq(st4.to_string(), "")
  assert_eq(st4.selection().main_range().head, 0)
  let st5 = st.apply(delete_char_forward(st))
  assert_eq(st5.to_string(), "ab")
  assert_eq(st5.selection().main_range().head, 2)
}

///|
test "cursor motion respects surrogate pairs" {
  let st = cursor_state("a🤣b", 1)
  let right = st.apply(cursor_char_right(st))
  assert_eq(right.selection().main_range().head, 3)
  let left = st.apply(cursor_char_left(st))
  assert_eq(left.selection().main_range().head, 0)
  let st2 = cursor_state("a🤣b", 3)
  let left2 = st2.apply(cursor_char_left(st2))
  assert_eq(left2.selection().main_range().head, 1)
  let del = left2.apply(delete_char_forward(left2))
  assert_eq(del.to_string(), "ab")
  let back = right.apply(delete_char_backward(right))
  assert_eq(back.to_string(), "ab")
}

///|
test "line up and down preserve column and clamp" {
  let st = cursor_state("abc\nde\nfghij", 2)
  let d1 = st.apply(cursor_line_down(st))
  assert_eq(d1.selection().main_range().head, 6)
  let d2 = d1.apply(cursor_line_down(d1))
  assert_eq(d2.selection().main_range().head, 9)
  let u1 = d2.apply(cursor_line_up(d2))
  assert_eq(u1.selection().main_range().head, 6)
  let u2 = u1.apply(cursor_line_up(u1))
  assert_eq(u2.selection().main_range().head, 2)
  let st2 = cursor_state("abc\nde\nfghij", 11)
  let u3 = st2.apply(cursor_line_up(st2))
  assert_eq(u3.selection().main_range().head, 6)
  let st3 = cursor_state("abc\nde\nfghij", 0)
  let u4 = st3.apply(cursor_line_up(st3))
  assert_eq(u4.selection().main_range().head, 0)
}

///|
test "line and doc boundaries" {
  let st = cursor_state("ab\ncd", 3)
  assert_eq(st.apply(cursor_line_start(st)).selection().main_range().head, 3)
  assert_eq(st.apply(cursor_line_end(st)).selection().main_range().head, 5)
  assert_eq(st.apply(cursor_doc_start(st)).selection().main_range().head, 0)
  assert_eq(st.apply(cursor_doc_end(st)).selection().main_range().head, 5)
  assert_eq(
    st.apply(cursor_visual_line_start(st)).selection().main_range().head,
    3,
  )
}

///|
test "select variants extend selections" {
  let st = cursor_state("abc", 1)
  let st2 = st.apply(select_char_right(st))
  assert_eq(st2.selection().main_range().anchor, 1)
  assert_eq(st2.selection().main_range().head, 2)
  let st3 = st2.apply(select_char_left(st2))
  assert_eq(st3.selection().main_range().anchor, 1)
  assert_eq(st3.selection().main_range().head, 1)
  let st4 = cursor_state("ab\ncd", 1)
  let st5 = st4.apply(select_line_down(st4))
  assert_eq(st5.selection().main_range().anchor, 1)
  assert_eq(st5.selection().main_range().head, 4)
  let st6 = st4.apply(select_doc_end(st4))
  assert_eq(st6.selection().main_range().anchor, 1)
  assert_eq(st6.selection().main_range().head, 5)
  let st7 = st4.apply(select_line_end(st4))
  assert_eq(st7.selection().main_range().head, 2)
  let st8 = st4.apply(select_line_start(st4))
  assert_eq(st8.selection().main_range().head, 0)
}

///|
test "word deletion" {
  let st = cursor_state("hello world", 11)
  let a = st.apply(delete_group_backward(st))
  assert_eq(a.to_string(), "hello ")
  let b = a.apply(delete_group_backward(a))
  assert_eq(b.to_string(), "hello")
  let c = b.apply(delete_group_backward(b))
  assert_eq(c.to_string(), "")
  let punct = cursor_state("abc.. def", 5)
  let p = punct.apply(delete_group_backward(punct))
  assert_eq(p.to_string(), "abc def")
}

///|
test "delete to line start and end" {
  let st = cursor_state("hello\nworld", 8)
  let a = st.apply(delete_to_line_start(st))
  assert_eq(a.to_string(), "hello\nrld")
  assert_eq(a.selection().main_range().head, 6)
  let b = st.apply(delete_to_line_end(st))
  assert_eq(b.to_string(), "hello\nwo")
  assert_eq(b.selection().main_range().head, 8)
}

///|
test "indent more and less multiple lines" {
  let st = state_of("a\nb\nc", @core.EditorSelection::single(0, 5))
  assert_eq(st.update(indent_more(st)).user_event(), Some("input.indent"))
  let st2 = st.apply(indent_more(st))
  assert_eq(st2.to_string(), "    a\n    b\n    c")
  let st3 = st2.apply(indent_less(st2))
  assert_eq(st3.to_string(), "a\nb\nc")
  let single = cursor_state("x", 1)
  let st4 = single.apply(indent_more(single))
  assert_eq(st4.to_string(), "    x")
}

///|
test "indent less removes a tab or spaces" {
  let st = cursor_state("\tfoo", 0)
  let st2 = st.apply(indent_less(st))
  assert_eq(st2.to_string(), "foo")
  let st3 = cursor_state("      foo", 0)
  let st4 = st3.apply(indent_less(st3))
  assert_eq(st4.to_string(), "  foo")
}

///|
test "insert tab indents or advances to tab stop" {
  let st = cursor_state("ab", 0)
  assert_eq(st.update(insert_tab(st)).user_event(), Some("input.type"))
  let st2 = st.apply(insert_tab(st))
  assert_eq(st2.to_string(), "    ab")
  assert_eq(st2.selection().main_range().head, 4)
  let st3 = cursor_state("  ab", 2)
  let st4 = st3.apply(insert_tab(st3))
  assert_eq(st4.to_string(), "      ab")
  let st5 = cursor_state("abc", 3)
  let st6 = st5.apply(insert_tab(st5))
  assert_eq(st6.to_string(), "abc ")
  let st7 = cursor_state("abc", 1)
  let st8 = st7.apply(insert_tab(st7))
  assert_eq(st8.to_string(), "a   bc")
}

///|
test "indent helpers" {
  assert_eq(leading_whitespace("  \tfoo"), "  \t")
  assert_eq(leading_whitespace("foo"), "")
  assert_eq(count_indent("    foo"), 4)
  assert_eq(count_indent("\tfoo"), 4)
  assert_eq(count_indent(" \tfoo"), 4)
  assert_eq(count_indent("\t\tfoo"), 8)
  let doc = @core.Text::of("  a\n\tb")
  assert_eq(line_indent(doc, 0), 2)
  assert_eq(line_indent(doc, 1), 4)
}

///|
test "select all and select line" {
  let st = cursor_state("ab\ncd", 1)
  let sa = st.apply(select_all_cmd(st))
  assert_eq(sa.selection().main_range().anchor, 0)
  assert_eq(sa.selection().main_range().head, 5)
  let sl = st.apply(select_line(st))
  assert_eq(sl.selection().main_range().anchor, 0)
  assert_eq(sl.selection().main_range().head, 2)
}

///|
test "page up and down" {
  let st = cursor_state("0\n1\n2\n3\n4\n5\n6\n7\n8\n9", 2)
  let d = st.apply(page_down(st, lines=3))
  assert_eq(d.selection().main_range().head, 8)
  let u = d.apply(page_up(d, lines=3))
  assert_eq(u.selection().main_range().head, 2)
  let bottom = st.apply(page_down(st, lines=100))
  assert_eq(bottom.selection().main_range().head, 18)
}

///|
test "binding spec normalization" {
  let e : KeyEvent = { key: "z", code: "KeyZ", mods: mod_ctrl | mod_shift }
  assert_eq(binding_spec(e), "Shift-Ctrl-z")
  let e2 : KeyEvent = { key: "A", code: "KeyA", mods: mod_shift }
  assert_eq(binding_spec(e2), "Shift-a")
  let e3 : KeyEvent = {
    key: "ArrowUp",
    code: "ArrowUp",
    mods: mod_alt | mod_shift,
  }
  assert_eq(binding_spec(e3), "Shift-Alt-ArrowUp")
  let e4 : KeyEvent = { key: " ", code: "Space", mods: 0 }
  assert_eq(binding_spec(e4), "Space")
  let e5 : KeyEvent = { key: "a", code: "KeyA", mods: mod_meta }
  assert_eq(binding_spec(e5), "Meta-a")
}

///|
test "keymap matches modifiers and Mod" {
  let st = cursor_state("hello", 1)
  let km = Keymap::new().bind([
    key_binding(key="Ctrl-Shift-z", run=some(select_all_cmd)),
    key_binding(key="Mod-y", run=some(cursor_doc_end)),
  ])
  let e : KeyEvent = { key: "z", code: "KeyZ", mods: mod_ctrl | mod_shift }
  let st2 = st.apply(km.run(st, e).unwrap())
  assert_eq(st2.selection().main_range().head, 5)
  let ey : KeyEvent = { key: "y", code: "KeyY", mods: mod_ctrl }
  let st3 = st.apply(km.run(st, ey).unwrap())
  assert_eq(st3.selection().main_range().head, 5)
  let plain_y : KeyEvent = { key: "y", code: "KeyY", mods: 0 }
  assert_true(km.run(st, plain_y) is None)
  let meta_y : KeyEvent = { key: "y", code: "KeyY", mods: mod_meta }
  assert_true(km.run(st, meta_y) is None)
  let alt_y : KeyEvent = { key: "y", code: "KeyY", mods: mod_alt }
  assert_true(km.run(st, alt_y) is None)
}

///|
test "platform mod matches meta instead of ctrl" {
  let st = cursor_state("abc", 1)
  let km = Keymap::new().add(key_binding(key="Mod-a", run=some(select_all_cmd)))
  let mac : KeyEvent = { key: "a", code: "KeyA", mods: mod_meta | mod_platform }
  let st2 = st.apply(km.run(st, mac).unwrap())
  assert_eq(st2.selection().main_range().anchor, 0)
  assert_eq(st2.selection().main_range().head, 3)
  let plain_meta : KeyEvent = { key: "a", code: "KeyA", mods: mod_meta }
  assert_true(km.run(st, plain_meta) is None)
  let mac_ctrl : KeyEvent = {
    key: "a",
    code: "KeyA",
    mods: mod_ctrl | mod_platform,
  }
  assert_true(km.run(st, mac_ctrl) is None)
  let ctrl : KeyEvent = { key: "a", code: "KeyA", mods: mod_ctrl }
  let st3 = st.apply(km.run(st, ctrl).unwrap())
  assert_eq(st3.selection().main_range().head, 3)
}

///|
test "configured indent drives indent commands" {
  let st = @state.EditorState::create(
    config=[indent_unit(2)],
    doc=@core.Text::of("a\nb"),
    selection=@core.EditorSelection::single(0, 3),
  )
  assert_eq(configured_indent(st), 2)
  let st2 = st.apply(indent_more(st))
  assert_eq(st2.to_string(), "  a\n  b")
  let st3 = st2.apply(indent_less(st2))
  assert_eq(st3.to_string(), "a\nb")
  let cursor = @state.EditorState::create(
    config=[indent_unit(2)],
    doc=@core.Text::of("ab"),
    selection=@core.EditorSelection::cursor(0),
  )
  assert_eq(cursor.apply(insert_tab(cursor)).to_string(), "  ab")
  let fallback = cursor_state("ab", 0)
  assert_eq(configured_indent(fallback), 4)
  assert_eq(fallback.apply(insert_tab(fallback)).to_string(), "    ab")
  assert_eq(fallback.apply(indent_more(fallback)).to_string(), "    ab")
}

///|
test "default keymap forwards the configured indent" {
  let st = @state.EditorState::create(
    config=[indent_unit(2)],
    doc=@core.Text::of("ab"),
    selection=@core.EditorSelection::cursor(0),
  )
  let tab : KeyEvent = { key: "Tab", code: "Tab", mods: 0 }
  let st2 = st.apply(run_keymap_facet(st, tab).unwrap())
  assert_eq(st2.to_string(), "  ab")
  let bracket : KeyEvent = { key: "]", code: "BracketRight", mods: mod_ctrl }
  let st3 = st.apply(run_keymap_facet(st, bracket).unwrap())
  assert_eq(st3.to_string(), "  ab")
  let close : KeyEvent = { key: "[", code: "BracketLeft", mods: mod_ctrl }
  let st4 = st3.apply(run_keymap_facet(st3, close).unwrap())
  assert_eq(st4.to_string(), "ab")
}

///|
test "keymap shift variant" {
  let custom : KeyBinding = {
    key: "Enter",
    run: fn(_) { None },
    shift: fn(state) { Some(insert_text(state, ";")) },
  }
  let km = Keymap::new().add(custom)
  let st = cursor_state("ab", 1)
  let ev : KeyEvent = { key: "Enter", code: "Enter", mods: mod_shift }
  let st2 = st.apply(km.run(st, ev).unwrap())
  assert_eq(st2.to_string(), "a;b")
}

///|
test "run keymap facet falls back to defaults" {
  let st = cursor_state("abc", 1)
  let ev : KeyEvent = { key: "ArrowRight", code: "ArrowRight", mods: 0 }
  let st2 = st.apply(run_keymap_facet(st, ev).unwrap())
  assert_eq(st2.selection().main_range().head, 2)
  let shift_ev : KeyEvent = {
    key: "ArrowLeft",
    code: "ArrowLeft",
    mods: mod_shift,
  }
  let st3 = st2.apply(run_keymap_facet(st2, shift_ev).unwrap())
  assert_eq(st3.selection().main_range().anchor, 2)
  assert_eq(st3.selection().main_range().head, 1)
  let enter : KeyEvent = { key: "Enter", code: "Enter", mods: 0 }
  let st4 = st.apply(run_keymap_facet(st, enter).unwrap())
  assert_eq(st4.to_string(), "a\nbc")
  let escape : KeyEvent = { key: "Escape", code: "Escape", mods: 0 }
  assert_true(run_keymap_facet(st, escape) is None)
  let backspace : KeyEvent = { key: "Backspace", code: "Backspace", mods: 0 }
  let st5 = st.apply(run_keymap_facet(st, backspace).unwrap())
  assert_eq(st5.to_string(), "bc")
}

///|
test "run keymap facet uses configured keymap" {
  let configured = Keymap::new().add(
    key_binding(key="Mod-a", run=some(select_all_cmd)),
  )
  let st = @state.EditorState::create(
    config=[keymap(configured.bindings())],
    doc=@core.Text::of("abc"),
    selection=@core.EditorSelection::cursor(1),
  )
  let ev : KeyEvent = { key: "a", code: "KeyA", mods: mod_ctrl }
  let st2 = st.apply(run_keymap_facet(st, ev).unwrap())
  assert_eq(st2.selection().main_range().anchor, 0)
  assert_eq(st2.selection().main_range().head, 3)
  let right : KeyEvent = { key: "ArrowRight", code: "ArrowRight", mods: 0 }
  assert_true(run_keymap_facet(st, right) is None)
}

///|
test "add cursor above and below then insert" {
  let st = cursor_state("aaa\nbbb\nccc", 5)
  let st2 = st.apply(add_cursor_above(st))
  assert_eq(st2.selection().range_count(), 2)
  assert_eq(st2.selection().main_index(), 0)
  assert_true(has_range(st2.selection(), 1, 1))
  let st3 = st2.apply(add_cursor_below(st2))
  assert_eq(st3.selection().range_count(), 3)
  assert_true(has_range(st3.selection(), 9, 9))
  let st4 = st3.apply(insert_text(st3, "x"))
  assert_eq(st4.to_string(), "axaa\nbxbb\ncxcc")
  assert_eq(st4.selection().range_count(), 3)
}

///|
test "add cursor above stops at document top" {
  let st = cursor_state("aaa\nbbb", 1)
  let st2 = st.apply(add_cursor_above(st))
  assert_eq(st2.selection().range_count(), 1)
}

///|
test "add cursor to line end" {
  let st = cursor_state("abc\ndef", 1)
  let st2 = st.apply(add_cursor_to_line_end(st))
  assert_eq(st2.selection().range_count(), 2)
  assert_true(has_range(st2.selection(), 3, 3))
}

///|
test "select next occurrence" {
  let st = state_of("foo bar foo baz foo", @core.EditorSelection::single(0, 3))
  assert_true(select_next_occurrence(st, selection_text="") is None)
  let spec = select_next_occurrence(st, selection_text="foo").unwrap()
  let st2 = st.apply(spec)
  assert_eq(st2.selection().range_count(), 2)
  assert_eq(st2.selection().main_index(), 0)
  assert_true(has_range(st2.selection(), 8, 11))
  let spec2 = select_next_occurrence(st2, selection_text="foo").unwrap()
  let st3 = st2.apply(spec2)
  assert_eq(st3.selection().range_count(), 3)
  assert_true(has_range(st3.selection(), 16, 19))
  assert_true(select_next_occurrence(st3, selection_text="foo") is None)
}

///|
test "select next occurrence wraps around" {
  let st = state_of("foo bar foo", @core.EditorSelection::single(8, 11))
  let st2 = st.apply(select_next_occurrence(st, selection_text="foo").unwrap())
  assert_eq(st2.selection().range_count(), 2)
  assert_true(has_range(st2.selection(), 0, 3))
}

///|
test "toggle line comment" {
  let st = state_of("  foo\nbar", @core.EditorSelection::single(0, 8))
  let tr = st.update(toggle_line_comment(st))
  assert_eq(tr.user_event(), Some("input.comment"))
  let st2 = tr.state()
  assert_eq(st2.to_string(), "  // foo\n// bar")
  let st3 = st2.apply(toggle_line_comment(st2))
  assert_eq(st3.to_string(), "  foo\nbar")
  let st4 = st3.apply(toggle_line_comment(st3, token="#"))
  assert_eq(st4.to_string(), "  # foo\n# bar")
}

///|
test "undo and redo commands" {
  let st0 = @state.EditorState::create(
    config=[@state.history_field.extension()],
    doc=@core.Text::of(""),
  )
  let st1 = st0.apply(insert_text(st0, "a"))
  let st2 = st1.apply(insert_text(st1, "b"))
  assert_eq(st2.to_string(), "ab")
  let st3 = st2.apply(undo_cmd(st2).unwrap())
  assert_eq(st3.to_string(), "")
  let st4 = st3.apply(redo_cmd(st3).unwrap())
  assert_eq(st4.to_string(), "ab")
}

///|
test "history groups consecutive insert_text transactions" {
  let st0 = @state.EditorState::create(
    config=[@state.history_field.extension()],
    doc=@core.Text::of(""),
  )
  let st1 = st0.apply(insert_text(st0, "h"))
  let st2 = st1.apply(insert_text(st1, "i"))
  assert_eq(st2.to_string(), "hi")
  let history = st2.field(@state.history_field)
  assert_eq(history.done.length(), 1)
  assert_eq(history.done[0].count, 2)
  let st3 = st2.apply(undo_cmd(st2).unwrap())
  assert_eq(st3.to_string(), "")
  assert_true(undo_cmd(st3) is None)
}

///|
test "motions at document boundaries do not abort" {
  let st = @state.EditorState::create(
    doc=@core.Text::of("ab\ncd"),
    selection=@core.EditorSelection::cursor(0),
  )
  let left = st.apply(cursor_char_left(st))
  assert_eq(left.selection().main_range().head, 0)
  let st2 = @state.EditorState::create(
    doc=@core.Text::of("ab\ncd"),
    selection=@core.EditorSelection::cursor(3),
  )
  let left2 = st2.apply(cursor_char_left(st2))
  assert_eq(left2.selection().main_range().head, 2)
  let st3 = @state.EditorState::create(
    doc=@core.Text::of("ab"),
    selection=@core.EditorSelection::cursor(2),
  )
  let right = st3.apply(cursor_char_right(st3))
  assert_eq(right.selection().main_range().head, 2)
  let back = st3.apply(delete_char_backward(st3))
  assert_eq(back.doc().to_string(), "a")
}

///|
test "backspace at start of line joins lines" {
  let st = @state.EditorState::create(
    doc=@core.Text::of("ab\ncd"),
    selection=@core.EditorSelection::cursor(3),
  )
  let back = st.apply(delete_char_backward(st))
  assert_eq(back.doc().to_string(), "abcd")
}

///|
test "word motion and selection" {
  let st = cursor_state("hello world  foo_bar", 11)
  let left = st.apply(cursor_word_left(st))
  assert_eq(left.selection().main_range().head, 6)
  let left2 = left.apply(cursor_word_left(left))
  assert_eq(left2.selection().main_range().head, 0)
  let right = st.apply(cursor_word_right(st))
  assert_eq(right.selection().main_range().head, 20)
  let sel = st.apply(select_word_left(st))
  assert_eq(sel.selection().main_range().anchor, 11)
  assert_eq(sel.selection().main_range().head, 6)
  let st2 = cursor_state("foo.bar baz", 3)
  let dot = st2.apply(cursor_word_left(st2))
  assert_eq(dot.selection().main_range().head, 0)
  assert_eq(st2.apply(cursor_word_right(st2)).selection().main_range().head, 4)
  let sel2 = st2.apply(select_word_right(st2))
  assert_eq(sel2.selection().main_range().anchor, 3)
  assert_eq(sel2.selection().main_range().head, 4)
}
