///|
/// An immutable editor state: document, selection, configured extensions and
/// computed state field values.
pub struct EditorState {
  priv doc : @core.Text
  priv selection : @core.EditorSelection
  priv fields : Array[ErasedField]
  priv field_slots : Array[() -> Unit]
  priv facet_slots : Array[(Int, () -> Unit)]
  priv extensions : Extension
}

///|
pub fn EditorState::create(
  config? : Array[Extension] = [],
  doc? : @core.Text,
  selection? : @core.EditorSelection,
) -> EditorState {
  let text = match doc {
    Some(d) => d
    None => @core.Text::empty()
  }
  let sel = match selection {
    Some(s) => s
    None => @core.EditorSelection::cursor(0)
  }
  let extensions = Extension::of(config)
  let facet_items = extensions.facet_items()
  for item in facet_items {
    let (_, input, _) = item
    input()
  }
  let facet_slots : Array[(Int, () -> Unit)] = []
  let finalized : Array[Int] = []
  for item in facet_items {
    let (id, _, finalize) = item
    if !finalized.contains(id) {
      finalized.push(id)
      facet_slots.push((id, finalize()))
    }
  }
  let fields = extensions.fields()
  let field_slots : Array[() -> Unit] = []
  for _ in fields {
    field_slots.push(fn() {
      abort(
        "state field dependency is not initialized yet (cyclic state field dependency)",
      )
    })
  }
  for i = 0; i < fields.length(); i = i + 1 {
    let partial : EditorState = {
      doc: text,
      selection: sel,
      fields,
      field_slots,
      facet_slots,
      extensions,
    }
    field_slots[i] = (fields[i].init_slot)(partial)
  }
  { doc: text, selection: sel, fields, field_slots, facet_slots, extensions, }
}

///|
pub fn EditorState::doc(self : EditorState) -> @core.Text {
  self.doc
}

///|
pub fn EditorState::selection(self : EditorState) -> @core.EditorSelection {
  self.selection
}

///|
pub fn EditorState::extensions(self : EditorState) -> Extension {
  self.extensions
}

///|
pub fn EditorState::length(self : EditorState) -> Int {
  self.doc.length()
}

///|
pub fn EditorState::line_count(self : EditorState) -> Int {
  self.doc.lines()
}

///|
pub fn EditorState::line(self : EditorState, line : Int) -> String {
  self.doc.line(line)
}

///|
pub fn EditorState::to_string(self : EditorState) -> String {
  self.doc.to_string()
}

///|
pub fn EditorState::slice(self : EditorState, from : Int, to : Int) -> String {
  self.doc.slice(from, to)
}

///|
fn EditorState::field_slot(self : EditorState, id : Int) -> (() -> Unit)? {
  for i = 0; i < self.fields.length(); i = i + 1 {
    if self.fields[i].id == id {
      return Some(self.field_slots[i])
    }
  }
  None
}

///|
pub fn EditorState::has_field(self : EditorState, id : Int) -> Bool {
  self.field_slot(id) is Some(_)
}

///|
fn EditorState::facet_slot(self : EditorState, id : Int) -> (() -> Unit)? {
  for entry in self.facet_slots {
    let (fid, slot) = entry
    if fid == id {
      return Some(slot)
    }
  }
  None
}

///|
/// Creates a new state with the given document and selection, updating every
/// active state field with the transaction.
fn EditorState::after_transaction(
  start : EditorState,
  doc : @core.Text,
  selection : @core.EditorSelection,
  tr : Transaction,
) -> EditorState {
  let field_slots : Array[() -> Unit] = []
  for i = 0; i < start.fields.length(); i = i + 1 {
    let field = start.fields[i]
    let old_slot = start.field_slots[i]
    match field.update_slot {
      Some(update_slot) => {
        old_slot()
        field_slots.push(update_slot(tr))
      }
      None => field_slots.push(old_slot)
    }
  }
  {
    doc,
    selection,
    fields: start.fields,
    field_slots,
    facet_slots: start.facet_slots,
    extensions: start.extensions,
  }
}

///|
/// Starts a state update and returns the (lazily applied) transaction.
pub fn EditorState::update(
  self : EditorState,
  spec : TransactionSpec,
) -> Transaction {
  let changes = match spec.changes {
    Some(c) => c
    None => @core.ChangeSet::empty()
  }
  let selection = match spec.selection {
    Some(s) => s
    None => self.selection.map(changes)
  }
  {
    start: self,
    changes,
    selection,
    effects: spec.effects,
    annotations: spec.annotations,
    scroll_into_view: match spec.scroll_into_view {
      Some(v) => v
      None => false
    },
    computed: None,
    cached_new_doc: None,
  }
}

///|
/// Updates the state and returns the resulting state directly.
pub fn EditorState::apply(
  self : EditorState,
  spec : TransactionSpec,
) -> EditorState {
  self.update(spec).state()
}

///|
pub fn EditorState::update_doc(
  self : EditorState,
  doc : @core.Text,
) -> EditorState {
  {
    doc,
    selection: @core.EditorSelection::cursor(0),
    fields: self.fields,
    field_slots: self.field_slots,
    facet_slots: self.facet_slots,
    extensions: self.extensions,
  }
}
