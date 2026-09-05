-- Gen1Recomp Persistence Adapter Implementation
--
-- Host-specific storage backend for Wild Ecology.
-- Wraps Gen1Recomp's mod.storage API.
--
-- This implementation knows about mod.storage but NOT about ecology domains.

local Gen1PersistenceAdapter = {}

local mod = nil

function Gen1PersistenceAdapter.init(modHost)
  mod = modHost
end

function Gen1PersistenceAdapter.load(namespace)
  if not mod or not mod.storage or not mod.storage.read then
    return nil, "error", "storage_unavailable"
  end

  local ok, result, code, message = pcall(function()
    return mod.storage:read(mod.game, namespace)
  end)
  if not ok then
    return nil, "error", tostring(result)
  end
  if result ~= nil then
    return result, "ok"
  end
  if code == "not_found" then
    return nil, "not_found"
  end
  return nil, "error", message or code or "storage_read_failed"
end

function Gen1PersistenceAdapter.save(namespace, state)
  if not mod or not mod.storage or not mod.storage.write then
    return false
  end

  if state == nil then
    return false
  end

  local ok, result = pcall(function()
    return mod.storage:write(mod.game, namespace, state)
  end)
  if not ok then
    return false
  end
  return result == true
end

return Gen1PersistenceAdapter
