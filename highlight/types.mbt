///|
/// The syntactic class of a highlighted span.
pub enum TokenType {
  Keyword
  TypeName
  VariableName
  PropertyName
  Atom
  Number
  String
  Comment
  Operator
  Punctuation
  Meta
  Tag
  Attribute
  Invalid
} derive(Eq, Hash, Debug)

///|
pub extend TokenType with Eq::{not_equal, equal}

///|
pub extend TokenType with Hash::{hash, hash_combine}

///|
pub extend TokenType with Debug::{to_repr}

///|
/// A highlighted span of a single line, in line-relative UTF-16 code units.
pub struct Token {
  from : Int
  to : Int
  typ : TokenType
} derive(Eq, Debug)

///|
pub extend Token with Eq::{not_equal, equal}

///|
pub extend Token with Debug::{to_repr}
