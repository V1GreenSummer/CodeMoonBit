///|
/// The (small) regular expression AST used by `find_matches` when
/// `SearchQuery::regex` is set.
priv enum Re {
  Lit(Int)
  AnyChar
  Cls(Array[(Int, Int)], Bool)
  StartAnchor
  EndAnchor
  WordBoundary
  Alt(Array[Re])
  Cat(Array[Re])
  Rep(Re, Int, Int)
}

///|
fn word_ranges() -> Array[(Int, Int)] {
  [(48, 57), (65, 90), (95, 95), (97, 122)]
}

///|
fn space_ranges() -> Array[(Int, Int)] {
  [(9, 13), (32, 32)]
}

///|
fn complement_ranges(ranges : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let sorted = ranges.copy()
  sorted.sort_by(fn(a, b) {
    let (a_low, _) = a
    let (b_low, _) = b
    a_low - b_low
  })
  let result : Array[(Int, Int)] = []
  let mut next = 0
  for range in sorted {
    let (low, high) = range
    if low > next {
      result.push((next, low - 1))
    }
    if high + 1 > next {
      next = high + 1
    }
  }
  if next <= 65535 {
    result.push((next, 65535))
  }
  result
}

///|
priv struct RegexParser {
  pattern : String
  mut index : Int
  mut failed : Bool
}

///|
fn RegexParser::new(pattern : String) -> RegexParser {
  { pattern, index: 0, failed: false }
}

///|
fn RegexParser::eof(self : RegexParser) -> Bool {
  self.index >= self.pattern.length()
}

///|
fn RegexParser::peek(self : RegexParser) -> Int {
  if self.eof() {
    -1
  } else {
    self.pattern.unsafe_get(self.index).to_int()
  }
}

///|
fn RegexParser::advance(self : RegexParser) -> Int {
  let c = self.peek()
  if c >= 0 {
    self.index = self.index + 1
  }
  c
}

///|
fn RegexParser::eat(self : RegexParser, c : Int) -> Bool {
  if self.peek() == c {
    self.index = self.index + 1
    true
  } else {
    false
  }
}

///|
fn RegexParser::parse_alt(self : RegexParser) -> Re {
  let alternatives : Array[Re] = [self.parse_concat()]
  while self.eat(124) {
    alternatives.push(self.parse_concat())
  }
  if alternatives.length() == 1 {
    alternatives[0]
  } else {
    Alt(alternatives)
  }
}

///|
fn RegexParser::parse_concat(self : RegexParser) -> Re {
  let nodes : Array[Re] = []
  while !self.eof() && self.peek() != 124 && self.peek() != 41 {
    let atom = self.parse_atom()
    nodes.push(self.parse_quantifier(atom))
  }
  if nodes.length() == 1 {
    nodes[0]
  } else {
    Cat(nodes)
  }
}

///|
fn RegexParser::parse_quantifier(self : RegexParser, atom : Re) -> Re {
  let c = self.peek()
  if c == 42 {
    self.index = self.index + 1
    Rep(atom, 0, -1)
  } else if c == 43 {
    self.index = self.index + 1
    Rep(atom, 1, -1)
  } else if c == 63 {
    self.index = self.index + 1
    Rep(atom, 0, 1)
  } else {
    atom
  }
}

///|
fn RegexParser::parse_atom(self : RegexParser) -> Re {
  let c = self.advance()
  if c < 0 {
    Cat([])
  } else if c == 40 {
    let inner = self.parse_alt()
    if !self.eat(41) {
      self.failed = true
    }
    inner
  } else if c == 91 {
    self.parse_class()
  } else if c == 46 {
    AnyChar
  } else if c == 94 {
    StartAnchor
  } else if c == 36 {
    EndAnchor
  } else if c == 92 {
    self.parse_escape()
  } else {
    Lit(c)
  }
}

///|
fn RegexParser::parse_escape(self : RegexParser) -> Re {
  let c = self.advance()
  if c < 0 {
    self.failed = true
    Cat([])
  } else if c == 100 {
    Cls([(48, 57)], false)
  } else if c == 68 {
    Cls([(48, 57)], true)
  } else if c == 119 {
    Cls(word_ranges(), false)
  } else if c == 87 {
    Cls(word_ranges(), true)
  } else if c == 115 {
    Cls(space_ranges(), false)
  } else if c == 83 {
    Cls(space_ranges(), true)
  } else if c == 98 {
    WordBoundary
  } else if c == 110 {
    Lit(10)
  } else if c == 116 {
    Lit(9)
  } else if c == 114 {
    Lit(13)
  } else if c == 102 {
    Lit(12)
  } else if c == 118 {
    Lit(11)
  } else {
    Lit(c)
  }
}

///|
fn RegexParser::parse_class(self : RegexParser) -> Re {
  let ranges : Array[(Int, Int)] = []
  let mut negated = false
  if self.eat(94) {
    negated = true
  }
  let mut first = true
  let mut closed = false
  while !self.eof() {
    if self.peek() == 93 && !first {
      self.index = self.index + 1
      closed = true
      break
    }
    let item = self.parse_class_item()
    ranges.append(item)
    first = false
  }
  if !closed {
    self.failed = true
  }
  Cls(ranges, negated)
}

///|
fn RegexParser::parse_class_item(self : RegexParser) -> Array[(Int, Int)] {
  let c = self.advance()
  if c < 0 {
    self.failed = true
    return []
  }
  if c == 92 {
    return self.parse_class_escape()
  }
  if self.peek() == 45 &&
    self.index + 1 < self.pattern.length() &&
    self.pattern.unsafe_get(self.index + 1).to_int() != 93 {
    self.index = self.index + 1
    let high = self.advance()
    let high_code = if high == 92 { self.advance() } else { high }
    if high_code < 0 {
      self.failed = true
      return [(c, c)]
    }
    return [(c, high_code)]
  }
  [(c, c)]
}

