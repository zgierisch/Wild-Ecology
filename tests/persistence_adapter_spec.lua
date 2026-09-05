-- Persistence Adapter Tests
--
-- Validates PersistenceAdapter contract and Gen1 implementation.
-- Also proves Save works through FakePersistenceAdapter.

local FakePersistenceAdapter = require("tests.fake_persistence_adapter")
local Gen1PersistenceAdapter = require("src.adapters.gen1.persistence_adapter")
local Save = require("src.core.save")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assert_eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assert_true(value, msg)
  if value ~= true then
    error((msg or "assert_true") .. ": expected true, got " .. tostring(value))
  end
end

local function assert_false(value, msg)
  if value ~= false then
    error((msg or "assert_false") .. ": expected false, got " .. tostring(value))
  end
end

local function assert_nil(value, msg)
  if value ~= nil then
    error((msg or "assert_nil") .. ": expected nil, got " .. tostring(value))
  end
end

local function assert_not_nil(value, msg)
  if value == nil then
    error((msg or "assert_not_nil") .. ": expected non-nil value")
  end
end

-- Test 1: FakePersistenceAdapter saves and loads state
FakePersistenceAdapter.clear()
local testState = { someField = "value", nested = { count = 42 } }
local saved = FakePersistenceAdapter.save("test_namespace", testState)
assert_true(saved, "Test 1a: Save should succeed")

local loaded = FakePersistenceAdapter.load("test_namespace")
assert_not_nil(loaded, "Test 1b: Load should return state")
assert_eq(loaded.someField, "value", "Test 1c: Field should match")
assert_eq(loaded.nested.count, 42, "Test 1d: Nested field should match")

-- Test 2: FakePersistenceAdapter returns nil for non-existent namespace
FakePersistenceAdapter.clear()
local loaded2 = FakePersistenceAdapter.load("non_existent")
assert_nil(loaded2, "Test 2: Non-existent namespace should return nil")

-- Test 3: FakePersistenceAdapter rejects nil state
FakePersistenceAdapter.clear()
local saved3 = FakePersistenceAdapter.save("test", nil)
assert_false(saved3, "Test 3: Saving nil should fail")

-- Test 4: FakePersistenceAdapter rejects non-string namespace
FakePersistenceAdapter.clear()
local saved4 = FakePersistenceAdapter.save(123, { data = "test" })
assert_false(saved4, "Test 4: Non-string namespace should fail")

-- Test 5: Gen1PersistenceAdapter uses the canonical host storage contract
local hostState = nil
local hostWrite = nil
local mockGame = { id = "test_game" }
local mockMod
mockMod = {
  game = mockGame,
  storage = {
    read = function(self, game, key)
      assert_eq(self, mockMod.storage, "Test 5a: read receives storage as self")
      assert_eq(game, mockGame, "Test 5b: read receives the active game")
      assert_eq(key, "wild_ecology", "Test 5c: read receives the namespace key")
      if hostState == nil then
        return nil, "not_found", "missing"
      end
      return hostState
    end,
    write = function(self, game, key, value)
      hostWrite = { self = self, game = game, key = key, value = value }
      hostState = value
      return true
    end
  }
}
Gen1PersistenceAdapter.init(mockMod)
local missingState, missingStatus = Gen1PersistenceAdapter.load("wild_ecology")
assert_nil(missingState, "Test 5d: missing host state is nil")
assert_eq(missingStatus, "not_found", "Test 5e: missing host state is explicit")
local hostPayload = { schemaVersion = 5, populations = {} }
assert_true(Gen1PersistenceAdapter.save("wild_ecology", hostPayload),
  "Test 5f: canonical host write succeeds")
assert_eq(hostWrite.self, mockMod.storage, "Test 5g: write receives storage as self")
assert_eq(hostWrite.game, mockGame, "Test 5h: write receives the active game")
assert_eq(hostWrite.key, "wild_ecology", "Test 5i: write receives namespace as key")
assert_eq(hostWrite.value, hostPayload, "Test 5j: write receives the state payload")
local loadedHostState, loadedHostStatus = Gen1PersistenceAdapter.load("wild_ecology")
assert_eq(loadedHostState, hostPayload, "Test 5k: host payload round-trips")
assert_eq(loadedHostStatus, "ok", "Test 5l: loaded host state is explicit")

-- Test 6: Save initializes with FakePersistenceAdapter and default state
FakePersistenceAdapter.clear()
Save.cache = nil
Save.init(FakePersistenceAdapter)

