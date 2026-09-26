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
  { lines: [""], starts: [0], len: 0, }
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
  { lines, starts, len, }
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
/// True when `pos` is a legal offset, i.e. it does not fall between a high
/// surrogate and its low surrogate.
pub fn Text::is_char_boundary(self : Text, pos : Int) -> Bool {
  if pos <= 0 || pos >= self.len {
    return true
  }
  let (line, col) = self.line_col(pos)
  let s = self.lines[line]
  if col == 0 || col == s.length() {
    return true
  }
  let prev = s.unsafe_get(col - 1).to_int()
  let next = s.unsafe_get(col).to_int()
  !(prev >= 0xD800 && prev <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF)
}

///|
/// Snaps an offset down to the nearest legal character boundary.
pub fn Text::snap_pos_left(self : Text, pos : Int) -> Int {
  let p = self.clip_pos(pos)
  let mut result = p
  while result > 0 && !self.is_char_boundary(result) {
    result = result - 1
  }
  result
}

///|
/// Snaps an offset up to the nearest legal character boundary.
pub fn Text::snap_pos_right(self : Text, pos : Int) -> Int {
  let p = self.clip_pos(pos)
  let mut result = p
  while result < self.len && !self.is_char_boundary(result) {
    result = result + 1
  }
  result
}

///|
pub fn Text::slice(self : Text, from : Int, to : Int) -> String {
  let cf = self.clip_pos(from)
  let ct = self.clip_pos(to)
  if cf >= ct {
    return ""
  }
  let f = self.snap_pos_left(cf)
  let t = self.snap_pos_right(ct)
  if f >= t {
    return ""
  }
  let (fl, fc) = self.line_col(f)
  let (tl, tc) = self.line_col(t)
  if fl == tl {
    return self.lines[fl][fc:tc].to_owned()
  }
  let buf = StringBuilder()
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
  let f0 = if from < 0 {
    0
  } else if from > s.length() {
    s.length()
  } else {
    from
  }
  let t0 = if to < f0 { f0 } else if to > s.length() { s.length() } else { to }
  if f0 >= t0 {
    return ""
  }
  let f = if self.is_line_boundary(line, f0) { f0 } else { f0 - 1 }
  let t = if self.is_line_boundary(line, t0) { t0 } else { t0 + 1 }
  if f >= t {
    return ""
  }
  s[f:t].to_owned()
}

///|
fn Text::is_line_boundary(self : Text, line : Int, col : Int) -> Bool {
  let s = self.lines[line]
  if col <= 0 || col >= s.length() {
    return true
  }
  let prev = s.unsafe_get(col - 1).to_int()
  let next = s.unsafe_get(col).to_int()
  !(prev >= 0xD800 && prev <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF)
}

///|
pub fn Text::to_string(self : Text) -> String {
  if self.lines.length() == 1 {
    return self.lines[0]
  }
  let buf = StringBuilder()
  buf.write_string(self.lines[0])
  for i = 1; i < self.lines.length(); i = i + 1 {
    buf.write_char('\n')
    buf.write_string(self.lines[i])
  }
  buf.to_string()
}

///|
pub fn Text::replace(self : Text, from : Int, to : Int, text : String) -> Text {
  let cf = self.clip_pos(from)
  let ct = self.clip_pos(to)
  let f = self.snap_pos_left(cf)
  let t = if cf == ct {
    f
  } else {
    let snapped = self.snap_pos_right(ct)
    if snapped < f {
      f
    } else {
      snapped
    }
  }
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
  { lines: new_lines, starts: new_starts, len, }
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

///|
test "text surrogate boundaries" {
  let t = Text::of("😀b")
  assert_eq(t.length(), 3)
  assert_false(t.is_char_boundary(1))
  assert_true(t.is_char_boundary(0))
  assert_true(t.is_char_boundary(2))
  assert_eq(t.snap_pos_left(1), 0)
  assert_eq(t.snap_pos_right(1), 2)
  assert_eq(t.slice(1, 1), "")
  assert_eq(t.slice(1, 2), "😀")
  assert_eq(t.slice(1, 3), "😀b")
  let t2 = t.replace(1, 1, "x")
  assert_eq(t2.to_string(), "x😀b")
  let t3 = t.replace(0, 1, "")
  assert_eq(t3.to_string(), "b")
  assert_eq(t.line_slice(0, 1, 2), "😀")
  assert_eq(t.line_slice(0, 1, 1), "")
}

///|
test "text replace at legal boundaries is unchanged" {
  let t = Text::of("hello world")
  assert_eq(t.replace(5, 5, ",").to_string(), "hello, world")
  assert_eq(t.replace(0, 5, "hi").to_string(), "hi world")
}
