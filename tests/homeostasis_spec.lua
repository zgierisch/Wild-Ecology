local Controller = require("src.behavior.controller")
local Motivation = require("src.behavior.motivation")
local Social = require("src.behavior.social")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function targetContext(targetId, distance, novelty)
  return {
    hasTarget = true,
    purposefulTarget = true,
    targetEntityId = targetId,
    candidates = { { id = targetId, distance = distance, novelty = novelty } },
    position = { cellX = 0, cellY = 0 },
    targetPositions = { [targetId] = { cellX = distance, cellY = 0 } },
    investigateRadius = 3,
    goalRadius = 1,
    allowTargeting = true
  }
end

local curious = {
  id = "homeostasis-curious",
  temperament = { curiosity = 1, sociability = 0, boldness = 0.5 },
  rawStats = { independence = 0.5 },
  relationships = {},
  runtimeState = { state = "SETTLED", stateEnteredTick = 0 }
}
local novelRelationship = { familiarity = 0, trust = 0, affinity = 0 }
assertEquals(Controller.tick(curious, novelRelationship, 5,
  targetContext("novel-b", 5, 100), 40), "INVESTIGATE",
  "a sufficiently novel stimulus should disturb passive equilibrium")
assertEquals(Controller.tick(curious, novelRelationship, 2,
  targetContext("novel-b", 2, 100), 41), "SETTLED",
  "completed investigation should return to passive equilibrium")
assertTrue(Motivation.satisfaction(curious, "curiosity", 41) >= 0.8,
  "investigation should discharge the broader curiosity drive")
assertEquals(Controller.tick(curious, { familiarity = 0 }, 5,
  targetContext("novel-c", 5, 100), 71), "SETTLED",
  "curiosity satisfaction should prevent automatic novel-target chaining")

local social = {
  id = "homeostasis-social",
  temperament = { curiosity = 0, sociability = 1, boldness = 0.5 },
  rawStats = { independence = 0.2 },
  relationships = {},
  runtimeState = { state = "SETTLED", stateEnteredTick = 0 }
}
local closeFriend = { familiarity = 100, trust = 100, affinity = 100 }
for tick = 30, 300, 30 do
  local state = Controller.tick(social, closeFriend, 1,
    targetContext("friend", 1, 0), tick)
  if tick <= 180 then
    assertEquals(state, "SETTLED",
      "acceptable social proximity should sustain passive equilibrium")
  end
  assertTrue(state ~= "APPROACH",
    "high affinity at acceptable proximity must not create an APPROACH loop")
end

local seeker = {
  id = "homeostasis-seeker",
  species = "PIDGEY",
  ecology = { family = "flock-a", desiredGroupSize = 3 },
  temperament = { curiosity = 0, sociability = 1, boldness = 0.5 },
  rawStats = { independence = 0 },
  relationships = {},
  runtimeState = { state = "SETTLED", stateEnteredTick = 0 }
}
local isolated = {
  hasTarget = false,
  purposefulTarget = false,
  position = { cellX = 0, cellY = 0 },
  targetPositions = {},
  flockSearch = {
    utility = 100, isolationPressure = 1, nearbySameSpecies = 0,
    cueSource = "social_signal", cueDirection = "RIGHT",
    cuePosition = { cellX = 6, cellY = 0 }, targetEntityId = "flock-b"
  }
}
assertEquals(Controller.tick(seeker, {}, nil, isolated, 40), "SEEK_FLOCK",
  "actual isolation pressure should disturb passive equilibrium")
local reunited = {
  hasTarget = false,
  purposefulTarget = false,
  position = { cellX = 5, cellY = 0 },
  targetPositions = {},
  flockSearch = {
    utility = 0, isolationPressure = 0, nearbySameSpecies = 1,
    cueSource = "perceived", cuePosition = { cellX = 6, cellY = 0 },
    targetEntityId = "flock-b"
  }
}
assertEquals(Controller.tick(seeker, {}, nil, reunited, 41), "SETTLED",
  "reaching compatible company should discharge flock-seeking pressure")
local cohesionSatisfaction = Motivation.satisfaction(seeker, "cohesion", 41)
assertTrue(cohesionSatisfaction > 0,
  "flock reunion should record cohesion satisfaction status="
    .. tostring(seeker.runtimeState.intentEpisode
      and seeker.runtimeState.intentEpisode.status)
    .. " stored=" .. tostring(seeker.runtimeState.motivationSatisfaction
      and seeker.runtimeState.motivationSatisfaction.cohesion
      and seeker.runtimeState.motivationSatisfaction.cohesion.value))

local wanderer = {
  id = "homeostasis-wanderer",
  temperament = { curiosity = 0, sociability = 0, boldness = 0.5 },
  rawStats = { independence = 0.5 },
  runtimeState = {
    state = "TARGET",
    stateEnteredTick = 0,
    targetDestination = { id = "target_right", cellX = 3, cellY = 3 },
    motion = { active = false }
  }
}
assertEquals(Controller.tick(wanderer, {}, nil, {
  hasTarget = false, purposefulTarget = false,
  position = { cellX = 3, cellY = 3 }, targetPositions = {}
}, 40), "SETTLED", "completed wandering should settle")
assertTrue(Motivation.satisfaction(wanderer, "exploration", 40) > 0,
  "completed wandering should discharge restlessness")

local settledA = {
  id = "settled-a", species = "PIDGEY",
  ecology = { family = "shared", socialModifier = 0.25,
    familySocialModifier = 1.25 },
  temperament = { curiosity = 0, sociability = 0.5, boldness = 0.5 },
  rawStats = { independence = 0.5 }, relationships = {},
  runtimeState = { state = "SETTLED", stateEnteredTick = 0 }
}
local settledB = {
  id = "settled-b", species = "PIDGEY",
  ecology = { family = "shared", socialModifier = 0.25,
    familySocialModifier = 1.25 },
  temperament = { curiosity = 0, sociability = 0.5, boldness = 0.5 },
  rawStats = { independence = 0.5 }, relationships = {},
  runtimeState = { state = "SETTLED", stateEnteredTick = 0 }
}
for tick = 1, 5000 do
  local contextA = targetContext(settledB.id, 1, 0)
  local contextB = targetContext(settledA.id, 1, 0)
  contextA.allowTargeting = false
  contextB.allowTargeting = false
  assertEquals(Controller.tick(settledA, settledA.relationships[settledB.id],
    1, contextA, tick), "SETTLED", "settled contact should remain stable")
  assertEquals(Controller.tick(settledB, settledB.relationships[settledA.id],
    1, contextB, tick), "SETTLED", "settled contact should remain reciprocal")
  Social.observeNearby(settledA, settledB.id, 1, tick, settledB)
  Social.observeNearby(settledB, settledA.id, 1, tick, settledA)
end
assertTrue(settledA.relationships[settledB.id].familiarity > 0,
  "relationship exposure must continue while settled")
assertTrue(settledB.relationships[settledA.id].affinity > 0,
  "directed affinity exposure must continue without locomotion")

print(string.format(
  "HOMEOSTASIS curiosity=%.3f cohesion=%.3f settledContactTicks=5000 familiarity=%.2f affinity=%.2f",
  Motivation.satisfaction(curious, "curiosity", 71),
  Motivation.satisfaction(seeker, "cohesion", 41),
  settledA.relationships[settledB.id].familiarity,
  settledB.relationships[settledA.id].affinity))

return true