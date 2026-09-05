-- Fake Persistence Adapter (TEST-ONLY)
--
-- In-memory persistence backend with deliberately different internal structure
-- from Gen1Recomp mod.storage.
--
-- Purpose: Prove that Save schema/migration logic works unchanged through any
-- persistence backend implementation.
--
-- This adapter uses a simple key-value dictionary instead of mod.storage,
-- demonstrating that Save has zero coupling to the storage mechanism.

local FakePersistenceAdapter = {}

local inMemoryStore = {}

function FakePersistenceAdapter.load(namespace)
  if not namespace or type(namespace) ~= "string" then
    return nil, "error", "invalid_namespace"
  end

  local state = inMemoryStore[namespace]
  if state == nil then
    return nil, "not_found"
  end
  return state, "ok"
end

function FakePersistenceAdapter.save(namespace, state)
  if not namespace or type(namespace) ~= "string" then
    return false
  end

  if state == nil then
    return false
  end

  inMemoryStore[namespace] = state
  return true
end

-- TEST-ONLY: Clear all in-memory state
function FakePersistenceAdapter.clear()
  inMemoryStore = {}
end

-- TEST-ONLY: Get internal store (for inspection)
function FakePersistenceAdapter.getStore()
  return inMemoryStore
end

return FakePersistenceAdapter