///|
fn RegexParser::parse_class_escape(self : RegexParser) -> Array[(Int, Int)] {
  let c = self.advance()
  if c < 0 {
    self.failed = true
    []
  } else if c == 100 {
    [(48, 57)]
  } else if c == 68 {
    [(0, 47), (58, 65535)]
  } else if c == 119 {
    word_ranges()
  } else if c == 87 {
    complement_ranges(word_ranges())
  } else if c == 115 {
    space_ranges()
  } else if c == 83 {
    complement_ranges(space_ranges())
  } else if c == 110 {
    [(10, 10)]
  } else if c == 116 {
    [(9, 9)]
  } else if c == 114 {
    [(13, 13)]
  } else if c == 102 {
    [(12, 12)]
  } else if c == 118 {
    [(11, 11)]
  } else {
    [(c, c)]
  }
}

///|
fn parse_regex(pattern : String) -> Re? {
  let parser = RegexParser::new(pattern)
  let re = parser.parse_alt()
  if parser.failed || parser.index < pattern.length() {
    None
  } else {
    Some(re)
  }
}

///|
priv struct RegexMatcher {
  content : String
  length : Int
  case_sensitive : Bool
}

///|
fn RegexMatcher::new(content : String, case_sensitive : Bool) -> RegexMatcher {
  { content, length: content.length(), case_sensitive }
}

///|
fn RegexMatcher::unit(self : RegexMatcher, index : Int) -> Int {
  self.content.unsafe_get(index).to_int()
}

///|
fn range_hit(ranges : Array[(Int, Int)], code : Int) -> Bool {
  for range in ranges {
    let (low, high) = range
    if code >= low && code <= high {
      return true
    }
  }
  false
}

///|
fn class_hit(
  ranges : Array[(Int, Int)],
  code : Int,
  case_sensitive : Bool,
) -> Bool {
  if range_hit(ranges, code) {
    true
  } else if !case_sensitive &&
    (range_hit(ranges, lower_code(code)) || range_hit(ranges, upper_code(code))) {
    true
  } else {
    false
  }
}

///|
fn RegexMatcher::match_here(
  self : RegexMatcher,
  re : Re,
  pos : Int,
  k : (Int) -> Bool,
) -> Bool {
  match re {
    Lit(code) =>
      pos < self.length &&
      units_equal(self.unit(pos), code, self.case_sensitive) &&
      k(pos + 1)
    AnyChar => pos < self.length && self.unit(pos) != 10 && k(pos + 1)
    Cls(ranges, negated) =>
      pos < self.length &&
      class_hit(ranges, self.unit(pos), self.case_sensitive) != negated &&
      k(pos + 1)
    StartAnchor => (pos == 0 || self.unit(pos - 1) == 10) && k(pos)
    EndAnchor => (pos == self.length || self.unit(pos) == 10) && k(pos)
    WordBoundary => {
      let before = pos > 0 && is_word_code(self.unit(pos - 1))
      let after = pos < self.length && is_word_code(self.unit(pos))
      before != after && k(pos)
    }
    Alt(alternatives) => {
      let mut matched = false
      for alternative in alternatives {
        if self.match_here(alternative, pos, k) {
          matched = true
          break
        }
      }
      matched
    }
    Cat(nodes) => self.match_sequence(nodes, 0, pos, k)
    Rep(inner, min, max) => self.match_repeat(inner, 0, min, max, pos, k)
  }
}

///|
fn RegexMatcher::match_sequence(
  self : RegexMatcher,
  nodes : Array[Re],
  index : Int,
  pos : Int,
  k : (Int) -> Bool,
) -> Bool {
  if index >= nodes.length() {
    k(pos)
  } else {
    self.match_here(nodes[index], pos, fn(next) {
      self.match_sequence(nodes, index + 1, next, k)
    })
  }
}

///|
fn RegexMatcher::match_repeat(
  self : RegexMatcher,
  inner : Re,
  count : Int,
  min : Int,
  max : Int,
  pos : Int,
  k : (Int) -> Bool,
) -> Bool {
  let can_more = max < 0 || count < max
  if can_more {
    let more : (Int) -> Bool = fn(next) {
      if next == pos {
        if count + 1 >= min {
          k(pos)
        } else {
          self.match_repeat(inner, min, min, max, pos, k)
        }
      } else {
        self.match_repeat(inner, count + 1, min, max, next, k)
      }
    }
    if self.match_here(inner, pos, more) {
      return true
    }
  }
  count >= min && k(pos)
}

///|
fn find_regex_matches(
  content : String,
  query : SearchQuery,
  limit : Int,
) -> Array[@core.Range] {
  let result : Array[@core.Range] = []
  match parse_regex(query.text) {
    None => ()
    Some(re) => {
      let matcher = RegexMatcher::new(content, query.case_sensitive)
      let length = content.length()
      let mut start = 0
      while start <= length && (limit <= 0 || result.length() < limit) {
        let end_ref : Ref[Int] = { val: -1 }
        let matched = matcher.match_here(re, start, fn(pos) {
          end_ref.val = pos
          true
        })
        let end = end_ref.val
        if matched &&
          end > start &&
          (!query.whole_word || word_boundaries(content, start, end)) {
          result.push(@core.Range::new(start, end))
          start = end
        } else {
          start = start + 1
        }
      }
    }
  }
  result
}
