///|
/// A search query: either a literal needle or a small regular expression.
pub struct SearchQuery {
  text : String
  case_sensitive : Bool
  whole_word : Bool
  regex : Bool
} derive(Eq)

///|
pub fn SearchQuery::new(
  text~ : String,
  case_sensitive? : Bool = false,
  whole_word? : Bool = false,
  regex? : Bool = false,
) -> SearchQuery {
  { text, case_sensitive, whole_word, regex }
}

///|
/// Finds all (non-overlapping) matches of `query` in `doc`.
///
/// Offsets are UTF-16 code units. Matches are returned in document order and
/// at most `limit` of them (a non-positive `limit` means unlimited).
pub fn find_matches(
  doc : @core.Text,
  query : SearchQuery,
  limit? : Int = 1000,
) -> Array[@core.Range] {
  if query.text == "" {
    return []
  }
  let content = doc.to_string()
  if query.regex {
    find_regex_matches(content, query, limit)
  } else {
    find_literal_matches(content, query, limit)
  }
}

///|
fn clamp_code(value : Int, low : Int, high : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
fn code_unit(s : String, index : Int) -> Int {
  s.unsafe_get(index).to_int()
}

///|
fn is_word_code(code : Int) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 95
}

///|
fn lower_code(code : Int) -> Int {
  if code >= 65 && code <= 90 {
    code + 32
  } else {
    code
  }
}

///|
fn upper_code(code : Int) -> Int {
  if code >= 97 && code <= 122 {
    code - 32
  } else {
    code
  }
}

///|
fn units_equal(a : Int, b : Int, case_sensitive : Bool) -> Bool {
  if case_sensitive {
    a == b
  } else {
    lower_code(a) == lower_code(b)
  }
}

///|
fn word_boundaries(s : String, from : Int, to : Int) -> Bool {
  let before = from > 0 && is_word_code(code_unit(s, from - 1))
  let after = to < s.length() && is_word_code(code_unit(s, to))
  !before && !after
}

///|
fn literal_eq_at(
  s : String,
  at : Int,
  needle : String,
  case_sensitive : Bool,
) -> Bool {
  let n = needle.length()
  for i = 0; i < n; i = i + 1 {
    if !units_equal(code_unit(s, at + i), code_unit(needle, i), case_sensitive) {
      return false
    }
  }
  true
}

///|
fn find_literal_matches(
  content : String,
  query : SearchQuery,
  limit : Int,
) -> Array[@core.Range] {
  let result : Array[@core.Range] = []
  let n = query.text.length()
  let length = content.length()
  let mut i = 0
  while i + n <= length && (limit <= 0 || result.length() < limit) {
    if literal_eq_at(content, i, query.text, query.case_sensitive) &&
      (!query.whole_word || word_boundaries(content, i, i + n)) {
      result.push(@core.Range::new(i, i + n))
      i = i + n
    } else {
      i = i + 1
    }
  }
  result
}
