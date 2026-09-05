-- Persistence Adapter
--
-- Formal boundary between Wild Ecology's portable save/schema logic and
-- host-specific storage backend (e.g., mod.storage in Gen1Recomp).
--
-- The adapter treats Wild Ecology state as opaque.
-- It must NOT interpret or validate ecology-specific fields.
-- That responsibility remains with Save.

local PersistenceAdapter = {}

-- Load opaque Wild Ecology persistent state from host backend.
--
-- namespace: string identifying the save namespace (e.g., "wild_ecology")
--
-- Returns: opaque value, status, optional error detail
--          status is "ok", "not_found", or "error".
--          The caller (Save) is responsible for validation/migration.
function PersistenceAdapter.load(namespace)
  error("PersistenceAdapter.load() must be implemented by host backend")
end

-- Save opaque Wild Ecology persistent state to host backend.
--
-- namespace: string identifying the save namespace (e.g., "wild_ecology")
-- state:     opaque Lua table containing full Wild Ecology persistent state
--
-- Returns: boolean success
--          true if saved successfully
--          false if save failed (backend error, no storage, etc.)
--
-- Caller (Save) is responsible for snapshotting/serialization before calling.
function PersistenceAdapter.save(namespace, state)
  error("PersistenceAdapter.save() must be implemented by host backend")
end

return PersistenceAdapter
