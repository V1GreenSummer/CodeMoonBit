///|
/// An immutable text document stored as an array of lines (without line
/// terminators). Offsets use UTF-16 code units, like JavaScript strings.
pub(all) struct Text {
  priv lines : Array[String]
  priv starts : Array[Int]
  priv len : Int
}

///|
pub fn Text::empty() -> Text {
  { lines: [""], starts: [0], len: 0 }
}

///|
pub fn Text::of(content : String) -> Text {
  let lines = content.split("\n").map(fn(v) { v.to_owned() }).to_array()
  let starts : Array[Int] = []
  let mut len = 0
  for line in lines {
    starts.push(len)
    len = len + line.length() + 1
  }
  if lines.length() > 0 {
    len = len - 1
  }
  { lines, starts, len }
}

///|
pub fn Text::lines(self : Text) -> Int {
  self.lines.length()
}

///|
pub fn Text::line(self : Text, line : Int) -> String {
  self.lines[line]
}

///|
pub fn Text::line_length(self : Text, line : Int) -> Int {
  self.lines[line].length()
}

///|
pub fn Text::length(self : Text) -> Int {
  self.len
}

///|
pub fn Text::is_empty(self : Text) -> Bool {
  self.len == 0
}

///|
pub fn Text::line_start(self : Text, line : Int) -> Int {
  self.starts[line]
}

///|
pub fn Text::line_end(self : Text, line : Int) -> Int {
  self.starts[line] + self.lines[line].length()
}

