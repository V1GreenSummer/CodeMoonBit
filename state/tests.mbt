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

///|
test "non-history edit clears undo history" {
  let st0 = EditorState::create(
    config=[history_field.extension()],
    doc=@core.Text::of("abc"),
  )
  let st1 = st0.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(1, "x")]),
      annotations=[UserEvent("input.type")],
    ),
  )
  assert_eq(st1.doc().to_string(), "axbc")
  assert_eq(st1.field(history_field).done.length(), 1)
  let st2 = st1.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(0, "Q")]),
      annotations=[AddToHistory(false)],
    ),
  )
  assert_eq(st2.doc().to_string(), "Qaxbc")
  assert_true(undo_spec(st2) is None)
  assert_true(redo_spec(st2) is None)
  assert_eq(st2.doc().to_string(), "Qaxbc")
  assert_eq(st2.field(history_field).done.length(), 0)
  assert_eq(st2.field(history_field).undone.length(), 0)
}

///|
test "remote document changes clear history" {
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
  assert_eq(st1.field(history_field).done.length(), 1)
  let st2 = st1.apply(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(1, "R")]),
      annotations=[Remote(true)],
    ),
  )
  assert_eq(st2.doc().to_string(), "aR")
  assert_eq(st2.field(history_field).done.length(), 0)
  assert_eq(st2.field(history_field).undone.length(), 0)
  assert_true(undo_spec(st2) is None)
}

///|
test "history group budget caps retained groups" {
  let mut st = EditorState::create(
    config=[history_field.extension()],
    doc=@core.Text::of(""),
  )
  let edits = history_max_groups + 5
  for i = 0; i < edits; i = i + 1 {
    st = st.apply(
      TransactionSpec::new(
        changes=@core.ChangeSet::of([
          @core.Change::insert(st.doc().length(), "x"),
        ]),
        annotations=[UserEvent("input.paste")],
      ),
    )
  }
  assert_eq(st.doc().to_string().length(), edits)
  let history = st.field(history_field)
  assert_eq(history.done.length(), history_max_groups)
  assert_eq(history.undone.length(), 0)
  assert_eq(history.done[0].before.to_string(), "xxxxx")
  assert_eq(
    history.done[history.done.length() - 1].after.to_string(),
    st.doc().to_string(),
  )
}

///|
test "field init reads earlier field in definition order" {
  let a : StateField[Int] = StateField::new(init=fn(_) { 20 })
  let b : StateField[Int] = StateField::new(init=fn(state) {
    state.field(a) + 2
  })
  let st = EditorState::create(config=[a.extension(), b.extension()])
  assert_eq(st.field(a), 20)
  assert_eq(st.field(b), 22)
}

///|
/// A field whose `init` reads a field that comes later in the configuration
/// (i.e. is still waiting to be initialized) aborts with a cycle diagnostic.
test "panic field init reads later field aborts" {
  let later : StateField[Int] = StateField::new(init=fn(_) { 1 })
  let earlier : StateField[Int] = StateField::new(init=fn(state) {
    state.field(later)
  })
  let _ = EditorState::create(config=[earlier.extension(), later.extension()])
}

///|
test "transaction caches new document" {
  let st = EditorState::create(doc=@core.Text::of("abc"))
  let tr = st.update(
    TransactionSpec::new(
      changes=@core.ChangeSet::of([@core.Change::insert(0, "x")]),
    ),
  )
  assert_eq(tr.new_doc().to_string(), "xabc")
  assert_eq(tr.new_doc().to_string(), "xabc")
  assert_eq(tr.state().doc().to_string(), "xabc")
}
