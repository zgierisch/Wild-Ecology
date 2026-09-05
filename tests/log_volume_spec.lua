local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function unloadRuntime()
  for _, name in ipairs({
    "main", "src.core.save", "src.debug.logger", "src.population.manager",
    "src.world.avatar_factory", "src.behavior.controller",
    "src.world.perception", "src.world.movement_claims"
  }) do
    package.loaded[name] = nil
  end
end

local function runWorkload(trace)
  unloadRuntime()
  local congestion = false
  package.loaded["src.world.Collision"] = {
    canMove = function()
      if congestion then return false, "entity" end
      return true
    end,
    target = function(x, y, direction)
      return x + (direction == "right" and 1 or direction == "left" and -1 or 0),
        y + (direction == "down" and 1 or direction == "up" and -1 or 0)
    end
  }

  local Logger = require("src.debug.logger")
  local records = {}
  local bytes = 0
  Logger.setObserver(function(entry)
    local line = string.format("[%s] %s\n", tostring(entry.category), entry.message)
    records[#records + 1] = entry
    bytes = bytes + #line
  end)

  local storedState = nil
  local handles, definitions = {}, {}
  local nextNpc = 0
  local playerX, playerY = 100, 100
  local mapId = Config.phase0.testMapId
  local mod = {
    storage = {
      read = function() return storedState, storedState == nil and "not_found" or nil end,
      write = function(_, _game, _key, value) storedState = value return true end,
      writeBytes = function() return true end
    },
    game = {},
    world = {
      current = function() return { mapId = mapId, x = playerX, y = playerY } end,
      spawnNpc = function(_, requestedMapId, definition)
        nextNpc = nextNpc + 1
        local id = requestedMapId .. "_log_" .. tostring(nextNpc)
        definitions[id] = definition
        return id
      end,
      npc = function(_, _, id)
        local definition = definitions[id]
        handles[id] = handles[id] or {
          npc = {
            cellX = definition.x,
            cellY = definition.y,
            moving = false,
            facing = "down",
            kind = "stand"
          },
          ow = { map = { id = mapId }, entities = {} }
        }
        return handles[id]
      end,
      removeNpc = function() return true end
    },
    options = {
      define = function() end,
      get = function(_, key)
        if key == "phase0_behavior_mode" then return "normal" end
        if key == "phase2_social_fear" or key == "phase5_diagnostics" then
          return true
        end
        return nil
      end
    },
    save = {
      get = function(_, key, default)
        local values = {
          phase0_debug_log = true,
          dev_log_console = true,
          dev_log_lifecycle = true,
          dev_log_behavior = true,
          dev_log_behavior_trace = trace,
          dev_log_relationships = true,
          dev_log_generation = false
        }
        if values[key] ~= nil then return values[key] end
        return default
      end,
      set = function() end
    }
  }

  local WildEcology = require("main")(mod)
  WildEcology.init(mod)
  local population = storedState.populations[mapId]
  local focusedId = Config.phase0.testEntityId
  local focused = population.members[focusedId]
  WildEcology.focusedEntityId = focusedId

  for tick = 1, 1000 do
    for _, handle in pairs(handles) do
      local npc = handle.npc
      if npc.moving then
        npc.cellX, npc.cellY = npc.targetX, npc.targetY
        npc.moving = false
      end
    end
    if tick == 300 then
      playerX = focused.home.spawnX
      playerY = focused.home.spawnY + 1
      local relationship = focused.relationships.player or {}
      focused.relationships.player = relationship
      relationship.trust = 0
      relationship.threatMemory = 90
      relationship.hostility = 60
    elseif tick == 700 then
      playerX, playerY = 100, 100
    end
    congestion = tick >= 200 and tick <= 250
    WildEcology.init(mod)
  end

  local claims = WildEcology.movementClaims
  local now = storedState.simulationTick
  claims:clear(focusedId, now, "TEST_SETUP")
  claims:publish({ actorId = focusedId, fromX = 10, fromY = 10,
    toX = 11, toY = 10, intent = "FLEE" }, now)
  claims:publish({ actorId = "head-on-contender", fromX = 11, fromY = 10,
    toX = 10, toY = 10, intent = "SEEK_FLOCK" }, now)
  claims:clear(focusedId, now, "TEST_SETUP")
  claims:publish({ actorId = focusedId, fromX = 10, fromY = 10,
    toX = 11, toY = 10, intent = "FLEE" }, now)
  claims:publish({ actorId = "destination-contender", fromX = 11, fromY = 9,
    toX = 11, toY = 10, intent = "TARGET" }, now)
  claims:clear(focusedId, now, "TEST_SETUP")
  claims:publish({ actorId = focusedId, fromX = 10, fromY = 10,
    toX = 11, toY = 10, intent = "FLEE" }, now)
  claims:validateActor(focusedId, {
    movementRequest = { traversalMode = "WALK", destinationX = 11, destinationY = 10 },
    motion = { active = false }
  }, { cellX = 10, cellY = 10 }, now + 180)

  local debugSnapshot = WildEcology.getSpawnDebugSnapshot()
  local telemetry = debugSnapshot.behaviorDiagnostics or {}

  local text = {}
  local categories = {}
  for _, entry in ipairs(records) do
    text[#text + 1] = entry.message
    local prefixes = {
      "Movement claim", "Movement request", "Route occupancy", "FLEE route",
      "FLEE provenance", "FLEE trace", "Fear", "Social FLEE decision",
      "Intent decision", "Intent transition", "Perception", "Threat switch",
      "Execution trace"
    }
    local prefix = entry.category
    for _, candidate in ipairs(prefixes) do
      if entry.message:sub(1, #candidate) == candidate then
        prefix = candidate
        break
      end
    end
    local category = categories[prefix] or { records = 0, bytes = 0 }
    category.records = category.records + 1
    category.bytes = category.bytes
      + #string.format("[%s] %s\n", tostring(entry.category), entry.message)
    categories[prefix] = category
  end
  return {
    bytes = bytes,
    records = #records,
    text = table.concat(text, "\n"),
    categories = categories,
    telemetry = telemetry
  }
end

local normal = runWorkload(false)
local trace = runWorkload(true)

print(string.format(
  "LOG_VOLUME_PRECHECK normalRecords=%d normalBytes=%d traceRecords=%d traceBytes=%d",
  normal.records, normal.bytes, trace.records, trace.bytes))
for category, data in pairs(normal.categories) do
  print(string.format("LOG_VOLUME_CATEGORY %s records=%d bytes=%d pct=%.2f",
    category, data.records, data.bytes, data.bytes * 100 / normal.bytes))
end
for category, data in pairs(trace.categories) do
  print(string.format("LOG_VOLUME_TRACE_CATEGORY %s records=%d bytes=%d pct=%.2f",
    category, data.records, data.bytes, data.bytes * 100 / trace.bytes))
end
assertTrue(normal.bytes < 160000,
  "healthy 1,000-tick NORMAL telemetry should retain headroom below the existing 200 KB cap; bytes="
    .. tostring(normal.bytes))
assertTrue(trace.bytes > normal.bytes * 2,
  "TRACE should remain substantially more detailed than transition-only NORMAL")
assertEquals(normal.text:find("claimAction=PUBLISHED", 1, true), nil,
  "NORMAL should suppress routine claim publication")
assertTrue(trace.text:find("claimAction=PUBLISHED", 1, true) ~= nil,
  "TRACE should retain routine claim publication")
assertEquals(normal.text:find("reason=MOVEMENT_COMPLETED", 1, true), nil,
  "NORMAL should suppress successful claim completion cleanup")
assertTrue(normal.text:find("conflictType=HEAD_ON_EDGE_SWAP", 1, true) ~= nil,
  "NORMAL should retain head-on claim conflicts")
assertTrue(normal.text:find("conflictType=SAME_DESTINATION", 1, true) ~= nil,
  "NORMAL should retain same-destination claim conflicts")
assertTrue(normal.text:find("reason=STALE_CLAIM", 1, true) ~= nil,
  "NORMAL should retain stale claim expiry")
assertTrue(normal.text:find("Movement request", 1, true) ~= nil,
  "NORMAL should retain rejected or otherwise unusual movement")
assertTrue(normal.text:find("result=false", 1, true) ~= nil
    and normal.text:find("reason=entity", 1, true) ~= nil,
  "NORMAL should clearly retain authoritative movement rejection; sample="
    .. tostring(normal.text:match("Movement request[^\n]+")))
assertTrue(normal.text:find("oscillation=true", 1, true) ~= nil
    or normal.text:find("noProgress=", 1, true) ~= nil,
  "NORMAL should retain ABAB or repeated no-progress evidence")
assertTrue(normal.text:find("Fear actor=", 1, true) ~= nil,
  "NORMAL should retain semantic fear transitions")
assertTrue(normal.text:find("Social FLEE decision", 1, true) ~= nil,
  "NORMAL should retain social FLEE outcome transitions")
assertTrue(normal.text:find("switchReason=", 1, true) ~= nil,
  "NORMAL social FLEE transitions should retain switch-blocking outcomes")
assertTrue(normal.text:find("FLEE provenance", 1, true) ~= nil,
  "NORMAL should retain threat provenance changes")
assertTrue(normal.text:find("socialOnly=true", 1, true) ~= nil,
  "NORMAL should retain explicit social-only Fear telemetry")
assertTrue(normal.text:find("reference=SOCIAL_ESCAPE_VECTOR", 1, true) ~= nil,
  "NORMAL should retain SOCIAL_ESCAPE_VECTOR provenance")
assertTrue(normal.text:find("threat=none", 1, true) ~= nil,
  "social-only NORMAL provenance should remain targetless")
assertTrue(normal.text:find("event=FLEE_STATE_CHANGED", 1, true) ~= nil
    or normal.text:find("Social FLEE decision", 1, true) ~= nil,
  "NORMAL should retain the social-only transition into FLEE")
assertEquals(normal.telemetry.fleeRouteNormalRecords,
  normal.categories["FLEE route"].records,
  "debug snapshot should expose emitted NORMAL FLEE route records")
assertEquals(normal.telemetry.fearNormalRecords,
  normal.categories["Fear"].records,
  "debug snapshot should expose emitted NORMAL Fear records")
assertTrue(normal.telemetry.fleeRouteNormalSuppressedUnchanged > 0,
  "mixed workload should expose unchanged route suppression")
assertTrue(normal.telemetry.fearNormalSuppressedCalmBookkeeping > 0,
  "mixed workload should expose calm Fear bookkeeping suppression")
assertTrue(trace.categories["Movement request"].bytes
    > normal.categories["Movement request"].bytes * 3,
  "TRACE movement requests should retain the full execution payload")
assertTrue(trace.categories["Perception"].records
    > normal.categories["Perception"].records * 5,
  "TRACE should retain detailed all-pairs perception")
assertEquals(normal.text:find("FLEE spatial", 1, true), nil,
  "NORMAL must not gain per-execution FLEE spatial records")
assertTrue(trace.text:find("FLEE spatial actor=", 1, true) ~= nil,
  "focused TRACE should include FLEE spatial geometry")
assertTrue(trace.text:find("primaryThreatId=", 1, true) ~= nil
    and trace.text:find("delta=", 1, true) ~= nil
    and trace.text:find("planningState=", 1, true) ~= nil,
  "FLEE spatial TRACE should retain threat offset and planning state")
assertEquals(normal.text:find("RELATIONSHIP observer=", 1, true), nil,
  "NORMAL must not contain focused relationship mutation diffs")
assertTrue(trace.text:find("RELATIONSHIP observer=", 1, true) ~= nil,
  "TRACE should contain focused relationship mutation diffs")
assertTrue(trace.text:find("event=", 1, true) ~= nil
    and trace.text:find("familiarity=", 1, true) ~= nil,
  "relationship mutation TRACE should identify event and changed field")

print(string.format(
  "LOG_VOLUME normalRecords=%d normalBytes=%d traceRecords=%d traceBytes=%d reductionVs200KB=%.2f%%",
  normal.records, normal.bytes, trace.records, trace.bytes,
  (1 - normal.bytes / 200000) * 100))

return true
