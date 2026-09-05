local FlockSearch = require("src.behavior.flock_search")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function actor(id, independence)
  return {
    id = id,
    species = "PIDGEY",
    ecology = { family = "flock-a", socialModifier = 1, desiredGroupSize = 3 },
    temperament = { sociability = 0.9 },
    rawStats = { independence = independence },
    relationships = {},
    runtimeState = { lastFleeEndTick = 100, state = "IDLE" }
  }
end

local position = { cellX = 0, cellY = 0 }
local dependent = actor("dependent", 0.1)
local early = FlockSearch.update(dependent, position, {}, 110)
local later = FlockSearch.update(dependent, position, {}, 240)
assertTrue(early.reassemblyPressure == 0, "reassembly pressure should be absent during immediate calm-down")
assertTrue(later.reassemblyPressure > early.reassemblyPressure and later.utility > early.utility,
  "isolated social actors should gradually regain SEEK_FLOCK pressure after FLEE")

local independent = actor("independent", 0.9)
local independentLater = FlockSearch.update(independent, position, {}, 240)
assertTrue(independentLater.utility < later.utility,
  "high-independence actors should have weaker reassembly utility")

local companion = actor("companion", 0.2)
local restored = FlockSearch.update(dependent, position, {
  { entity = companion, position = { cellX = 1, cellY = 0 }, perceived = true }
}, 241)
assertTrue(restored.reassemblyPressure == 0,
  "restored local conspecific context should clear post-FLEE reassembly pressure")

dependent.runtimeState.directThreatId = "threat"
local interrupted = FlockSearch.update(dependent, position, {}, 242)
assertTrue(interrupted.reassemblyPressure == 0,
  "a new direct threat should interrupt reassembly pressure")

return true