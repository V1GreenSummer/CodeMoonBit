///|
/// View decorations supplied by the editor extension layer.
pub(all) enum Decoration {
  Mark(@core.Range, String)
  Line(Int, String)
  Widget(Int, String, String)
  GutterMarker(Int, String)
  Fold(Int)
  Foldable(Int)
}

///|
pub(all) struct ViewOptions {
  line_numbers : Bool
  line_wrapping : Bool
  tab_size : Int
  read_only : Bool
  theme : String
  font : String
  line_height : Double
  language_name : String
}

///|
pub fn ViewOptions::default() -> ViewOptions {
  {
    line_numbers: true,
    line_wrapping: false,
    tab_size: 4,
    read_only: false,
    theme: "light",
    font: "14px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
    line_height: 20.0,
    language_name: "plain",
  }
}

///|
pub fn ViewOptions::with_line_numbers(
  self : ViewOptions,
  value : Bool,
) -> ViewOptions {
  {
    line_numbers: value,
    line_wrapping: self.line_wrapping,
    tab_size: self.tab_size,
    read_only: self.read_only,
    theme: self.theme,
    font: self.font,
    line_height: self.line_height,
    language_name: self.language_name,
  }
}

///|
pub fn ViewOptions::with_line_wrapping(
  self : ViewOptions,
  value : Bool,
) -> ViewOptions {
  {
    line_numbers: self.line_numbers,
    line_wrapping: value,
    tab_size: self.tab_size,
    read_only: self.read_only,
    theme: self.theme,
    font: self.font,
    line_height: self.line_height,
    language_name: self.language_name,
  }
}

///|
pub fn ViewOptions::with_read_only(
  self : ViewOptions,
  value : Bool,
) -> ViewOptions {
  {
    line_numbers: self.line_numbers,
    line_wrapping: self.line_wrapping,
    tab_size: self.tab_size,
    read_only: value,
    theme: self.theme,
    font: self.font,
    line_height: self.line_height,
    language_name: self.language_name,
  }
}

///|
pub fn ViewOptions::with_tab_size(
  self : ViewOptions,
  value : Int,
) -> ViewOptions {
  {
    line_numbers: self.line_numbers,
    line_wrapping: self.line_wrapping,
    tab_size: value,
    read_only: self.read_only,
    theme: self.theme,
    font: self.font,
    line_height: self.line_height,
    language_name: self.language_name,
  }
}

///|
pub fn ViewOptions::with_language_name(
  self : ViewOptions,
  value : String,
) -> ViewOptions {
  {
    line_numbers: self.line_numbers,
    line_wrapping: self.line_wrapping,
    tab_size: self.tab_size,
    read_only: self.read_only,
    theme: self.theme,
    font: self.font,
    line_height: self.line_height,
    language_name: value,
  }
}

///|
pub fn ViewOptions::with_theme(
  self : ViewOptions,
  value : String,
) -> ViewOptions {
  {
    line_numbers: self.line_numbers,
    line_wrapping: self.line_wrapping,
    tab_size: self.tab_size,
    read_only: self.read_only,
    theme: value,
    font: self.font,
    line_height: self.line_height,
    language_name: self.language_name,
  }
}

///|
pub fn ViewOptions::with_font(
  self : ViewOptions,
  value : String,
) -> ViewOptions {
  {
    line_numbers: self.line_numbers,
    line_wrapping: self.line_wrapping,
    tab_size: self.tab_size,
    read_only: self.read_only,
    theme: self.theme,
    font: value,
    line_height: self.line_height,
    language_name: self.language_name,
  }
}

///|
pub fn ViewOptions::with_line_height(
  self : ViewOptions,
  value : Double,
) -> ViewOptions {
  {
    line_numbers: self.line_numbers,
    line_wrapping: self.line_wrapping,
    tab_size: self.tab_size,
    read_only: self.read_only,
    theme: self.theme,
    font: self.font,
    line_height: value,
    language_name: self.language_name,
  }
}
