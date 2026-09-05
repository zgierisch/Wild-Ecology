local Controller = require("src.behavior.controller")
local NavigationGoal = require("src.navigation.navigation_goal")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local actor = {
  id = "navigation-episode-target-to-approach",
  temperament = { curiosity = 0, sociability = 1, boldness = 0.5 },
  rawStats = { independence = 0 },
  runtimeState = {
    state = "TARGET",
    stateEnteredTick = 0,
    recentCommittedCells = {
      { key = "0,0", targetEntityId = "target_right", direction = "RIGHT" },
      { key = "1,0", targetEntityId = "target_left", direction = "LEFT" },
      { key = "0,0", targetEntityId = "target_right", direction = "RIGHT" }
    },
    motion = { active = false }
  }
}
local relationship = { familiarity = 100, trust = 100, affinity = 100 }
local function approachContext(position, distance)
  return {
    hasTarget = true,
    purposefulTarget = true,
    allowTargeting = true,
    targetEntityId = "friend",
    candidates = { { id = "friend", distance = distance, novelty = 0 } },
    position = position,
    targetPositions = { friend = { cellX = 4, cellY = 0 } },
    goalRadius = 1,
    mapId = "NAVIGATION_EPISODE"
  }
end

assertEquals(Controller.tick(actor, relationship, 4,
  approachContext({ cellX = 0, cellY = 0 }, 4), 40), "APPROACH",
  "trusted target should legitimately replace ambient TARGET")
assertEquals(actor.runtimeState.movementRequest.direction, "RIGHT",
  "new APPROACH should request its first valid step")

actor.runtimeState.motion = { active = false, justCompleted = true }
local stateAfterFirstApproachStep = Controller.tick(actor, relationship, 3,
  approachContext({ cellX = 1, cellY = 0 }, 3), 41)
assertEquals(stateAfterFirstApproachStep, "APPROACH",
  "TARGET history must not make the first APPROACH step look like an ABAB cycle")
assertEquals(actor.runtimeState.navigationAvoidTargetId, nil,
  "unrelated TARGET history must not suppress the new APPROACH target")

local seeker = {
  id = "navigation-episode-seek-to-approach",
  species = "PIDGEY",
  ecology = { family = "flock-a", locomotion = { WALK = true } },
  temperament = { curiosity = 0, sociability = 1, boldness = 0.5 },
  rawStats = { independence = 0 },
  runtimeState = {
    state = "SEEK_FLOCK",
    stateEnteredTick = 0,
    targetEntityId = "old-flock-target",
    recentCommittedCells = {
      { key = "0,0", targetEntityId = "old-flock-target", direction = "RIGHT" },
      { key = "1,0", targetEntityId = "old-flock-target", direction = "LEFT" },
      { key = "0,0", targetEntityId = "old-flock-target", direction = "RIGHT" }
    },
    navigation = {
      goalSignature = "PROXIMITY:perceived:old-flock-target:1:0",
      targetEntityId = "old-flock-target"
    },
    motion = { active = false }
  }
}
local completedSearchContext = approachContext({ cellX = 0, cellY = 0 }, 4)
completedSearchContext.flockSearch = {
  utility = 0,
  nearbySameSpecies = 1,
  cueSource = "perceived",
  cuePosition = { cellX = 1, cellY = 0 },
  targetEntityId = "old-flock-target"
}
assertEquals(Controller.tick(seeker, relationship, 4, completedSearchContext, 40),
  "APPROACH", "completed SEEK_FLOCK should yield to the trusted target")
assertEquals(seeker.runtimeState.navigation.ownerBehavior, "APPROACH",
  "SEEK_FLOCK should replace its route owner with the new APPROACH episode")
assertEquals(seeker.runtimeState.navigation.targetEntityId, "friend",
  "the replacement navigation episode should own the new behavior target")

seeker.runtimeState.motion = { active = false, justCompleted = true }
local stateAfterSearchHandoff = Controller.tick(seeker, relationship, 3,
  approachContext({ cellX = 1, cellY = 0 }, 3), 41)
assertEquals(stateAfterSearchHandoff, "APPROACH",
  "SEEK_FLOCK history must not make the first APPROACH step look cyclic")
assertEquals(seeker.runtimeState.navigationAvoidTargetId, nil,
  "completed flock-search history must not suppress the new APPROACH target")

local function newApproacher(id)
  return {
    id = id,
    temperament = { curiosity = 0, sociability = 1, boldness = 0.5 },
    rawStats = { independence = 0 },
    runtimeState = { state = "APPROACH", stateEnteredTick = 0, targetEntityId = "friend",
      motion = { active = false } }
  }
