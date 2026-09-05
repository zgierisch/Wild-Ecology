local MovementClaims = require("src.world.movement_claims")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local events = {}
local claims = MovementClaims.new(function(action, claim, reason, conflict)
  events[#events + 1] = {
    action = action,
    actorId = claim.actorId,
    reason = reason,
    conflict = conflict
  }
end)

local accepted, claimA = claims:publish({
  actorId = "a", fromX = 10, fromY = 14, toX = 9, toY = 14,
  intent = "SEEK_FLOCK", urgency = 0.2, routeCommitted = true
}, 1)
assertEquals(accepted, true, "a valid one-tile WALK should publish a claim")
assertEquals(claimA.establishedTick, 1, "claim should retain establishment time")
assertEquals(claims:claimForActor("a"), claimA, "claim should be indexed by actor")

local wonAgain, sameClaim = claims:publish({
  actorId = "a", fromX = 10, fromY = 14, toX = 9, toY = 14,
  intent = "SEEK_FLOCK", urgency = 0.2, routeCommitted = true
}, 2)
assertEquals(wonAgain, true, "revalidating the same edge should retain ownership")
assertEquals(sameClaim, claimA, "existing claim inertia should preserve claim identity")
assertEquals(sameClaim.establishedTick, 1, "revalidation must not reset claim age")

local sameDestination, sameType, incumbent = claims:publish({
  actorId = "b", fromX = 9, fromY = 15, toX = 9, toY = 14,
  intent = "FLEE", urgency = 0.8
}, 2)
assertEquals(sameDestination, false, "a later same-destination claimant should yield")
assertEquals(sameType, "SAME_DESTINATION", "same destination should be classified")
assertEquals(incumbent.actorId, "a", "existing ownership should have short-term inertia")
assertEquals(claims:claimForActor("a"), claimA, "loser must not steal incumbent ownership")

local headOn, headOnType = claims:publish({
  actorId = "c", fromX = 9, fromY = 14, toX = 10, toY = 14,
  intent = "FLEE", urgency = 0.8
}, 2)
assertEquals(headOn, false, "head-on swaps should deterministically yield to incumbent")
assertEquals(headOnType, "HEAD_ON_EDGE_SWAP", "reverse directed edges should be classified")
claims:publish({
  actorId = "c", fromX = 9, fromY = 14, toX = 10, toY = 14,
  intent = "FLEE", urgency = 0.8
}, 3)
assertEquals(claims:snapshot().headOnConflicts, 1,
  "repeated identical head-on retries should not multiply conflict transitions")

claims:clear("a", 3, "MOVEMENT_COMPLETED")
assertEquals(claims:claimForActor("a"), nil, "movement completion should clear the claim")

claims:publish({ actorId = "reject", fromX = 1, fromY = 1, toX = 0, toY = 1 }, 4)
claims:validateActor("reject", {
  movementRequest = { traversalMode = "WALK", destinationX = 0, destinationY = 1, rejectionReason = "entity" },
  motion = { active = false }
}, { cellX = 1, cellY = 1 }, 4)
assertEquals(claims:claimForActor("reject"), nil, "actuator rejection should clear immediately")

claims:publish({ actorId = "reset", fromX = 2, fromY = 1, toX = 1, toY = 1 }, 5)
claims:clearAll(6, "MAP_CHANGED")
assertEquals(claims:claimForActor("reset"), nil, "map/reset cleanup should clear all claims")

local snapshot = claims:snapshot()
assertEquals(snapshot.movementClaimsPublished, 3, "published counter should count accepted claims")
assertEquals(snapshot.destinationClaimConflicts, 1, "same-destination conflicts should be counted")
assertEquals(snapshot.headOnConflicts, 1, "head-on conflicts should be counted")
assertEquals(snapshot.claimArbitrations, 2, "both conflict types should arbitrate")
assertEquals(snapshot.claimPreemptions, 0, "incumbent inertia should avoid comparable preemption")
assertEquals(snapshot.activeMovementClaims, 0, "cleanup should leave no active claims")

local flow = MovementClaims.new()
assertEquals(flow:publish({ actorId = "a", fromX = 10, fromY = 14, toX = 9, toY = 14 }, 1), true,
  "front actor should claim its next cell")
assertEquals(flow:publish({ actorId = "b", fromX = 11, fromY = 14, toX = 10, toY = 14 }, 1), true,
  "following actor should claim the cell being vacated ahead")
assertEquals(flow:publish({ actorId = "c", fromX = 12, fromY = 14, toX = 11, toY = 14 }, 1), true,
  "third actor should extend a same-direction flow without conflict")
assertEquals(flow:snapshot().activeMovementClaims, 3,
  "three-actor flow should preserve all one-edge claims")
assertEquals(flow:snapshot().destinationClaimConflicts, 0,
  "vacated-cell chains should not be classified as same-destination conflicts")

