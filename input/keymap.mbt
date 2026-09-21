///|
/// Shift modifier bit for `KeyEvent.mods`.
pub let mod_shift : Int = 1

///|
/// Ctrl modifier bit for `KeyEvent.mods`.
pub let mod_ctrl : Int = 2

///|
/// Alt modifier bit for `KeyEvent.mods`.
pub let mod_alt : Int = 4

///|
/// Meta (Cmd/Win) modifier bit for `KeyEvent.mods`.
pub let mod_meta : Int = 8

///|
/// Platform bit for `KeyEvent.mods`: when set, `Mod` bindings map to the meta
/// key (Apple platforms) instead of ctrl. Hosts set this bit together with the
/// actual modifier bits of the event.
pub let mod_platform : Int = 16

///|
/// A normalized keyboard event as delivered by the DOM layer.
pub(all) struct KeyEvent {
  key : String
  code : String
  mods : Int
} derive(Eq)

///|
/// A named command bound to a normalized key spec such as `"Ctrl-z"` or
/// `"Shift-Alt-ArrowUp"`. `shift` is an optional variant run when shift is
/// held and the plain binding matched.
pub(all) struct KeyBinding {
  key : String
  run : (@state.EditorState) -> @state.TransactionSpec?
  shift : (@state.EditorState) -> @state.TransactionSpec?
}

///|
/// An ordered list of key bindings.
pub struct Keymap {
  priv bindings : Array[KeyBinding]
}

///|
pub fn Keymap::new() -> Keymap {
  { bindings: [] }
}

///|
pub fn Keymap::bind(self : Keymap, bindings : Array[KeyBinding]) -> Keymap {
  { bindings: self.bindings + bindings }
}

///|
pub fn Keymap::add(self : Keymap, binding : KeyBinding) -> Keymap {
  { bindings: self.bindings + [binding] }
}

///|
pub fn Keymap::bindings(self : Keymap) -> Array[KeyBinding] {
  self.bindings.copy()
}

///|
/// Normalizes a raw event key: `"A"` becomes `"a"`, `" "` becomes `"Space"`,
/// special key names are kept verbatim.
pub fn normalize_key_name(key : String) -> String {
  if key == " " {
    return "Space"
  }
  if key.length() == 1 {
    return key.to_lower()
  }
  key
}

///|
/// Builds the canonical spec string for an event, e.g. `"Shift-Ctrl-Alt-Meta-z"`.
pub fn binding_spec(event : KeyEvent) -> String {
  let sb = StringBuilder::new()
  if (event.mods & mod_shift) != 0 {
    sb.write_string("Shift-")
  }
  if (event.mods & mod_ctrl) != 0 {
    sb.write_string("Ctrl-")
  }
  if (event.mods & mod_alt) != 0 {
    sb.write_string("Alt-")
  }
  if (event.mods & mod_meta) != 0 {
    sb.write_string("Meta-")
  }
  sb.write_string(normalize_key_name(event.key))
  sb.to_string()
}

///|
/// Parses a binding spec into `(modifier bits, uses Mod, base key)`.
fn parse_key_spec(spec : String) -> (Int, Bool, String) {
  let parts = spec.split("-").map(fn(part) { part.to_owned() }).to_array()
  let mut flags = 0
  let mut has_mod = false
  let mut i = 0
  while i < parts.length() - 1 {
    let part = parts[i].to_lower()
    if part == "shift" {
      flags = flags | mod_shift
    } else if part == "ctrl" || part == "control" {
      flags = flags | mod_ctrl
    } else if part == "alt" {
      flags = flags | mod_alt
    } else if part == "meta" || part == "cmd" {
      flags = flags | mod_meta
    } else if part == "mod" {
      has_mod = true
    } else {
      break
    }
    i = i + 1
  }
  let raw = parts[parts.length() - 1]
  let base = normalize_key_name(raw)
  if raw.length() == 1 {
    let c = raw.unsafe_get(0).to_int()
    if c >= 65 && c <= 90 {
      flags = flags | mod_shift
    }
  }
  (flags, has_mod, base)
}

///|
/// True when `binding_key` matches the canonical `event_spec`. `Mod` maps to
/// ctrl, or to meta when the platform bit is set in `event_mods`, and only
/// when the opposite modifier is not held. Unlisted modifiers must not be
/// held.
fn key_spec_matches(
  binding_key : String,
  event_spec : String,
  event_mods : Int,
) -> Bool {
  let (req, has_mod, base) = parse_key_spec(binding_key)
  let (ev, _, ev_base) = parse_key_spec(event_spec)
  if base != ev_base {
    return false
  }
  let mut need = req
  if has_mod {
    if (event_mods & mod_platform) != 0 {
      if (ev & mod_meta) == 0 {
        return false
      }
      need = need | mod_meta
    } else {
      if (ev & mod_meta) != 0 {
        return false
      }
      need = need | mod_ctrl
    }
  }
  ev == need
}

