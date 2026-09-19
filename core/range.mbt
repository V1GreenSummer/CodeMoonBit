///|
pub(all) struct Range {
  from : Int
  to : Int
} derive(Eq, Hash)

///|
pub fn Range::new(from : Int, to : Int) -> Range {
  if from <= to {
    { from, to }
  } else {
    { from: to, to: from }
  }
}

///|
pub fn Range::empty(pos : Int) -> Range {
  { from: pos, to: pos }
}

///|
pub fn Range::length(self : Range) -> Int {
  self.to - self.from
}

///|
pub fn Range::is_empty(self : Range) -> Bool {
  self.from == self.to
}

///|
pub fn Range::contains(self : Range, pos : Int) -> Bool {
  self.from <= pos && pos <= self.to
}

///|
pub fn Range::contains_range(self : Range, other : Range) -> Bool {
  self.from <= other.from && other.to <= self.to
}

///|
pub fn Range::overlaps(self : Range, other : Range) -> Bool {
  self.from < other.to && other.from < self.to
}

///|
pub fn Range::touches(self : Range, other : Range) -> Bool {
  self.from <= other.to && other.from <= self.to
}

///|
pub fn Range::eq(self : Range, other : Range) -> Bool {
  self.from == other.from && self.to == other.to
}

///|
pub fn Range::map(self : Range, changes : ChangeSet, assoc? : Int = 1) -> Range {
  changes.map_range(self, assoc)
}

///|
/// An immutable set of sorted, non-overlapping, non-touching ranges.
pub(all) struct RangeSet {
  priv ranges : Array[Range]
}

///|
pub fn RangeSet::empty() -> RangeSet {
  { ranges: [] }
}

///|
pub fn RangeSet::of(ranges : Array[Range]) -> RangeSet {
  let sorted = ranges.copy()
  sorted.sort_by(fn(a, b) {
    if a.from != b.from {
      a.from - b.from
    } else {
      a.to - b.to
    }
  })
  let result : Array[Range] = []
  for r in sorted {
    if r.is_empty() {
      continue
    }
    match result.last() {
      Some(prev) if prev.to >= r.from =>
        if r.to > prev.to {
          let _ = result.pop()
          result.push({ from: prev.from, to: r.to })
        }
      _ => result.push(r)
    }
  }
  { ranges: result }
}

///|
pub fn RangeSet::ranges(self : RangeSet) -> Array[Range] {
  self.ranges.copy()
}

///|
pub fn RangeSet::size(self : RangeSet) -> Int {
  self.ranges.length()
}

///|
pub fn RangeSet::iter(self : RangeSet) -> Iter[Range] {
  self.ranges.iter()
}

///|
pub fn RangeSet::contains(self : RangeSet, pos : Int) -> Bool {
  for r in self.ranges {
    if r.from > pos {
      return false
    }
    if r.contains(pos) {
      return true
    }
  }
  false
}

///|
pub fn RangeSet::between(self : RangeSet, from : Int, to : Int) -> Array[Range] {
  let result : Array[Range] = []
  for r in self.ranges {
    if r.from > to {
      break
    }
    if r.to >= from {
      result.push({ from: r.from.max(from), to: r.to.min(to) })
    }
  }
  result
}

///|
pub fn RangeSet::update(
  self : RangeSet,
  add : Array[Range],
  filter : (Range) -> Bool,
) -> RangeSet {
  RangeSet::of(self.ranges.iter().filter(filter).to_array() + add)
}

///|
pub fn RangeSet::map(self : RangeSet, changes : ChangeSet) -> RangeSet {
  let result : Array[Range] = []
  for r in self.ranges {
    result.push(changes.map_range(r, 1))
  }
  RangeSet::of(result)
}

///|
test "range basics" {
  let r = Range::new(5, 2)
  assert_eq(r.from, 2)
  assert_eq(r.to, 5)
  assert_true(r.contains(3))
  assert_false(r.contains(1))
  assert_true(r.overlaps(Range::new(4, 8)))
  assert_false(r.overlaps(Range::new(5, 8)))
}

///|
test "rangeset normalize and merge" {
  let set = RangeSet::of([
    Range::new(0, 3),
    Range::new(2, 6),
    Range::new(8, 9),
    Range::new(9, 12),
    Range::new(11, 11),
    Range::new(20, 18),
  ])
  assert_eq(set.size(), 3)
  assert_true(set.contains(5))
  assert_true(set.contains(10))
  assert_false(set.contains(7))
  assert_true(set.contains(19))
  assert_false(set.contains(17))
}
