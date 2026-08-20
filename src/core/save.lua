local Save = {
  mod = nil,
  cache = nil
}

local DEFAULT_STATE = {
  schemaVersion = 1,
  entities = {},
  relationships = {}
}

local function shallowCopy(tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = v
  end
  return copy
end

function Save.init(mod)
  Save.mod = mod

  local storage = mod and mod.storage
  if storage and storage.get then
    Save.cache = storage.get("wild_ecology")
  end

  if Save.cache == nil then
    Save.cache = shallowCopy(DEFAULT_STATE)
  end
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

return Save