end

local steady = newApproacher("same-approach-owner")
steady.runtimeState.recentCommittedCells = {
  { key = "0,0", targetEntityId = "friend", direction = "RIGHT" },
  { key = "1,0", targetEntityId = "friend", direction = "LEFT" },
  { key = "0,0", targetEntityId = "friend", direction = "RIGHT" }
}
Controller.tick(steady, relationship, 4,
  approachContext({ cellX = 0, cellY = 0 }, 4), 40)
assertEquals(#steady.runtimeState.recentCommittedCells, 3,
  "same-state same-target deliberation should preserve anti-oscillation evidence")
steady.runtimeState.motion = { active = false, justCompleted = true }
steady.runtimeState.movementRequest = { direction = "LEFT" }
assertEquals(Controller.tick(steady, relationship, 3,
  approachContext({ cellX = 1, cellY = 0 }, 3), 41), "IDLE",
  "a real ABAB cycle within one APPROACH episode should still trigger recovery")
assertEquals(steady.runtimeState.navigationAvoidTargetId, "friend",
  "true same-episode cycling should temporarily suppress its target")

local retargeted = newApproacher("retargeted-approach-owner")
retargeted.runtimeState.recentCommittedCells = {
  { key = "0,0", targetEntityId = "friend", direction = "RIGHT" },
  { key = "1,0", targetEntityId = "friend", direction = "LEFT" }
}
retargeted.runtimeState.goalSatisfiedSinceTick = 12
retargeted.runtimeState.spatialGoal = { targetEntityId = "friend" }
local replacementContext = approachContext({ cellX = 0, cellY = 0 }, 4)
replacementContext.targetEntityId = "new-friend"
replacementContext.candidates = { { id = "new-friend", distance = 4, novelty = 0 } }
replacementContext.targetPositions = {
  friend = { cellX = 3, cellY = 0 },
  ["new-friend"] = { cellX = 4, cellY = 0 }
}
Controller.tick(retargeted, relationship, 4, replacementContext, 40)
assertEquals(retargeted.runtimeState.state, "APPROACH",
  "target replacement may retain the high-level APPROACH behavior")
assertEquals(retargeted.runtimeState.targetEntityId, "new-friend",
  "same-state target replacement should transfer navigation ownership")
assertEquals(#retargeted.runtimeState.recentCommittedCells, 0,
  "same-state target replacement should discard the old target's history")
assertEquals(retargeted.runtimeState.intentEpisode.targetId, "new-friend",
  "same-state target replacement should restart target-specific intent bookkeeping")
assertEquals(retargeted.runtimeState.intentEpisode.progress, 0,
  "replacement target must not inherit prior intent progress")
assertEquals(retargeted.runtimeState.goalSatisfiedSinceTick, nil,
  "replacement target must not inherit prior goal satisfaction timing")

local search = {
  utility = 100,
  isolationPressure = 1,
  nearbySameSpecies = 0,
  cueSource = "social_signal",
  cueDirection = "EAST",
  targetEntityId = "hidden-family"
}
local searchGoalSignature = NavigationGoal.signature(
  NavigationGoal.fromFlockSearch(search))
local routeOwner = {
  id = "same-search-owner",
  species = "PIDGEY",
  ecology = { family = "flock-a", locomotion = { WALK = true } },
  temperament = { curiosity = 0, sociability = 1, boldness = 0.5 },
  rawStats = { independence = 0 },
  runtimeState = {
    state = "SEEK_FLOCK",
    stateEnteredTick = 0,
    targetEntityId = "hidden-family",
    recentCommittedCells = {
      { key = "0,0", targetEntityId = "hidden-family", direction = "RIGHT" },
      { key = "1,0", targetEntityId = "hidden-family", direction = "LEFT" }
    },
    navigation = {
      goalSignature = searchGoalSignature,
      mapId = "SEARCH_A",
      blockedEdges = { old_edge = true },
      replanReason = "EXECUTION_REJECTED"
    },
    motion = { active = false }
  }
}
local searchContext = {
  executionOnly = true,
  position = { cellX = 0, cellY = 0 },
  mapId = "SEARCH_A",
  flockSearch = search
}
Controller.executeCurrentIntent(routeOwner, searchContext, 40)
assertEquals(#routeOwner.runtimeState.recentCommittedCells, 2,
  "same-goal route establishment should preserve cycle evidence")
assertEquals(routeOwner.runtimeState.navigation.blockedEdges.old_edge, true,
  "same-goal route establishment should preserve learned blocked edges")

