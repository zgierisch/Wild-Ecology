package.path = package.path .. ";./?.lua;./?/init.lua"

local Concealment = require("src.world.concealment")
local Emergence = require("src.world.emergence")
local Entity = require("src.entities.entity")
local FoodOpportunities = require("src.needs.food_opportunities")
local Harness = require("tests.support.daily_rhythm_harness")
local RuntimeState = require("src.core.runtime_state")
local WorldSemantics = require("src.world.world_semantics")

local function assertTrue(value, message)
  if not value then error(message or "expected truthy value") end
end

local TICKS_PER_DAY = 7200
local DURATION = TICKS_PER_DAY * 2

local cells = {}
for _, position in ipairs({
  { cellX = 2, cellY = 1 },
  { cellX = 3, cellY = 1 },
  { cellX = 8, cellY = 1 }
}) do
  cells[WorldSemantics.cellKey(position.cellX, position.cellY)] = {
    terrain = "TALL_GRASS", grass = true, walkable = true,
    validLanding = true, cover = "HIGH"
  }
end
local semantics = assert(WorldSemantics.fromOverview({
  mapId = "DAILY_RHYTHM_ROUTE", width = 14, height = 3,
  rows = {
    "..............",
    "............~.",
    ".............."
  }
}, { cells = cells }))

local function makeActor(id, species, seed, position)
  local entity = Entity.newWildPokemon({
    id = id,
    species = species,
    level = 4,
    personalitySeed = seed,
    firstEncounteredTick = 0,
    home = {
      mapId = semantics.mapId,
      spawnX = position.cellX,
      spawnY = position.cellY,
      area = {
        mapId = semantics.mapId,
        anchorCell = { cellX = 2, cellY = 1 },
        radius = 2,
        establishedTick = 0,
        provenance = "TEST"
      }
    }
  })
  entity.runtimeState = {
    state = "SETTLED",
    stateEnteredTick = 0,
    motion = { active = false },
    rejectedMoves = {}
  }
  return entity
end

local function lifecycle(harness, _, tick)
  if tick % harness.decisionCadence ~= 0 then return "CONCEALED" end
  local result = Concealment.updateRest(harness.entity, tick)
  if result and result.action == "WAKE_HIDDEN" then
    harness.metrics.normalHiddenWakes = (harness.metrics.normalHiddenWakes or 0) + 1
  end
  if not result or result.action ~= "REQUEST_EMERGENCE" then
    return "CONCEALED"
  end
  local cell = Emergence.selectCell(harness.entity, harness.semantics, {})
  if not cell then return "CONCEALED" end
  harness.position = { cellX = cell.cellX, cellY = cell.cellY }
  Concealment.clear(harness.entity)
  RuntimeState.reset(harness.entity)
  harness.entity.runtimeState.state = "SETTLED"
  harness.entity.runtimeState.stateEnteredTick = tick
  harness.metrics.normalEmergences = (harness.metrics.normalEmergences or 0) + 1
  return "SETTLED"
end

local function afterStep(harness, _, tick)
  local runtime = harness.entity.runtimeState or {}
  if runtime.concealmentRequest then
    Concealment.enter(harness.entity, runtime.concealmentRequest, tick)
    RuntimeState.reset(harness.entity)
  end
end

FoodOpportunities.reset()
local pidgey = makeActor("daily-pidgey", "PIDGEY", 17,
  { cellX = 10, cellY = 1 })
local simulation = Harness.new({
  entity = pidgey,
  position = { cellX = 10, cellY = 1 },
  semantics = semantics,
  ticksPerDay = TICKS_PER_DAY,
  decisionCadence = 15,
  timelineLimit = 32,
  lifecycle = lifecycle,
  afterStep = afterStep,
  context = function(_, context)
    context.needSearchRadius = 14
  end
})
local metrics = simulation:run(DURATION)
local occupancy = Harness.occupancy(metrics, DURATION)

print(string.format(
  "DAILY_RHYTHM actor=%s duration=%d transitions=%d SETTLED=%.3f TARGET=%.3f NEED=%.3f REST=%.3f HOME=%.3f CONCEALED=%.3f",
  pidgey.id, DURATION, metrics.transitions,
  occupancy.SETTLED or 0, occupancy.TARGET or 0,
  occupancy.SATISFY_NEED or 0, occupancy.REST or 0,
  occupancy.RETURN_HOME or 0, occupancy.CONCEALED or 0))
local finalRuntime = pidgey.runtimeState or {}
local finalEpisode = finalRuntime.intentEpisode or {}
local finalNeed = finalRuntime.needOpportunity or {}
print(string.format(
  "RHYTHM_FINAL state=%s cell=%d,%d episode=%s/%s need=%s goal=%s movement=%s navigation=%s failure=%s",
  tostring(finalRuntime.state), simulation.position.cellX, simulation.position.cellY,
  tostring(finalEpisode.intent), tostring(finalEpisode.status),
  tostring(finalNeed.driveId), tostring(finalNeed.goalSignature),
  tostring(finalRuntime.movementRequest and finalRuntime.movementRequest.direction),
  tostring(finalRuntime.navigation and finalRuntime.navigation.goalSatisfactionState),
  tostring(finalRuntime.navigation and finalRuntime.navigation.failureReason)))
for _, row in ipairs(metrics.timeline) do
  print(string.format(
    "RHYTHM_EVENT tick=%d phase=%.3f %s->%s reason=%s cell=%d,%d home=%s H=%.3f T=%.3f F=%.3f hidden=%s",
    row.tick, row.phase, row.from, row.to, tostring(row.reason),
    row.position.cellX, row.position.cellY, tostring(row.insideHome),
    row.hunger, row.thirst, row.fatigue, tostring(row.concealed)))
end

assertTrue((occupancy.SETTLED or 0) > 0.15,
  "calm equilibrium should remain a meaningful share of a long run")
assertTrue((metrics.satisfactions.HUNGER or 0) >= 1,
  "real semantic forage should discharge hunger")
assertTrue((metrics.satisfactions.THIRST or 0) >= 1,
  "real water adjacency should discharge thirst")
assertTrue((metrics.driveMinimum.FATIGUE or 1) < 0.25
  and (metrics.driveMaximum.FATIGUE or 0) > 0.35,
  "fatigue should rise and recover across the long run")
assertTrue((occupancy.REST or 0) > 0 or (occupancy.CONCEALED or 0) > 0,
  "fatigue and circadian pressure should produce rest")
assertTrue(metrics.homeReturns >= 1,
  "home return should appear naturally in the long run")
assertTrue((metrics.normalHiddenWakes or 0) >= 1
  and (metrics.normalEmergences or 0) >= 1,
  "concealed rest should wake and emerge normally without disturbance")
assertTrue(metrics.transitions < DURATION / 20,
  "long-horizon behavior should not chatter pathologically")

return true