local state = Save.getState()
assert_not_nil(state, "Test 6a: State should be initialized")
assert_eq(state.schemaVersion, 8, "Test 6b: Should have current schema version")
assert_eq(state.nextEntitySerial, 1, "Test 6c: Serial should be 1")
assert_eq(state.simulationTick, 0, "Test 6d: Tick should be 0")

-- Test 7: Save loads existing state from FakePersistenceAdapter
FakePersistenceAdapter.clear()

local historicalState = {
  schemaVersion = 3,
  nextEntitySerial = 10,
  simulationTick = 100,
  populations = {},
  ecologyClock = { mode = "SIMULATION" },
  dormantCohorts = {},
  debug = { devLog = { entries = {} }, phase0 = {} }
}
FakePersistenceAdapter.save("wild_ecology", historicalState)

Save.cache = nil
Save.init(FakePersistenceAdapter)

local state7 = Save.getState()
assert_not_nil(state7, "Test 7a: State should load")
assert_eq(state7.schemaVersion, 8, "Test 7b: Should migrate to schema 8")
assert_eq(state7.nextEntitySerial, 10, "Test 7c: Should preserve serial")

-- Test 8: Save round-trip
FakePersistenceAdapter.clear()
Save.cache = nil

Save.init(FakePersistenceAdapter)
local state8a = Save.getState()
state8a.nextEntitySerial = 50
state8a.simulationTick = 200

local flushed = Save.flush()
assert_true(flushed, "Test 8a: Flush should succeed")

Save.cache = nil
Save.init(FakePersistenceAdapter)
local state8b = Save.getState()

assert_eq(state8b.nextEntitySerial, 50, "Test 8b: Serial should persist")
assert_eq(state8b.simulationTick, 200, "Test 8c: Tick should persist")
assert_eq(state8b.schemaVersion, 8, "Test 8d: Schema should remain current")

-- Test 9: Save handles nil adapter
Save.cache = nil
Save.init(nil)

local state9 = Save.getState()
assert_not_nil(state9, "Test 9a: Should still create default state")

local flushed9 = Save.flush()
assert_false(flushed9, "Test 9b: Flush without adapter should fail")

-- Test 10: backend load failure does not overwrite valid backend data
local backendStore = {
  wild_ecology = {
    schemaVersion = 3,
    simulationTick = 7,
    populations = {},
    debug = { devLog = { entries = {} }, phase0 = {} }
  }
}

local failingLoadAdapter = {
  load = function() return nil, "error", "temporary backend failure" end,
  save = function(namespace, state)
    backendStore[namespace] = state
    return true
  end
}

Save.cache = nil
Save.init(failingLoadAdapter)
assert_not_nil(backendStore.wild_ecology, "Test 10a: existing backend state still exists")
assert_eq(backendStore.wild_ecology.simulationTick, 7, "Test 10b: backend storage not overwritten on load failure")
assert_eq(Save.loadStatus, "error", "Test 10c: load failure is explicit")
assert_false(Save.flush(), "Test 10d: load failure blocks default-state overwrite")
assert_eq(backendStore.wild_ecology.simulationTick, 7, "Test 10e: blocked flush preserves backend data")

-- Test 11: save failure is reported as failure and cache is kept intact
local backendStore2 = { wild_ecology = { schemaVersion = 5, simulationTick = 10 } }
local failingSaveAdapter = {
  load = function() return backendStore2.wild_ecology end,
  save = function() return false end
}

Save.persistenceAdapter = failingSaveAdapter
Save.cache = { schemaVersion = 5, simulationTick = 42, populations = {}, debug = { devLog = { entries = {} }, phase0 = {} } }
local saveResult = Save.flush()
assert_false(saveResult, "Test 11a: flush should return false on save failure")
assert_eq(Save.getState().simulationTick, 42, "Test 11b: in-memory state remains intact")

-- Test 12: malformed non-table load is treated as empty storage
local malformedAdapter = {
  load = function() return 42, "ok" end,
  save = function() return true end
}

Save.cache = nil
Save.init(malformedAdapter)
local malformedState = Save.getState()
assert_not_nil(malformedState, "Test 12a: malformed backend state falls back to default state")
assert_eq(malformedState.schemaVersion, 8, "Test 12b: recovered default state remains current schema")
assert_eq(Save.loadStatus, "malformed", "Test 12c: malformed state is explicit")
assert_false(Save.flush(), "Test 12d: malformed state cannot overwrite backend data")

print("All persistence adapter tests passed!")

