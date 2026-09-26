///|
/// The state of the search/replace panel.
pub struct SearchState {
  open : Bool
  query : SearchQuery
  matches : Array[@core.Range]
  current : Int
  replace_text : String
}

///|
pub fn SearchState::empty() -> SearchState {
  {
    open: false,
    query: SearchQuery::new(text=""),
    matches: [],
    current: 0,
    replace_text: "",
  }
}

///|
/// Opens or closes the search panel.
pub let set_open_effect : @state.StateEffect[Bool] = @state.StateEffect::new()

///|
/// Installs a new query (resets `current` to the first match).
pub let set_query_effect : @state.StateEffect[SearchQuery] = @state.StateEffect::new()

///|
/// Selects a match by index.
pub let set_current_effect : @state.StateEffect[Int] = @state.StateEffect::new()

///|
/// Remembers the text the user last replaced with.
pub let set_replace_effect : @state.StateEffect[String] = @state.StateEffect::new()

///|
pub let search_field : @state.StateField[SearchState] = @state.StateField::new(
  init=fn(_) { SearchState::empty() },
  update=fn(old, tr) {
    let mut open = old.open
    let mut query = old.query
    let mut replace_text = old.replace_text
    let mut current = old.current
    match tr.effect(set_open_effect) {
      Some(value) => open = value
      None => ()
    }
    match tr.effect(set_query_effect) {
      Some(value) => {
        query = value
        current = 0
      }
      None => ()
    }
    match tr.effect(set_replace_effect) {
      Some(value) => replace_text = value
      None => ()
    }
    match tr.effect(set_current_effect) {
      Some(value) => current = value
      None => ()
    }
    let matches : Array[@core.Range] = if open && query.text != "" {
      find_matches(tr.new_doc(), query)
    } else {
      []
    }
    let count = matches.length()
    let clamped = if count == 0 {
      0
    } else if current < 0 {
      0
    } else if current >= count {
      count - 1
    } else {
      current
    }
    { open, query, matches, current: clamped, replace_text, }
  },
)

///|
fn search_state(state : @state.EditorState) -> SearchState? {
  if state.has_field(search_field.id()) {
    Some(state.field(search_field))
  } else {
    None
  }
}

///|
/// Opens the search panel.
pub fn open_search() -> @state.TransactionSpec {
  @state.TransactionSpec::new(effects=[set_open_effect.of(true)])
}

///|
/// Closes the search panel and drops the current matches.
pub fn close_search(state : @state.EditorState) -> @state.TransactionSpec {
  ignore(state)
  @state.TransactionSpec::new(effects=[set_open_effect.of(false)])
}

///|
/// Sets the active query, opens the panel and selects the first match (if any).
pub fn set_query(
  state : @state.EditorState,
  query : SearchQuery,
) -> @state.TransactionSpec {
  let effects = [set_open_effect.of(true), set_query_effect.of(query)]
  if query.text != "" {
    let matches = find_matches(state.doc(), query)
    if matches.length() > 0 {
      let first = matches[0]
      return @state.TransactionSpec::new(
        selection=@core.EditorSelection::single(first.from, first.to),
        effects~,
        scroll_into_view=true,
      )
    }
  }
  @state.TransactionSpec::new(effects~)
}

///|
fn select_relative(
  state : @state.EditorState,
  delta : Int,
) -> @state.TransactionSpec? {
  match search_state(state) {
    None => None
    Some(search) => {
      let count = search.matches.length()
      if !search.open || count == 0 {
        return None
      }
      let index = ((search.current + delta) % count + count) % count
      let range = search.matches[index]
      Some(
        @state.TransactionSpec::new(
          selection=@core.EditorSelection::single(range.from, range.to),
          effects=[set_current_effect.of(index)],
          scroll_into_view=true,
        ),
      )
    }
  }
}

///|
/// Selects the next match, wrapping around.
pub fn select_next(state : @state.EditorState) -> @state.TransactionSpec? {
  select_relative(state, 1)
}

///|
/// Selects the previous match, wrapping around.
pub fn select_prev(state : @state.EditorState) -> @state.TransactionSpec? {
  select_relative(state, -1)
}

///|
/// Replaces the currently selected match.
pub fn replace_current(
  state : @state.EditorState,
  replacement : String,
) -> @state.TransactionSpec? {
  match search_state(state) {
    None => None
    Some(search) => {
      if search.matches.length() == 0 {
        return None
      }
      let range = search.matches[search.current]
      let changes = @core.ChangeSet::of([
        @core.Change::new(range.from, range.to, replacement),
      ])
      Some(
        @state.TransactionSpec::new(
          changes~,
          selection=@core.EditorSelection::single(
            range.from,
            range.from + replacement.length(),
          ),
          effects=[
            set_replace_effect.of(replacement),
            set_current_effect.of(search.current),
          ],
          scroll_into_view=true,
        ),
      )
    }
  }
}

///|
/// Replaces every match at once and selects the changed region.
pub fn replace_all(
  state : @state.EditorState,
  replacement : String,
) -> @state.TransactionSpec? {
  match search_state(state) {
    None => None
    Some(search) => {
      let matches = find_matches(state.doc(), search.query, limit=0)
      if matches.length() == 0 {
        return None
      }
      let changes : Array[@core.Change] = []
      for range in matches {
        changes.push(@core.Change::new(range.from, range.to, replacement))
      }
      let change_set = @core.ChangeSet::of(changes)
      let first = matches[0]
      let last = matches[matches.length() - 1]
      let selection = @core.EditorSelection::single(
        change_set.map_pos(first.from, -1),
        change_set.map_pos(last.to, 1),
      )
      Some(
        @state.TransactionSpec::new(
          changes=change_set,
          selection~,
          effects=[set_replace_effect.of(replacement)],
          annotations=[@state.UserEvent("replace")],
          scroll_into_view=true,
        ),
      )
    }
  }
}

///|
pub fn is_search_open(state : @state.EditorState) -> Bool {
  match search_state(state) {
    Some(search) => search.open
    None => false
  }
}
