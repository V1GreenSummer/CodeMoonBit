///|
/// Transaction annotations, used to tag transactions with metadata.
pub(all) enum Annotation {
  UserEvent(String)
  AddToHistory(Bool)
  Remote(Bool)
  ScrollIntoView(Bool)
}

///|
pub struct EffectEntry {
  priv id : Int
  priv read : () -> Unit
}

///|
/// A typed state effect definition. Create one with `StateEffect::define`,
/// produce entries with `effect.of(value)`, and read them from a transaction
/// with `tr.effects(effect)`.
pub struct StateEffect[T] {
  priv id : Int
  priv mut holder : T?
}

///|
pub fn[T] StateEffect::new() -> StateEffect[T] {
  { id: fresh_state_id(), holder: None, }
}

///|
pub fn[T] StateEffect::id(self : StateEffect[T]) -> Int {
  self.id
}

///|
pub fn[T] StateEffect::of(self : StateEffect[T], value : T) -> EffectEntry {
  let effect = self
  { id: self.id, read: fn() { effect.holder = Some(value) }, }
}

///|
pub(all) struct TransactionSpec {
  changes : @core.ChangeSet?
  selection : @core.EditorSelection?
  effects : Array[EffectEntry]
  annotations : Array[Annotation]
  scroll_into_view : Bool?
}

///|
pub fn TransactionSpec::new(
  changes? : @core.ChangeSet,
  selection? : @core.EditorSelection,
  effects? : Array[EffectEntry] = [],
  annotations? : Array[Annotation] = [],
  scroll_into_view? : Bool,
) -> TransactionSpec {
  { changes, selection, effects, annotations, scroll_into_view, }
}

///|
/// An immutable description of a state update.
pub struct Transaction {
  priv start : EditorState
  priv changes : @core.ChangeSet
  priv selection : @core.EditorSelection
  priv effects : Array[EffectEntry]
  priv annotations : Array[Annotation]
  priv scroll_into_view : Bool
  priv mut computed : EditorState?
  priv mut cached_new_doc : @core.Text?
}

///|
pub fn Transaction::start_state(self : Transaction) -> EditorState {
  self.start
}

///|
pub fn Transaction::changes(self : Transaction) -> @core.ChangeSet {
  self.changes
}

///|
pub fn Transaction::selection(self : Transaction) -> @core.EditorSelection {
  self.selection
}

///|
pub fn Transaction::new_doc(self : Transaction) -> @core.Text {
  match self.cached_new_doc {
    Some(doc) => doc
    None => {
      let doc = self.changes.apply(self.start.doc())
      self.cached_new_doc = Some(doc)
      doc
    }
  }
}

///|
pub fn Transaction::scroll_into_view(self : Transaction) -> Bool {
  self.scroll_into_view
}

///|
pub fn[T] Transaction::effects(
  self : Transaction,
  effect : StateEffect[T],
) -> Array[T] {
  let result : Array[T] = []
  for entry in self.effects {
    if entry.id == effect.id {
      (entry.read)()
      match effect.holder {
        Some(v) => result.push(v)
        None => ()
      }
    }
  }
  result
}

///|
pub fn[T] Transaction::effect(
  self : Transaction,
  effect : StateEffect[T],
) -> T? {
  let values = self.effects(effect)
  if values.length() == 0 {
    None
  } else {
    Some(values[values.length() - 1])
  }
}

///|
pub fn Transaction::annotations(self : Transaction) -> Array[Annotation] {
  self.annotations.copy()
}

///|
pub fn Transaction::annotation(
  self : Transaction,
  which : Annotation,
) -> Annotation? {
  for a in self.annotations {
    if same_annotation_kind(a, which) {
      return Some(a)
    }
  }
  None
}

///|
fn same_annotation_kind(a : Annotation, b : Annotation) -> Bool {
  match (a, b) {
    (UserEvent(_), UserEvent(_)) => true
    (AddToHistory(_), AddToHistory(_)) => true
    (Remote(_), Remote(_)) => true
    (ScrollIntoView(_), ScrollIntoView(_)) => true
    _ => false
  }
}

///|
pub fn Transaction::user_event(self : Transaction) -> String? {
  for a in self.annotations {
    match a {
      UserEvent(name) => return Some(name)
      _ => ()
    }
  }
  None
}

///|
pub fn Transaction::add_to_history(self : Transaction) -> Bool {
  for a in self.annotations {
    match a {
      AddToHistory(flag) => return flag
      _ => ()
    }
  }
  !self.changes.is_empty()
}

///|
pub fn Transaction::is_remote(self : Transaction) -> Bool {
  for a in self.annotations {
    match a {
      Remote(flag) => return flag
      _ => ()
    }
  }
  false
}

///|
pub fn Transaction::state(self : Transaction) -> EditorState {
  match self.computed {
    Some(s) => s
    None => {
      let new_state = EditorState::after_transaction(
        self.start,
        self.new_doc(),
        self.selection,
        self,
      )
      self.computed = Some(new_state)
      new_state
    }
  }
}
