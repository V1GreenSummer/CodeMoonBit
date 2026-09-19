///|
/// A configured facet contribution inside an extension list.
pub enum ExtItem {
  FacetValue(Int, () -> Unit, () -> () -> Unit)
  Field(ErasedField)
}

///|
/// An extension list: the configuration of an editor state.
pub struct Extension {
  priv items : Array[ExtItem]
}

///|
pub fn Extension::empty() -> Extension {
  { items: [] }
}

///|
pub fn Extension::single(item : ExtItem) -> Extension {
  { items: [item] }
}

///|
pub fn Extension::of(extensions : Array[Extension]) -> Extension {
  let items : Array[ExtItem] = []
  for ext in extensions {
    items.append(ext.items)
  }
  { items, }
}

///|
pub fn Extension::items(self : Extension) -> Array[ExtItem] {
  self.items.copy()
}

///|
pub fn Extension::size(self : Extension) -> Int {
  self.items.length()
}

///|
pub impl Add for Extension with fn add(self : Extension, other : Extension) -> Extension {
  { items: self.items + other.items }
}

///|
pub fn Extension::fields(self : Extension) -> Array[ErasedField] {
  let result : Array[ErasedField] = []
  for item in self.items {
    match item {
      Field(f) => result.push(f)
      _ => ()
    }
  }
  let seen : Array[Int] = []
  let unique : Array[ErasedField] = []
  for f in result {
    if !seen.contains(f.id) {
      seen.push(f.id)
      unique.push(f)
    }
  }
  unique
}

///|
pub fn Extension::facet_items(
  self : Extension,
) -> Array[(Int, () -> Unit, () -> () -> Unit)] {
  let result : Array[(Int, () -> Unit, () -> () -> Unit)] = []
  for item in self.items {
    match item {
      FacetValue(id, input, finalize) => result.push((id, input, finalize))
      _ => ()
    }
  }
  result
}
