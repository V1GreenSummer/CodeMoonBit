///|
test "facet default and combine" {
  let f : Facet[Int] = Facet::new(default=fn() { 1 }, combine=fn(a, b) { a + b })
  let st = EditorState::create(config=[f.of(2), f.of(3)])
  assert_eq(st.facet(f), 6)
  let st2 = EditorState::create(config=[])
  assert_eq(st2.facet(f), 1)
}

///|
test "state field init and update" {
  let count : StateField[Int] = StateField::new(init=fn(_) { 0 }, update=fn(
    old,
    tr,
  ) {
    if tr.changes().is_empty() {
      old
    } else {
      old + 1
    }
  })
  let st = EditorState::create(
    config=[count.extension()],
    doc=@core.Text::of("abc"),
  )
  assert_eq(st.field(count), 0)
  let st2 = st.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::new(0, 0, "x")]),
    ),
  )
  assert_eq(st2.field(count), 1)
  assert_eq(st2.doc().to_string(), "xabc")
}

///|
test "transaction maps selection" {
  let st = EditorState::create(
    doc=@core.Text::of("hello"),
    selection=@core.EditorSelection::cursor(2),
  )
  let st2 = st.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(0, "XY")]),
    ),
  )
  assert_eq(st2.selection().main_range().head, 4)
}

///|
test "history groups typing and undo redo" {
  let st0 = EditorState::create(
    config=[history_field.extension()],
    doc=@core.Text::of(""),
  )
  let st1 = st0.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(0, "a")]),
      annotations=[UserEvent("input.type")],
    ),
  )
  let st2 = st1.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(1, "b")]),
      annotations=[UserEvent("input.type")],
    ),
  )
  assert_eq(st2.doc().to_string(), "ab")
  let history = st2.field(history_field)
  assert_eq(history.done.length(), 1)
  assert_eq(history.done[0].count, 2)
  let undo = undo_spec(st2).unwrap()
  let st3 = st2.apply(undo)
  assert_eq(st3.doc().to_string(), "")
  let redo = redo_spec(st3).unwrap()
  let st4 = st3.apply(redo)
  assert_eq(st4.doc().to_string(), "ab")
}

///|
test "history separates non typing edits" {
  let st0 = EditorState::create(
    config=[history_field.extension()],
    doc=@core.Text::of("hello"),
  )
  let st1 = st0.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::delete(0, 1)]),
      annotations=[UserEvent("delete")],
    ),
  )
  let st2 = st1.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(0, "H")]),
      annotations=[UserEvent("input.type")],
    ),
  )
  assert_eq(st2.field(history_field).done.length(), 2)
}
