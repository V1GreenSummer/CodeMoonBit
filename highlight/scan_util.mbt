///|
/// Code unit at `i` in `s`, or `-1` when out of bounds.
fn code_unit(s : String, i : Int) -> Int {
  if i < 0 || i >= s.length() {
    -1
  } else {
    s.unsafe_get(i).to_int()
  }
}

///|
/// Whether `pat` occurs in `s` starting at `pos`.
fn match_str(s : String, pos : Int, pat : String) -> Bool {
  let n = pat.length()
  if n == 0 || pos < 0 || pos + n > s.length() {
    return false
  }
  let mut i = 0
  while i < n {
    if s.unsafe_get(pos + i).to_int() != pat.unsafe_get(i).to_int() {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Whether the ASCII character `c` appears in `s`.
fn ch_in(s : String, c : Int) -> Bool {
  let mut i = 0
  while i < s.length() {
    if s.unsafe_get(i).to_int() == c {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn Scanner::matches(self : Scanner, pat : String) -> Bool {
  match_str(self.line, self.pos, pat)
}

///|
/// Whether every code unit before the cursor on this line is whitespace.
fn Scanner::only_ws_before(self : Scanner) -> Bool {
  let mut i = 0
  while i < self.pos {
    if !is_whitespace(self.line.unsafe_get(i).to_int()) {
      return false
    }
    i = i + 1
  }
  true
}
