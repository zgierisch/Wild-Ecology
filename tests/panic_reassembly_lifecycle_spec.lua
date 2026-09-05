local Controller = require("src.behavior.controller")
local FlockSearch = require("src.behavior.flock_search")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function actor(index)
  return {
    id = "flock-" .. index,
    species = "PIDGEY",
    personalitySeed = 100 + index,
    ecology = { family = "family-a", socialModifier = 1, desiredGroupSize = 4 },
    temperament = { sociability = 0.9, boldness = 0.15 },
    rawStats = { independence = 0.08 + index * 0.04 },
    relationships = { player = { hostility = 80, threatMemory = 35 } },
    runtimeState = { fearCurrent = 0.9, fearDirect = 0.9 }
  }
end

local actors = { actor(1), actor(2), actor(3), actor(4) }
local positions = {
  [actors[1].id] = { cellX = 3, cellY = 0 },
  [actors[2].id] = { cellX = 3, cellY = 1 },
  [actors[3].id] = { cellX = 4, cellY = 0 },
  [actors[4].id] = { cellX = 4, cellY = 1 }
}
local threatPosition = { cellX = 0, cellY = 0 }

local function socialCandidates(subject)
  local candidates = {}
  for _, other in ipairs(actors) do
    if other ~= subject then
      candidates[#candidates + 1] = {
        entity = other,
        position = positions[other.id],
        perceived = true
      }
    end
  end
  return candidates
end

for _, entity in ipairs(actors) do
  FlockSearch.update(entity, positions[entity.id], socialCandidates(entity), 0, { perceptionRadius = 5 })
end

local function completePriorStep(entity)
  local request = entity.runtimeState.movementRequest
  if request and request.traversalMode == "WALK" then
    positions[entity.id] = { cellX = request.destinationX, cellY = request.destinationY }
    entity.runtimeState.motion = { active = false, justCompleted = true }
  else
    entity.runtimeState.motion = { active = false }
  end
end

for tick = 1, 12 do
  for _, entity in ipairs(actors) do
    if tick > 1 then completePriorStep(entity) end
    local position = positions[entity.id]
    local distance = math.max(math.abs(position.cellX), math.abs(position.cellY))
    Controller.tick(entity, entity.relationships.player, distance, {
      threatAssessment = { primaryThreatId = "player" },
      targetPositions = { player = threatPosition },
      position = position,
      currentFear = 0.9,
      fleeNeighbors = socialCandidates(entity)
    }, tick)
  end
end

local lanes = {}
for _, entity in ipairs(actors) do
  completePriorStep(entity)
  local position = positions[entity.id]
  lanes[position.cellX .. ":" .. position.cellY] = true
  assertTrue(math.max(math.abs(position.cellX), math.abs(position.cellY)) > 4,
    "every panicked flock member should gain net safety")
end
local laneCount = 0
for _ in pairs(lanes) do laneCount = laneCount + 1 end
assertTrue(laneCount >= 3, "individual headings and separation should spatially disperse the flock")

local exitTicks = {}
local earlyRadial, lateRadial = {}, {}
for tick = 20, 180 do
  for index, entity in ipairs(actors) do
    if entity.runtimeState.state == "FLEE" then
      completePriorStep(entity)
      local decline = 0.010 + index * 0.0015
      local fear = math.max(0, 0.9 - (tick - 20) * decline)
      entity.runtimeState.fearCurrent = fear
      entity.runtimeState.fearDirect = fear * 0.7
      Controller.tick(entity, {}, nil, {
        threatAssessment = { primaryThreatId = nil },
        targetPositions = {},
        position = positions[entity.id],
        currentFear = fear,
        fleeNeighbors = {}
      }, tick)
      local heading = entity.runtimeState.escapeHeading
      if heading and not earlyRadial[entity.id] then earlyRadial[entity.id] = heading.radialWeight end
      if heading then lateRadial[entity.id] = heading.radialWeight end
      if entity.runtimeState.state ~= "FLEE" then exitTicks[entity.id] = tick end
    end
  end
end

local distinctExitTicks = {}
for _, entity in ipairs(actors) do
  assertTrue(exitTicks[entity.id] ~= nil, "every actor should eventually leave FLEE")
  assertTrue(entity.runtimeState.firstOrdinaryDecisionTick == exitTicks[entity.id]
      and entity.runtimeState.firstOrdinaryState ~= "FLEE",
    "FLEE exit should record the first ordinary decision and state")
  assertTrue(lateRadial[entity.id] < earlyRadial[entity.id],
    "escape urgency should decline before each actor returns to ordinary behavior")
  distinctExitTicks[exitTicks[entity.id]] = true
end
local exitTickCount = 0
for _ in pairs(distinctExitTicks) do exitTickCount = exitTickCount + 1 end
assertTrue(exitTickCount > 1, "individual fear trajectories should produce asynchronous recovery")

for _, entity in ipairs(actors) do
  local seekTick = exitTicks[entity.id] + 220
  local search = FlockSearch.update(entity, positions[entity.id], {}, seekTick, { perceptionRadius = 5 })
  assertTrue(search.reassemblyPressure > 0 and search.utility > 20,
    "isolated dependent actors should develop substantial post-FLEE flock pressure")
  assertTrue(search.cueSource == "last_seen" and search.targetEntityId ~= nil,
    "post-panic regrouping should retain legal pre-dispersion spatial history")
  Controller.tick(entity, {}, nil, {
    threatAssessment = { primaryThreatId = nil },
    targetPositions = {},
    position = positions[entity.id],
    currentFear = 0,
    flockSearch = search,
    allowTargeting = false
  }, seekTick)
  assertTrue(entity.runtimeState.state == "SEEK_FLOCK"
      and entity.runtimeState.firstSeekFlockTick == seekTick,
    string.format("existing utility selection should transition an isolated dependent actor into SEEK_FLOCK (actor=%s state=%s seek=%.2f selected=%.2f entered=%s)",
      entity.id, tostring(entity.runtimeState.state), search.utility,
      entity.runtimeState.selectedScore or -1, tostring(entity.runtimeState.stateEnteredTick)))
end

local reunited = FlockSearch.update(actors[1], positions[actors[1].id], {
  { entity = actors[2], position = positions[actors[1].id], perceived = true }
}, exitTicks[actors[1].id] + 221, { perceptionRadius = 5 })
assertTrue(reunited.reassemblyPressure == 0,
  "reunion should clear recovery-specific flock pressure instead of preserving a timer-only need")

return true