///|
/// Runs the first binding that matches the event. When shift is held and no
/// exact binding matches, the `shift` variant of the plain binding is used.
pub fn Keymap::run(
  self : Keymap,
  state : @state.EditorState,
  event : KeyEvent,
) -> @state.TransactionSpec? {
  let spec = binding_spec(event)
  for b in self.bindings {
    if key_spec_matches(b.key, spec, event.mods) {
      match (b.run)(state) {
        Some(t) => return Some(t)
        None => ()
      }
    }
  }
  if (event.mods & mod_shift) != 0 {
    let plain_mods = event.mods ^ mod_shift
    let plain = binding_spec({
      key: event.key,
      code: event.code,
      mods: plain_mods,
    })
    for b in self.bindings {
      if key_spec_matches(b.key, plain, plain_mods) {
        match (b.shift)(state) {
          Some(t) => return Some(t)
          None => ()
        }
      }
    }
  }
  None
}

///|
pub fn key_binding(
  key~ : String,
  run~ : (@state.EditorState) -> @state.TransactionSpec?,
) -> KeyBinding {
  { key, run, shift: fn(_) { None } }
}

///|
/// Facet holding the merged keymaps of the configuration.
pub let keymap_facet : @state.Facet[Array[KeyBinding]] = @state.Facet::new(
  default=fn() -> Array[KeyBinding] { [] },
  combine=fn(a : Array[KeyBinding], b : Array[KeyBinding]) { a + b },
)

///|
pub fn keymap(bindings : Array[KeyBinding]) -> @state.Extension {
  keymap_facet.of(bindings)
}

///|
fn some(
  f : (@state.EditorState) -> @state.TransactionSpec,
) -> (@state.EditorState) -> @state.TransactionSpec? {
  fn(state) { Some(f(state)) }
}

///|
fn none_cmd(_ : @state.EditorState) -> @state.TransactionSpec? {
  None
}

///|
/// The default key bindings, analogous to CodeMirror's `defaultKeymap`.
pub fn default_keymap() -> Array[KeyBinding] {
  [
    key_binding(key="ArrowLeft", run=some(cursor_char_left)),
    key_binding(key="ArrowRight", run=some(cursor_char_right)),
    key_binding(key="ArrowUp", run=some(cursor_line_up)),
    key_binding(key="ArrowDown", run=some(cursor_line_down)),
    key_binding(key="Shift-ArrowLeft", run=some(select_char_left)),
    key_binding(key="Shift-ArrowRight", run=some(select_char_right)),
    key_binding(key="Shift-ArrowUp", run=some(select_line_up)),
    key_binding(key="Shift-ArrowDown", run=some(select_line_down)),
    key_binding(key="Ctrl-ArrowLeft", run=some(cursor_word_left)),
    key_binding(key="Ctrl-ArrowRight", run=some(cursor_word_right)),
    key_binding(key="Shift-Ctrl-ArrowLeft", run=some(select_word_left)),
    key_binding(key="Shift-Ctrl-ArrowRight", run=some(select_word_right)),
    key_binding(key="Home", run=some(cursor_line_start)),
    key_binding(key="End", run=some(cursor_line_end)),
    key_binding(key="Shift-Home", run=some(select_line_start)),
    key_binding(key="Shift-End", run=some(select_line_end)),
    key_binding(key="Ctrl-Home", run=some(cursor_doc_start)),
    key_binding(key="Ctrl-End", run=some(cursor_doc_end)),
    key_binding(key="Shift-Ctrl-Home", run=some(select_doc_start)),
    key_binding(key="Shift-Ctrl-End", run=some(select_doc_end)),
    key_binding(key="Mod-a", run=some(select_all_cmd)),
    key_binding(key="Backspace", run=some(delete_char_backward)),
    key_binding(key="Mod-Backspace", run=some(delete_group_backward)),
    key_binding(key="Delete", run=some(delete_char_forward)),
    key_binding(key="Enter", run=some(insert_newline)),
    key_binding(
      key="Tab",
      run=some(fn(state) {
        insert_tab(state, indent_unit=state.facet(indent_unit_facet))
      }),
    ),
    key_binding(key="Escape", run=none_cmd),
    key_binding(key="PageUp", run=some(fn(state) { page_up(state) })),
    key_binding(key="PageDown", run=some(fn(state) { page_down(state) })),
    key_binding(key="Mod-z", run=undo_cmd),
    key_binding(key="Mod-Shift-z", run=redo_cmd),
    key_binding(key="Mod-y", run=redo_cmd),
    key_binding(key="Alt-ArrowUp", run=some(add_cursor_above)),
    key_binding(key="Alt-ArrowDown", run=some(add_cursor_below)),
    key_binding(key="Mod-d", run=select_next_occurrence_cmd),
    key_binding(key="Mod-/", run=some(fn(state) { toggle_line_comment(state) })),
    key_binding(
      key="Mod-]",
      run=some(fn(state) {
        indent_more(state, indent_unit=state.facet(indent_unit_facet))
      }),
    ),
    key_binding(
      key="Mod-[",
      run=some(fn(state) {
        indent_less(state, indent_unit=state.facet(indent_unit_facet))
      }),
    ),
  ]
}

///|
/// Reads the configured keymaps from the state, falling back to
/// `default_keymap()` when the facet is empty, and runs the matching binding.
pub fn run_keymap_facet(
  state : @state.EditorState,
  event : KeyEvent,
) -> @state.TransactionSpec? {
  let configured = state.facet(keymap_facet)
  let bindings = if configured.length() == 0 {
    default_keymap()
  } else {
    configured
  }
  Keymap::new().bind(bindings).run(state, event)
}
