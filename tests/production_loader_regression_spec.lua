local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEquals failed") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local storedState = nil
local spawnCalls = 0
local mapId = "ROUTE_3"
local rows = {}
for _ = 1, 36 do rows[#rows + 1] = string.rep(".", 20) end

local mod = {
  path = ".",
  storage = {
    read = function() return storedState, storedState == nil and "not_found" or nil end,
    write = function(_, _, _, value) storedState = value return true end
  },
  world = {
    current = function() return { mapId = mapId, x = 10, y = 10 } end,
    mapOverview = function() return { mapId = mapId, width = 20, height = 36, rows = rows } end,
    spawnNpc = function(_, _, _) spawnCalls = spawnCalls + 1 return "npc_" .. tostring(spawnCalls) end,
    npc = function() return {} end,
    removeNpc = function() return true end
  },
  options = {
    define = function() end,
    get = function(_, key)
      if key == "phase0_behavior_mode" then return "normal" end
      return nil
    end
  },
  save = { get = function(_, _, default) return default end, set = function() end }
}

local entry = require("main")
local WildEcology = entry(mod)
assertEquals(spawnCalls, Config.phase3.visibleSubsetSize,
  "normal bootstrap should materialize the selected cohort")

local originalRequire = require
local originalPackagePath = package.path
package.path = ""
require = function(moduleName)
  if moduleName == "src.world.avatar_factory" then
    error("ordinary AvatarFactory require intentionally disabled")
  end
  return originalRequire(moduleName)
end

WildEcology.shutdown()
local before = spawnCalls
WildEcology.init(mod)
require = originalRequire
package.path = originalPackagePath

assertEquals(spawnCalls > before, true,
  "re-entry should materialize the selected cohort")
assertEquals(WildEcology.spawnDiagnostics.phase3LastBlocker, "SUCCESS",
  "materialization should continue using the bootstrap-loaded AvatarFactory")
assertEquals(WildEcology.spawnDiagnostics.lastPhase3Error, "NONE",
  "production-like loader test should not record a lazy AvatarFactory require error")

local phase3BeforeStableTicks = WildEcology.spawnDiagnostics.phase3Entered
WildEcology.resetPerformanceProfiler()
WildEcology.enablePerformanceProfiler(true)
for _ = 1, 1000 do
  WildEcology.sync(mod)
end
local performance = WildEcology.getPerformanceSnapshot()
local leakBeforeGc = WildEcology.getLeakDiagnostics()
collectgarbage("collect")
local leakAfterGc = WildEcology.getLeakDiagnostics()
print(string.format("PERF samples=%s pairs=%s threats=%s fear=%s relationships=%s phases=%s selections=%s",
  tostring(performance.samples), tostring(performance.counts.perception_pair_checks or 0),
  tostring(performance.counts.threat_assessments or 0),
  tostring(performance.counts.fear_updates or 0),
  tostring(performance.counts.relationship_observation_calls or 0),
  tostring(WildEcology.spawnDiagnostics.phase3Entered),
  tostring(WildEcology.spawnDiagnostics.visibleSelectionCalls)))
print(string.format("PERF_MS sync=%.3f perception=%.3f threatFear=%.3f behavior=%.3f hud=%.3f",
  performance.totals.sync or 0, performance.totals.perception or 0,
  performance.totals.threat_fear or 0, performance.totals.behavior or 0,
  performance.totals.hud or 0))
print(string.format("BEHAVIOR_MS target=%.3f deliberation=%.3f execution=%.3f builds=%s",
  performance.totals.target_build or 0, performance.totals.deliberation or 0,
  performance.totals.execution or 0,
  tostring(performance.counts.behavior_target_builds or 0)))
print(string.format("EXEC_MS total=%.3f context=%.3f controller=%.3f movement=%.3f calls=%s polls=%s",
  performance.totals.execution_total or 0,
  performance.totals.execution_context or 0,
  performance.totals.execution_controller or 0,
  performance.totals.execution_movement or 0,
  tostring(performance.counts.execution_calls or 0),
  tostring(performance.counts.execution_motion_polls or 0)))
print(string.format("LEAK luaKB_before=%.1f luaKB_afterGC=%.1f events=%s relationships=%s contacts=%s nav=%s intent=%s active=%s profilerMem=%s",
  leakBeforeGc.luaKB, leakAfterGc.luaKB, tostring(leakAfterGc.recentEvents),
  tostring(leakAfterGc.relationshipRecords), tostring(leakAfterGc.contactRecords),
  tostring(leakAfterGc.navigationRecords), tostring(leakAfterGc.intentRecords),
  tostring(leakAfterGc.activeAvatars), tostring(leakAfterGc.profilerMemorySamples)))
local plateauBaseline = leakAfterGc.luaKB
for checkpoint = 1, 3 do
  for _ = 1, 1000 do WildEcology.sync(mod) end
  local beforeCheckpointGc = WildEcology.getLeakDiagnostics().luaKB
  collectgarbage("collect")
  local afterCheckpointGc = WildEcology.getLeakDiagnostics()
  print(string.format("SOAK tick=%s luaKB_beforeGC=%.1f luaKB_afterGC=%.1f events=%s relationships=%s contacts=%s active=%s",
    tostring(checkpoint * 1000 + 1000), beforeCheckpointGc, afterCheckpointGc.luaKB,
    tostring(afterCheckpointGc.recentEvents), tostring(afterCheckpointGc.relationshipRecords),
    tostring(afterCheckpointGc.contactRecords), tostring(afterCheckpointGc.activeAvatars)))
  assert(afterCheckpointGc.luaKB <= plateauBaseline + 750,
    "stable soak memory should remain near the post-warmup plateau")
end
assertEquals(WildEcology.spawnDiagnostics.phase3Entered, phase3BeforeStableTicks,
  "stable ticks must not re-enter Phase 3 spawn synchronization")
assertEquals(WildEcology.spawnDiagnostics.visibleSelectionCalls, 2,
  "stable ticks must not recompute the visible selection")

local firstVisitIds, firstVisitCells = {}, {}
for entityId, avatar in pairs(WildEcology.activeAvatars) do
  firstVisitIds[entityId] = true
  firstVisitCells[entityId] = avatar.requestedCell
end
mapId = "PALLET_TOWN"
WildEcology.sync(mod)
mapId = "ROUTE_3"
WildEcology.sync(mod)
local changedSelection = false
local changedPlacement = false
for entityId, avatar in pairs(WildEcology.activeAvatars) do
  if not firstVisitIds[entityId] then changedSelection = true end
  local oldCell = firstVisitCells[entityId]
  local newCell = avatar.requestedCell
  if oldCell and newCell and (oldCell.cellX ~= newCell.cellX or oldCell.cellY ~= newCell.cellY) then
    changedPlacement = true
  end
end
assertEquals(changedSelection or changedPlacement, true,
  "a distinct route visit should permit deterministic subset or placement variation")

print("production loader regression: ok")
return true