///|
pub fn Text::line_at(self : Text, pos : Int) -> Int {
  let mut lo = 0
  let mut hi = self.lines.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if self.starts[mid] <= pos {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
pub fn Text::line_col(self : Text, pos : Int) -> (Int, Int) {
  let line = self.line_at(pos)
  (line, pos - self.starts[line])
}

///|
pub fn Text::pos(self : Text, line : Int, col : Int) -> Int {
  let l = if line < 0 {
    0
  } else if line >= self.lines.length() {
    self.lines.length() - 1
  } else {
    line
  }
  let c = if col < 0 {
    0
  } else if col > self.lines[l].length() {
    self.lines[l].length()
  } else {
    col
  }
  self.starts[l] + c
}

///|
pub fn Text::clip_pos(self : Text, pos : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > self.len {
    self.len
  } else {
    pos
  }
}

///|
pub fn Text::slice(self : Text, from : Int, to : Int) -> String {
  let f = self.clip_pos(from)
  let t = self.clip_pos(to)
  if f >= t {
    return ""
  }
  let (fl, fc) = self.line_col(f)
  let (tl, tc) = self.line_col(t)
  if fl == tl {
    return self.lines[fl][fc:tc].to_owned()
  }
  let buf = StringBuilder::new()
  buf.write_string(self.lines[fl][fc:].to_owned())
  for i = fl + 1; i < tl; i = i + 1 {
    buf.write_char('\n')
    buf.write_string(self.lines[i])
  }
  buf.write_char('\n')
  buf.write_string(self.lines[tl][:tc].to_owned())
  buf.to_string()
}

///|
pub fn Text::line_slice(
  self : Text,
  line : Int,
  from : Int,
  to : Int,
) -> String {
  let s = self.lines[line]
  let f = if from < 0 {
    0
  } else if from > s.length() {
    s.length()
  } else {
    from
  }
  let t = if to < f { f } else if to > s.length() { s.length() } else { to }
  s[f:t].to_owned()
}

///|
pub fn Text::to_string(self : Text) -> String {
  if self.lines.length() == 1 {
    return self.lines[0]
  }
  let buf = StringBuilder::new()
  buf.write_string(self.lines[0])
  for i = 1; i < self.lines.length(); i = i + 1 {
    buf.write_char('\n')
    buf.write_string(self.lines[i])
  }
  buf.to_string()
}

///|
pub fn Text::replace(self : Text, from : Int, to : Int, text : String) -> Text {
  let f = self.clip_pos(from)
  let t = if to < f { f } else if to > self.len { self.len } else { to }
  if f == t && text.length() == 0 {
    return self
  }
  let (fl, fc) = self.line_col(f)
  let (tl, tc) = self.line_col(t)
  let inserted = text.split("\n").map(fn(v) { v.to_owned() }).to_array()
  let new_lines : Array[String] = []
  for i = 0; i < fl; i = i + 1 {
    new_lines.push(self.lines[i])
  }
  if inserted.length() == 1 {
    let merged = self.lines[fl][:fc].to_owned() +
      inserted[0] +
      self.lines[tl][tc:].to_owned()
    new_lines.push(merged)
  } else {
    new_lines.push(self.lines[fl][:fc].to_owned() + inserted[0])
    for i = 1; i < inserted.length() - 1; i = i + 1 {
      new_lines.push(inserted[i])
    }
    new_lines.push(
      inserted[inserted.length() - 1] + self.lines[tl][tc:].to_owned(),
    )
  }
  for i = tl + 1; i < self.lines.length(); i = i + 1 {
    new_lines.push(self.lines[i])
  }
  let new_starts : Array[Int] = []
  let mut len = 0
  for line in new_lines {
    new_starts.push(len)
    len = len + line.length() + 1
  }
  len = len - 1
  { lines: new_lines, starts: new_starts, len }
}

///|
pub fn Text::append(self : Text, other : Text) -> Text {
  self.replace(self.len, self.len, other.to_string())
}

///|
pub fn Text::eq(self : Text, other : Text) -> Bool {
  if self.len != other.len || self.lines.length() != other.lines.length() {
    return false
  }
  for i = 0; i < self.lines.length(); i = i + 1 {
    if self.lines[i] != other.lines[i] {
      return false
    }
  }
  true
}

///|
pub fn Text::iter_lines(self : Text) -> Iter[String] {
  self.lines.iter()
}

///|
pub fn Text::substring(self : Text, from : Int, to : Int) -> String {
  self.slice(from, to)
}

///|
test "text basic mapping" {
  let t = Text::of("hello\nworld\n!")
  assert_eq(t.lines(), 3)
  assert_eq(t.length(), 13)
  assert_eq(t.line_start(0), 0)
  assert_eq(t.line_start(1), 6)
  assert_eq(t.line_start(2), 12)
  assert_eq(t.line_at(0), 0)
  assert_eq(t.line_at(6), 1)
  assert_eq(t.line_at(12), 2)
  assert_eq(t.line_col(6), (1, 0))
  assert_eq(t.line_col(8), (1, 2))
  assert_eq(t.pos(1, 2), 8)
}

///|
test "text slice and replace" {
  let t = Text::of("hello\nworld")
  assert_eq(t.slice(3, 8), "lo\nwo")
  assert_eq(t.line_slice(1, 1, 3), "or")
  let t2 = t.replace(3, 8, "LO\nWO")
  assert_eq(t2.to_string(), "helLO\nWOrld")
  let t3 = t.replace(5, 5, "\n")
  assert_eq(t3.to_string(), "hello\n\nworld")
  let t4 = t3.replace(5, 6, "")
  assert_eq(t4.to_string(), "hello\nworld")
  assert_eq(t4.length(), 11)
  let t5 = t3.replace(5, 7, "")
  assert_eq(t5.to_string(), "helloworld")
  assert_eq(t5.length(), 10)
}

///|
test "text append and eq" {
  let a = Text::of("ab")
  let b = Text::of("cd")
  let c = a.append(b)
  assert_eq(c.to_string(), "abcd")
  assert_true(c.eq(Text::of("abcd")))
  assert_false(c.eq(Text::of("abce")))
}

///|
test "text unicode code units" {
  let t = Text::of("a🤣b")
  assert_eq(t.length(), 4)
  assert_eq(t.line_length(0), 4)
  let t2 = t.replace(1, 3, "x")
  assert_eq(t2.to_string(), "axb")
}
