///|
/// An update definition for state fields.
pub struct StateField[T] {
  priv id : Int
  priv init : (EditorState) -> T
  priv update : ((T, Transaction) -> T)?
  priv mut holder : T?
}

///|
pub fn[T] StateField::new(
  init~ : (EditorState) -> T,
  update? : (T, Transaction) -> T,
) -> StateField[T] {
  { id: fresh_state_id(), init, update, holder: None }
}

///|
pub fn[T] StateField::id(self : StateField[T]) -> Int {
  self.id
}

///|
/// The type-erased runtime representation of a state field.
pub struct ErasedField {
  priv id : Int
  priv init_slot : (EditorState) -> () -> Unit
  priv update_slot : ((Transaction) -> () -> Unit)?
}

///|
fn[T] StateField::erase(self : StateField[T]) -> ErasedField {
  let field = self
  let init_slot : (EditorState) -> () -> Unit = fn(state) {
    let value = (field.init)(state)
    let slot : () -> Unit = fn() { field.holder = Some(value) }
    slot
  }
  let update_slot : ((Transaction) -> () -> Unit)? = match self.update {
    Some(update_fn) =>
      Some(fn(tr) {
        let old = match field.holder {
          Some(v) => v
          None => (field.init)(tr.start_state())
        }
        let value = update_fn(old, tr)
        let slot : () -> Unit = fn() { field.holder = Some(value) }
        slot
      })
    None => None
  }
  { id: self.id, init_slot, update_slot }
}

///|
pub fn[T] StateField::extension(self : StateField[T]) -> Extension {
  Extension::single(ExtItem::Field(self.erase()))
}

///|
/// Reads the value of a state field from the given state.
pub fn[T] EditorState::field(self : EditorState, field : StateField[T]) -> T {
  match self.field_slot(field.id) {
    Some(slot) => {
      slot()
      match field.holder {
        Some(v) => v
        None => abort("state field value not initialized")
      }
    }
    None => abort("state field is not part of this state configuration")
  }
}