searchContext.flockSearch = {
  utility = 100,
  isolationPressure = 1,
  nearbySameSpecies = 0,
  cueSource = "social_signal",
  cueDirection = "WEST",
  targetEntityId = "hidden-family"
}
Controller.executeCurrentIntent(routeOwner, searchContext, 41)
assertEquals(#routeOwner.runtimeState.recentCommittedCells, 0,
  "material SEEK_FLOCK goal replacement should discard prior cycle evidence")
assertEquals(routeOwner.runtimeState.navigation.blockedEdges.old_edge, nil,
  "material goal replacement should discard route-local blocked edges")

routeOwner.runtimeState.recentCommittedCells = {
  { key = "9,9", targetEntityId = "hidden-family", direction = "LEFT" }
}
searchContext.mapId = "SEARCH_B"
Controller.executeCurrentIntent(routeOwner, searchContext, 42)
assertEquals(#routeOwner.runtimeState.recentCommittedCells, 0,
  "map replacement should discard coordinate-scoped cycle evidence")

for episode = 1, 100 do
  routeOwner.runtimeState.recentCommittedCells = {
    { key = episode .. ",0", targetEntityId = "hidden-family", direction = "RIGHT" }
  }
  routeOwner.runtimeState.navigation.blockedEdges["episode-" .. episode] = true
  searchContext.flockSearch.cueDirection = episode % 2 == 1 and "EAST" or "WEST"
  Controller.executeCurrentIntent(routeOwner, searchContext, 42 + episode)
  assertEquals(#routeOwner.runtimeState.recentCommittedCells, 0,
    "repeated logical goal replacement must not retain cycle history")
  assertEquals(routeOwner.runtimeState.navigation.blockedEdges["episode-" .. episode], nil,
    "repeated logical goal replacement must not retain blocked edges")
end

local movingHandoff = {
  id = "moving-search-handoff",
  species = "PIDGEY",
  ecology = { family = "flock-a", locomotion = { WALK = true } },
  temperament = { curiosity = 0, sociability = 1, boldness = 0.5 },
  rawStats = { independence = 0 },
  runtimeState = {
    state = "SEEK_FLOCK",
    stateEnteredTick = 0,
    targetEntityId = "old-flock-target",
    recentCommittedCells = { { key = "0,0", targetEntityId = "old-flock-target" } },
    navigation = { goalSignature = "old", blockedEdges = { old = true } },
    spatialGoal = { targetEntityId = "old-flock-target" },
    goalSatisfied = true,
    goalSatisfiedSinceTick = 12,
    goalSelfPosition = { cellX = 0, cellY = 0 },
    goalTargetPosition = { cellX = 1, cellY = 0 },
    movementRequest = { direction = "RIGHT", goalKind = "SEEK_FLOCK" },
    motion = { active = true, destinationX = 1, destinationY = 0 },
    rejectedMoves = {
      LEFT = { mapId = "NAVIGATION_EPISODE", cellX = 0, cellY = 0, reason = "tile" }
    }
  }
}
local movingContext = approachContext({ cellX = 0, cellY = 0 }, 4)
movingContext.flockSearch = {
  utility = 0,
  nearbySameSpecies = 1,
  cueSource = "perceived",
  cuePosition = { cellX = 1, cellY = 0 },
  targetEntityId = "old-flock-target"
}
assertEquals(Controller.tick(movingHandoff, relationship, 4, movingContext, 40),
  "APPROACH", "active stock motion should not prevent a high-level owner handoff")
assertEquals(movingHandoff.runtimeState.motion.active, true,
  "accepted physical motion should survive the high-level owner handoff")
assertEquals(movingHandoff.runtimeState.movementRequest, nil,
  "the prior owner's queued movement request should not survive the handoff")
assertEquals(movingHandoff.runtimeState.navigation, nil,
  "the prior SEEK_FLOCK route should not survive the handoff")
assertEquals(#movingHandoff.runtimeState.recentCommittedCells, 0,
  "the prior episode's cycle history should not survive the handoff")
assertEquals(movingHandoff.runtimeState.spatialGoal, nil,
  "the prior episode's resolved spatial goal should not survive the handoff")
assertEquals(movingHandoff.runtimeState.goalSatisfiedSinceTick, nil,
  "the prior episode's satisfaction timer should not survive the handoff")
assertEquals(movingHandoff.runtimeState.rejectedMoves.LEFT.reason, "tile",
  "actuator-owned static collision knowledge should survive the handoff")

return true
