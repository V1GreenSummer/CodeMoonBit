///|
/// Monotonic id generator shared by facets, fields and effects.
let next_state_id : Ref[Int] = { val: 0, }

///|
pub fn fresh_state_id() -> Int {
  let id = next_state_id.val
  next_state_id.val = id + 1
  id
}

///|
/// A facet is a labeled, typed configuration value. Multiple extensions may
/// contribute values which are combined in extension order.
pub struct Facet[T] {
  priv id : Int
  priv default : () -> T
  priv combine : (T, T) -> T
  priv mut inputs : Array[() -> Unit]
  priv mut tmp : T?
  priv mut holder : T?
}

///|
pub fn[T] Facet::new(default~ : () -> T, combine~ : (T, T) -> T) -> Facet[T] {
  {
    id: fresh_state_id(),
    default,
    combine,
    inputs: [],
    tmp: None,
    holder: None,
  }
}

///|
pub fn[T] Facet::id(self : Facet[T]) -> Int {
  self.id
}

///|
pub fn[T] Facet::of(self : Facet[T], value : T) -> Extension {
  let facet = self
  let input : () -> Unit = fn() {
    let value = value
    facet.inputs.push(fn() { facet.tmp = Some(value) })
  }
  let finalize : () -> () -> Unit = fn() {
    let default_fn = facet.default
    let combine_fn = facet.combine
    let mut combined = default_fn()
    for f in facet.inputs {
      f()
      match facet.tmp {
        Some(v) => combined = combine_fn(combined, v)
        None => ()
      }
    }
    facet.inputs = []
    facet.tmp = None
    let slot : () -> Unit = fn() { facet.holder = Some(combined) }
    slot
  }
  Extension::single(ExtItem::FacetValue(self.id, input, finalize))
}

///|
pub fn[T] Facet::of_array(self : Facet[T], values : Array[T]) -> Extension {
  let mut ext = Extension::empty()
  for v in values {
    ext = ext + self.of(v)
  }
  ext
}

///|
/// Reads the facet value from a state.
pub fn[T] EditorState::facet(self : EditorState, facet : Facet[T]) -> T {
  match self.facet_slot(facet.id) {
    Some(slot) => {
      slot()
      match facet.holder {
        Some(v) => v
        None => (facet.default)()
      }
    }
    None => (facet.default)()
  }
}
