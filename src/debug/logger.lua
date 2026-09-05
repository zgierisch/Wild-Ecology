local Save = require("src.core.save")

local Logger = {}

local MAX_ENTRIES = 24
local observer = nil

function Logger.setObserver(callback)
  observer = callback
end

local function ensureLogState(state)
  state.debug = state.debug or {}
  state.debug.devLog = state.debug.devLog or {
    nextSequence = 1,
    entries = {}
  }

  local logState = state.debug.devLog
  logState.nextSequence = logState.nextSequence or 1
  logState.entries = logState.entries or {}
  return logState
end

function Logger.getState()
  local state = Save.getState()
  if not state then
    return nil
  end

  return ensureLogState(state)
end

function Logger.log(category, message)
  local logState = Logger.getState()
  if not logState then
    return nil
  end

  local entry = {
    sequence = logState.nextSequence,
    category = category or "system",
    message = tostring(message or "")
  }

  if observer then
    observer(entry)
  end

  logState.nextSequence = logState.nextSequence + 1
  logState.entries[#logState.entries + 1] = entry

  while #logState.entries > MAX_ENTRIES do
    table.remove(logState.entries, 1)
  end

  return entry
end

function Logger.entries()
  local logState = Logger.getState()
  if not logState then
    return {}
  end

  return logState.entries
end

function Logger.filteredEntries(predicate, limit)
  local entries = Logger.entries()
  local results = {}

  for index = #entries, 1, -1 do
    local entry = entries[index]
    if not predicate or predicate(entry) then
      table.insert(results, 1, entry)
      if limit and #results >= limit then
        break
      end
    end
  end

  return results
end

return Logger