local Save = {
  mod = nil,
  cache = nil
}

local CURRENT_SCHEMA_VERSION = 1

local DEFAULT_STATE = {
  schemaVersion = CURRENT_SCHEMA_VERSION,
  nextEntitySerial = 1,
  simulationTick = 0,
  populations = {}
}

local function deepCopy(tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      copy[k] = deepCopy(v)
    else
      copy[k] = v
    end
  end
  return copy
end

local function ensureStateShape(state)
  if state.schemaVersion == nil then
    state.schemaVersion = CURRENT_SCHEMA_VERSION
  end
  if state.nextEntitySerial == nil then
    state.nextEntitySerial = 1
  end
  if state.simulationTick == nil then
    state.simulationTick = 0
  end
  if state.populations == nil then
    state.populations = {}
  end

  return state
end

local function migrateState(state)
  if state == nil then
    return deepCopy(DEFAULT_STATE)
  end

  -- Add in-place schema migration logic here when schemaVersion > 1.
  return ensureStateShape(state)
end

function Save.init(mod)
  Save.mod = mod

  local storage = mod and mod.storage
  if storage and storage.get then
    Save.cache = storage.get("wild_ecology")
  end

  Save.cache = migrateState(Save.cache)
end

function Save.getState()
  return Save.cache
end

function Save.flush()
  local storage = Save.mod and Save.mod.storage
  if storage and storage.set and Save.cache then
    storage.set("wild_ecology", Save.cache)
  end
end

function Save.nextTick()
  local state = Save.getState()
  if state == nil then
    state = deepCopy(DEFAULT_STATE)
    Save.cache = state
  end
  if state.simulationTick == nil then
    state.simulationTick = 0
  end
  state.simulationTick = state.simulationTick + 1
  return state.simulationTick
end

return Save
