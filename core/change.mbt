///|
/// A single replacement: the half-open range `[from, to)` of the old document
/// is replaced by `text`.
pub(all) struct Change {
  from : Int
  to : Int
  text : String
} derive(Eq)

///|
pub fn Change::new(from : Int, to : Int, text : String) -> Change {
  if from <= to {
    { from, to, text }
  } else {
    { from: to, to: from, text }
  }
}

///|
pub fn Change::insert(pos : Int, text : String) -> Change {
  { from: pos, to: pos, text }
}

///|
pub fn Change::delete(from : Int, to : Int) -> Change {
  { from, to, text: "" }
}

///|
pub fn Change::length(self : Change) -> Int {
  self.to - self.from
}

///|
pub fn Change::new_length(self : Change) -> Int {
  self.text.length()
}

///|
pub fn Change::delta(self : Change) -> Int {
  self.text.length() - (self.to - self.from)
}

///|
pub fn Change::is_empty(self : Change) -> Bool {
  self.from == self.to && self.text.length() == 0
}

///|
/// An immutable, ordered set of changes, all expressed in the coordinates of
/// the original document.
pub(all) struct ChangeSet {
  priv changes : Array[Change]
}

///|
pub fn ChangeSet::empty() -> ChangeSet {
  { changes: [] }
}

///|
pub fn ChangeSet::of(changes : Array[Change]) -> ChangeSet {
  let sorted = changes.copy()
  sorted.sort_by(fn(a, b) {
    if a.from != b.from {
      a.from - b.from
    } else {
      a.to - b.to
    }
  })
  let result : Array[Change] = []
  for c in sorted {
    if c.is_empty() {
      continue
    }
    result.push(c)
  }
  { changes: result }
}

///|
pub fn ChangeSet::changes(self : ChangeSet) -> Array[Change] {
  self.changes.copy()
}

///|
pub fn ChangeSet::length(self : ChangeSet) -> Int {
  self.changes.length()
}

///|
pub fn ChangeSet::is_empty(self : ChangeSet) -> Bool {
  self.changes.length() == 0
}

///|
pub fn ChangeSet::iter(self : ChangeSet) -> Iter[Change] {
  self.changes.iter()
}

///|
pub fn ChangeSet::apply(self : ChangeSet, text : Text) -> Text {
  let mut result = text
  let mut i = self.changes.length() - 1
  while i >= 0 {
    let c = self.changes[i]
    result = result.replace(c.from, c.to, c.text)
    i = i - 1
  }
  result
}

///|
/// Returns the changes that transform the document after applying `self` back
/// into the original document.
pub fn ChangeSet::invert(self : ChangeSet, text : Text) -> ChangeSet {
  let inverted : Array[Change] = []
  let mut delta = 0
  for c in self.changes {
    let pos = c.from + delta
    let old = text.slice(c.from, c.to)
    inverted.push({ from: pos, to: pos + c.text.length(), text: old })
    delta = delta + c.delta()
  }
  { changes: inverted }
}

///|
/// Maps a position in the original document through the change set.
/// `assoc` < 0 associates the position with the text before the change,
/// `assoc` >= 0 with the text after the change.
pub fn ChangeSet::map_pos(self : ChangeSet, pos : Int, assoc : Int) -> Int {
  let mut delta = 0
  for c in self.changes {
    if pos < c.from {
      return pos + delta
    }
    if pos > c.to {
      delta = delta + c.delta()
      continue
    }
    if c.from == c.to {
      if pos == c.from {
        return if assoc < 0 {
          pos + delta
        } else {
          pos + delta + c.text.length()
        }
      }
      delta = delta + c.delta()
      continue
    }
    if pos == c.from && assoc < 0 {
      return pos + delta
    }
    if pos == c.to && assoc < 0 {
      return c.from + delta
    }
    return c.from + delta + c.text.length()
  }
  pos + delta
}

///|
pub fn ChangeSet::map_range(
  self : ChangeSet,
  range : Range,
  assoc : Int,
) -> Range {
  let from = self.map_pos(range.from, -1)
  let to = self.map_pos(range.to, assoc)
  if from <= to {
    { from, to }
  } else {
    { from: to, to: from }
  }
}

///|
/// Returns the total length change of the document.
pub fn ChangeSet::delta(self : ChangeSet) -> Int {
  let mut delta = 0
  for c in self.changes {
    delta = delta + c.delta()
  }
  delta
}

///|
pub fn ChangeSet::map_pos_bias(self : ChangeSet, pos : Int, bias : Int) -> Int {
  if bias < 0 {
    self.map_pos(pos, -1)
  } else {
    self.map_pos(pos, 1)
  }
}

///|
test "changeset apply single" {
  let t = Text::of("hello world")
  let cs = ChangeSet::of([Change::new(6, 11, "moonbit")])
  let t2 = cs.apply(t)
  assert_eq(t2.to_string(), "hello moonbit")
  assert_eq(cs.delta(), 2)
}

///|
test "changeset apply multiple" {
  let t = Text::of("abc")
  let cs = ChangeSet::of([Change::new(0, 1, "X"), Change::new(2, 3, "Y")])
  let t2 = cs.apply(t)
  assert_eq(t2.to_string(), "XbY")
}

///|
test "changeset invert roundtrip" {
  let t = Text::of("hello world")
  let cs = ChangeSet::of([Change::new(0, 5, "HI"), Change::insert(11, "!")])
  let t2 = cs.apply(t)
  let inv = cs.invert(t)
  let t3 = inv.apply(t2)
  assert_eq(t3.to_string(), t.to_string())
}

///|
test "changeset map_pos" {
  let cs = ChangeSet::of([Change::new(2, 4, "XYZ")])
  assert_eq(cs.map_pos(0, 1), 0)
  assert_eq(cs.map_pos(1, 1), 1)
  assert_eq(cs.map_pos(2, 1), 5)
  assert_eq(cs.map_pos(3, 1), 5)
  assert_eq(cs.map_pos(4, -1), 2)
  assert_eq(cs.map_pos(6, 1), 7)
}

///|
test "changeset map_pos insertion" {
  let cs = ChangeSet::of([Change::insert(2, "ab")])
  assert_eq(cs.map_pos(2, -1), 2)
  assert_eq(cs.map_pos(2, 1), 4)
  assert_eq(cs.map_pos(3, 1), 5)
}

///|
test "changeset map range" {
  let cs = ChangeSet::of([Change::new(0, 2, "")])
  let r = cs.map_range(Range::new(1, 3), 1)
  assert_eq(r.from, 0)
  assert_eq(r.to, 1)
}
