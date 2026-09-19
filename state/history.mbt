///|
/// A group of adjacent edits that are undone or redone together.
pub(all) struct HistoryGroup {
  before : @core.Text
  after : @core.Text
  selection_before : @core.EditorSelection
  selection_after : @core.EditorSelection
  event : String
  count : Int
}

///|
pub(all) struct HistoryState {
  done : Array[HistoryGroup]
  undone : Array[HistoryGroup]
}

///|
pub fn HistoryState::empty() -> HistoryState {
  { done: [], undone: [] }
}

///|
pub fn HistoryState::can_undo(self : HistoryState) -> Bool {
  self.done.length() > 0
}

///|
pub fn HistoryState::can_redo(self : HistoryState) -> Bool {
  self.undone.length() > 0
}

///|
fn is_groupable_event(event : String) -> Bool {
  event == "input.type" || event == "input.delete" || event == "input.backspace"
}

///|
fn can_merge(last : HistoryGroup, group : HistoryGroup) -> Bool {
  if last.event != group.event || !is_groupable_event(group.event) {
    return false
  }
  if last.count >= 100 {
    return false
  }
  last.selection_after.eq(group.selection_before)
}

///|
fn diff_changes(from : @core.Text, to : @core.Text) -> @core.ChangeSet {
  let a = from.to_string()
  let b = to.to_string()
  let alen = a.length()
  let blen = b.length()
  let mut prefix = 0
  while prefix < alen &&
        prefix < blen &&
        a.unsafe_get(prefix) == b.unsafe_get(prefix) {
    prefix = prefix + 1
  }
  let mut suffix = 0
  while suffix < alen - prefix &&
        suffix < blen - prefix &&
        a.unsafe_get(alen - 1 - suffix) == b.unsafe_get(blen - 1 - suffix) {
    suffix = suffix + 1
  }
  @core.ChangeSet::of([
    @core.Change::new(prefix, alen - suffix, b[prefix:blen - suffix].to_owned()),
  ])
}

///|
/// Maximum number of history groups retained. Once exceeded, the oldest
/// groups are dropped so undo history memory stays bounded.
pub let history_max_groups : Int = 200

///|
/// Appends a group to the done stack, trimming the oldest groups when the
/// budget is exceeded.
fn push_group(
  done : Array[HistoryGroup],
  group : HistoryGroup,
) -> Array[HistoryGroup] {
  let result = done + [group]
  let excess = result.length() - history_max_groups
  if excess > 0 {
    result[excess:result.length()].to_owned()
  } else {
    result
  }
}

///|
pub let history_field : StateField[HistoryState] = StateField::new(
  init=fn(_) { HistoryState::empty() },
  update=fn(old, tr) {
    match tr.user_event() {
      Some("undo") => {
        if old.done.length() == 0 {
          return old
        }
        let group = old.done[old.done.length() - 1]
        return {
          done: old.done[0:old.done.length() - 1].to_owned(),
          undone: old.undone + [group],
        }
      }
      Some("redo") => {
        if old.undone.length() == 0 {
          return old
        }
        let group = old.undone[old.undone.length() - 1]
        return {
          done: push_group(old.done, group),
          undone: old.undone[0:old.undone.length() - 1].to_owned(),
        }
      }
      _ => ()
    }
    if tr.changes().is_empty() {
      return old
    }
    // A non-history document change cannot be rebased against stale snapshot
    // diffs, so drop all existing groups instead of corrupting undo.
    if tr.is_remote() || !tr.add_to_history() {
      return { done: [], undone: [] }
    }
    let event = match tr.user_event() {
      Some(e) => e
      None => "input"
    }
    let group : HistoryGroup = {
      before: tr.start_state().doc(),
      after: tr.new_doc(),
      selection_before: tr.start_state().selection(),
      selection_after: tr.selection(),
      event,
      count: 1,
    }
    if old.done.length() > 0 {
      let last = old.done[old.done.length() - 1]
      if can_merge(last, group) {
        let done = old.done.copy()
        let _ = done.pop()
        done.push({
          before: last.before,
          after: group.after,
          selection_before: last.selection_before,
          selection_after: group.selection_after,
          event: last.event,
          count: last.count + 1,
        })
        return { done, undone: [] }
      }
    }
    { done: push_group(old.done, group), undone: [] }
  },
)

///|
/// Returns the transaction spec that undoes the last history group.
pub fn undo_spec(state : EditorState) -> TransactionSpec? {
  let history = state.field(history_field)
  if history.done.length() == 0 {
    return None
  }
  let group = history.done[history.done.length() - 1]
  Some(
    TransactionSpec::new(
      changes=diff_changes(group.after, group.before),
      selection=group.selection_before,
      annotations=[AddToHistory(false), UserEvent("undo")],
      scroll_into_view=true,
    ),
  )
}

///|
/// Returns the transaction spec that redoes the last undone history group.
pub fn redo_spec(state : EditorState) -> TransactionSpec? {
  let history = state.field(history_field)
  if history.undone.length() == 0 {
    return None
  }
  let group = history.undone[history.undone.length() - 1]
  Some(
    TransactionSpec::new(
      changes=diff_changes(group.before, group.after),
      selection=group.selection_after,
      annotations=[AddToHistory(false), UserEvent("redo")],
      scroll_into_view=true,
    ),
  )
}