local fleeFirst = MovementClaims.new()
local fleeRuntime = { primaryThreatId = "player", directThreatId = "player" }
assertEquals(fleeFirst:publish({
  actorId = "urgent-flee", fromX = 5, fromY = 4, toX = 5, toY = 5,
  intent = "FLEE", urgency = 0.9
}, 1), true, "urgency-sorted FLEE actor should establish the first unclaimed edge")
local seekWon, seekConflict = fleeFirst:publish({
  actorId = "seeker", fromX = 4, fromY = 5, toX = 5, toY = 5,
  intent = "SEEK_FLOCK", urgency = 0.1
}, 1)
assertEquals(seekWon, false, "later SEEK_FLOCK contender should yield to established FLEE claim")
assertEquals(seekConflict, "SAME_DESTINATION", "FLEE/SEEK contention should remain generic")
assertEquals(fleeRuntime.primaryThreatId, "player", "claim arbitration must not change threat identity")
assertEquals(fleeRuntime.directThreatId, "player", "claim arbitration must not change direct threat memory")

local cleanup = MovementClaims.new()
cleanup:publish({ actorId = "complete", fromX = 2, fromY = 2, toX = 1, toY = 2 }, 10)
cleanup:validateActor("complete", {
  movementRequest = { traversalMode = "WALK", destinationX = 1, destinationY = 2 },
  motion = { active = false, justCompleted = true }
}, { cellX = 1, cellY = 2 }, 11)
assertEquals(cleanup:claimForActor("complete"), nil, "completed movement should clear")

cleanup:publish({ actorId = "cancel", fromX = 2, fromY = 2, toX = 1, toY = 2 }, 20)
cleanup:validateActor("cancel", { motion = { active = false } }, { cellX = 2, cellY = 2 }, 21)
assertEquals(cleanup:claimForActor("cancel"), nil, "canceled request or intent change should clear")

cleanup:publish({ actorId = "stale", fromX = 2, fromY = 2, toX = 1, toY = 2 }, 30)
cleanup:validateActor("stale", {
  movementRequest = { traversalMode = "WALK", destinationX = 1, destinationY = 2 },
  motion = { active = true, destinationX = 1, destinationY = 2 }
}, { cellX = 2, cellY = 2 }, 210)
local activeClaim = cleanup:claimForActor("stale")
assertEquals(activeClaim ~= nil, true,
  "total claim age must not expire a claim backed by matching active stock motion")
assertEquals(activeClaim.establishedTick, 30,
  "active validation should preserve the original establishment time")
assertEquals(activeClaim.lastValidatedTick, 210,
  "active validation should refresh the claim's evidence timestamp")
local stoleActiveDestination, activeConflict = cleanup:publish({
  actorId = "contender", fromX = 1, fromY = 1, toX = 1, toY = 2
}, 210)
assertEquals(stoleActiveDestination, false,
  "another actor must not acquire a destination during matching active motion")
assertEquals(activeConflict, "SAME_DESTINATION",
  "active destination ownership should remain visible to arbitration")
cleanup:validateActor("stale", { motion = { active = false } }, { cellX = 2, cellY = 2 }, 211)
assertEquals(cleanup:claimForActor("stale"), nil,
  "normal cleanup should resume when active motion and its request no longer back the claim")

cleanup:publish({ actorId = "expired", fromX = 3, fromY = 2, toX = 2, toY = 2 }, 300)
cleanup:validateActor("expired", {
  movementRequest = { traversalMode = "WALK", destinationX = 2, destinationY = 2 },
  motion = { active = false }
}, { cellX = 3, cellY = 2 }, 480)
assertEquals(cleanup:snapshot().claimExpirations, 1,
  "stale request-only cleanup should retain an aggregate expiration counter")

local invalidStay = cleanup:publish({ actorId = "stay", fromX = 2, fromY = 2, toX = 2, toY = 2 }, 1)
assertEquals(invalidStay, false, "STAY/no-movement must never publish a claim")

local ordered = MovementClaims.new()
ordered:publish({
  actorId = "late-owner", fromX = 4, fromY = 4, toX = 5, toY = 4
}, 1)
local actors = {
  ["late-owner"] = {
    runtime = { motion = { active = false } },
    position = { cellX = 4, cellY = 4 }
  }
}
ordered:validateAll(function(actorId)
  local actor = actors[actorId]
  return actor and actor.runtime or nil, actor and actor.position or nil
end, 2)
assertEquals(ordered:claimForActor("late-owner"), nil,
  "pre-evaluation validation should clear a canceled claim before another actor observes it")
local entersReleasedCell = ordered:publish({
  actorId = "early-contender", fromX = 5, fromY = 3, toX = 5, toY = 4
}, 2)
assertEquals(entersReleasedCell, true,
  "evaluation order must not expose a canceled later actor as a physical reservation")

return true
