///|
/// A selection range with a fixed `anchor` and a moving `head`.
pub(all) struct SelectionRange {
  anchor : Int
  head : Int
} derive(Eq, Hash)

///|
pub fn SelectionRange::new(anchor : Int, head : Int) -> SelectionRange {
  { anchor, head }
}

///|
pub fn SelectionRange::cursor(pos : Int) -> SelectionRange {
  { anchor: pos, head: pos }
}

///|
pub fn SelectionRange::from(self : SelectionRange) -> Int {
  if self.anchor < self.head {
    self.anchor
  } else {
    self.head
  }
}

///|
pub fn SelectionRange::to(self : SelectionRange) -> Int {
  if self.anchor > self.head {
    self.anchor
  } else {
    self.head
  }
}

///|
pub fn SelectionRange::is_empty(self : SelectionRange) -> Bool {
  self.anchor == self.head
}

///|
pub fn SelectionRange::length(self : SelectionRange) -> Int {
  let d = self.head - self.anchor
  if d < 0 {
    -d
  } else {
    d
  }
}

///|
pub fn SelectionRange::eq(
  self : SelectionRange,
  other : SelectionRange,
) -> Bool {
  self.anchor == other.anchor && self.head == other.head
}

///|
pub fn SelectionRange::as_range(self : SelectionRange) -> Range {
  Range::new(self.anchor, self.head)
}

///|
pub fn SelectionRange::head_pos(self : SelectionRange) -> Int {
  self.head
}

///|
/// An ordered set of selection ranges plus the index of the main range.
pub(all) struct EditorSelection {
  priv ranges : Array[SelectionRange]
  priv main : Int
}

///|
pub fn EditorSelection::create(
  ranges : Array[SelectionRange],
  main : Int,
) -> EditorSelection {
  if ranges.length() == 0 {
    return { ranges: [SelectionRange::cursor(0)], main: 0 }
  }
  let m = if main < 0 {
    0
  } else if main >= ranges.length() {
    ranges.length() - 1
  } else {
    main
  }
  { ranges, main: m }
}

///|
pub fn EditorSelection::cursor(pos : Int) -> EditorSelection {
  EditorSelection::create([SelectionRange::cursor(pos)], 0)
}

///|
pub fn EditorSelection::single(anchor : Int, head : Int) -> EditorSelection {
  EditorSelection::create([SelectionRange::new(anchor, head)], 0)
}

///|
pub fn EditorSelection::ranges(self : EditorSelection) -> Array[SelectionRange] {
  self.ranges.copy()
}

///|
pub fn EditorSelection::range_count(self : EditorSelection) -> Int {
  self.ranges.length()
}

///|
pub fn EditorSelection::main_index(self : EditorSelection) -> Int {
  self.main
}

///|
pub fn EditorSelection::main_range(self : EditorSelection) -> SelectionRange {
  self.ranges[self.main]
}

///|
pub fn EditorSelection::set_main_index(
  self : EditorSelection,
  index : Int,
) -> EditorSelection {
  EditorSelection::create(self.ranges, index)
}

///|
pub fn EditorSelection::eq(
  self : EditorSelection,
  other : EditorSelection,
) -> Bool {
  if self.main != other.main || self.ranges.length() != other.ranges.length() {
    return false
  }
  for i = 0; i < self.ranges.length(); i = i + 1 {
    if !self.ranges[i].eq(other.ranges[i]) {
      return false
    }
  }
  true
}

///|
pub fn EditorSelection::add_range(
  self : EditorSelection,
  range : SelectionRange,
  main? : Bool = false,
) -> EditorSelection {
  let ranges = self.ranges.copy()
  ranges.push(range)
  EditorSelection::create(
    ranges,
    if main {
      ranges.length() - 1
    } else {
      self.main
    },
  )
}

///|
pub fn EditorSelection::map(
  self : EditorSelection,
  changes : ChangeSet,
  assoc? : Int = 1,
) -> EditorSelection {
  let mapped : Array[SelectionRange] = []
  for r in self.ranges {
    mapped.push({
      anchor: changes.map_pos(r.anchor, -1),
      head: changes.map_pos(r.head, assoc),
    })
  }
  { ranges: mapped, main: self.main }
}

///|
/// Merges overlapping selection ranges, keeping the main range when possible.
pub fn EditorSelection::normalized(self : EditorSelection) -> EditorSelection {
  let sorted = self.ranges.copy()
  let main_range = self.main_range()
  sorted.sort_by(fn(a, b) {
    let d = a.from() - b.from()
    if d != 0 {
      d
    } else {
      a.to() - b.to()
    }
  })
  let result : Array[SelectionRange] = []
  for r in sorted {
    let mut merged = false
    if result.length() > 0 {
      let prev = result[result.length() - 1]
      if prev.to() >= r.from() {
        if r.to() > prev.to() {
          let _ = result.pop()
          result.push({ anchor: prev.anchor, head: r.head })
        }
        merged = true
      }
    }
    if !merged {
      result.push(r)
    }
  }
  let mut main = 0
  for i = 0; i < result.length(); i = i + 1 {
    if result[i].eq(main_range) {
      main = i
      break
    }
  }
  EditorSelection::create(result, main)
}

///|
pub fn EditorSelection::is_cursor(self : EditorSelection) -> Bool {
  self.ranges.length() == 1 && self.ranges[0].is_empty()
}

///|
test "selection basics" {
  let sel = EditorSelection::cursor(5)
  assert_true(sel.is_cursor())
  assert_eq(sel.main_range().head, 5)
  let sel2 = sel.add_range(SelectionRange::new(3, 7))
  assert_eq(sel2.range_count(), 2)
  assert_eq(sel2.main_index(), 0)
}

///|
test "selection map" {
  let sel = EditorSelection::single(2, 5)
  let cs = ChangeSet::of([Change::insert(3, "XY")])
  let mapped = sel.map(cs)
  assert_eq(mapped.main_range().anchor, 2)
  assert_eq(mapped.main_range().head, 7)
}

///|
test "selection normalized merges" {
  let sel = EditorSelection::create(
    [
      SelectionRange::new(0, 3),
      SelectionRange::new(2, 6),
      SelectionRange::cursor(10),
    ],
    1,
  )
  let n = sel.normalized()
  assert_eq(n.range_count(), 2)
}
