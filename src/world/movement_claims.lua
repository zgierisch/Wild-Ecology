local WorldSemantics = require("src.world.world_semantics")

local MovementClaims = {}
MovementClaims.__index = MovementClaims

local STALE_TICKS = 180

local function edgeKey(fromX, fromY, toX, toY)
  return WorldSemantics.edgeKey(fromX, fromY, toX, toY)
end

local function destinationKey(claim)
  return WorldSemantics.cellKey(claim.toX, claim.toY)
end

local function sameEdge(claim, proposal)
  return claim and proposal
    and claim.fromX == proposal.fromX and claim.fromY == proposal.fromY
    and claim.toX == proposal.toX and claim.toY == proposal.toY
end

function MovementClaims.new(eventSink)
  return setmetatable({
    byActor = {},
    byDestination = {},
    byEdge = {},
    conflictByActor = {},
    eventSink = eventSink,
    counters = {
      movementClaimsPublished = 0,
      movementClaimsCleared = 0,
      destinationClaimConflicts = 0,
      headOnConflicts = 0,
      vacatingCellWaits = 0,
      claimArbitrations = 0,
      claimPreemptions = 0,
      claimExpirations = 0,
      claimLifetimeTicks = 0
    }
  }, MovementClaims)
end

function MovementClaims:_event(action, claim, reason, conflict)
  if self.eventSink then
    self.eventSink(action, claim, reason, conflict)
  end
end

function MovementClaims:_remove(claim)
  if not claim then return end
  self.byActor[claim.actorId] = nil
  local destinationClaims = self.byDestination[destinationKey(claim)]
  if destinationClaims then
    destinationClaims[claim.actorId] = nil
    if next(destinationClaims) == nil then
      self.byDestination[destinationKey(claim)] = nil
    end
  end
  self.byEdge[edgeKey(claim.fromX, claim.fromY, claim.toX, claim.toY)] = nil
end

function MovementClaims:clear(actorId, tick, reason, action)
  self.conflictByActor[actorId] = nil
  local claim = self.byActor[actorId]
  if not claim then return false end
  self:_remove(claim)
  self.counters.movementClaimsCleared = self.counters.movementClaimsCleared + 1
  if action == "EXPIRED" then
    self.counters.claimExpirations = self.counters.claimExpirations + 1
  end
  self.counters.claimLifetimeTicks = self.counters.claimLifetimeTicks
    + math.max(0, (tick or claim.lastValidatedTick or claim.establishedTick)
      - claim.establishedTick)
  self:_event(action or "CLEARED", claim, reason or "CLEARED")
  return true
end

function MovementClaims:clearAll(tick, reason)
  local actorIds = {}
  for actorId in pairs(self.byActor) do actorIds[#actorIds + 1] = actorId end
  table.sort(actorIds, function(left, right) return tostring(left) < tostring(right) end)
  for _, actorId in ipairs(actorIds) do
    self:clear(actorId, tick, reason or "RESET")
  end
end

function MovementClaims:claimForActor(actorId)
  return self.byActor[actorId]
end

function MovementClaims:claimsForDestination(cellKey)
  return self.byDestination[cellKey] or {}
end

function MovementClaims:conflict(actorId, fromX, fromY, toX, toY)
  local reverse = self.byEdge[edgeKey(toX, toY, fromX, fromY)]
  if reverse and reverse.actorId ~= actorId then
    return "HEAD_ON_EDGE_SWAP", reverse
  end
  local destinationClaims = self.byDestination[WorldSemantics.cellKey(toX, toY)]
  local firstId, firstClaim
  for otherId, claim in pairs(destinationClaims or {}) do
    if otherId ~= actorId and (firstId == nil or tostring(otherId) < tostring(firstId)) then
      firstId, firstClaim = otherId, claim
    end
  end
  if firstClaim then return "SAME_DESTINATION", firstClaim end
  return nil, nil
end

function MovementClaims:stepCost(actorId, fromX, fromY, toX, toY)
  local conflictType = self:conflict(actorId, fromX, fromY, toX, toY)
  if conflictType == "HEAD_ON_EDGE_SWAP" then return 100, conflictType end
  if conflictType == "SAME_DESTINATION" then return 60, conflictType end
  return 0, nil
end

function MovementClaims:publish(proposal, tick)
  if not proposal or proposal.actorId == nil
    or proposal.fromX == nil or proposal.fromY == nil
    or proposal.toX == nil or proposal.toY == nil
    or math.abs(proposal.toX - proposal.fromX) + math.abs(proposal.toY - proposal.fromY) ~= 1 then
    return false, "INVALID_CLAIM"
  end
  local existing = self.byActor[proposal.actorId]
  if sameEdge(existing, proposal) then
    existing.lastValidatedTick = tick
    existing.intent = proposal.intent or existing.intent
    existing.urgency = proposal.urgency or existing.urgency
    existing.routeCommitted = proposal.routeCommitted == true
    return true, existing
  end
  if existing then self:clear(proposal.actorId, tick, "MOVE_CHANGED", "UPDATED") end

  local conflictType, incumbent = self:conflict(
    proposal.actorId, proposal.fromX, proposal.fromY, proposal.toX, proposal.toY)
  if incumbent then
    local conflictSignature = table.concat({
      tostring(conflictType), tostring(incumbent.actorId),
      tostring(proposal.fromX), tostring(proposal.fromY),
      tostring(proposal.toX), tostring(proposal.toY)
    }, ":")
    if self.conflictByActor[proposal.actorId] ~= conflictSignature then
      self.conflictByActor[proposal.actorId] = conflictSignature
      self.counters.claimArbitrations = self.counters.claimArbitrations + 1
      if conflictType == "HEAD_ON_EDGE_SWAP" then
        self.counters.headOnConflicts = self.counters.headOnConflicts + 1
      else
        self.counters.destinationClaimConflicts = self.counters.destinationClaimConflicts + 1
      end
      self:_event("WON_CONFLICT", incumbent, "EXISTING_CLAIM_INERTIA", {
        actorId = proposal.actorId,
        type = conflictType
      })
      self:_event("YIELDED", proposal, "EXISTING_CLAIM_INERTIA", {
        actorId = incumbent.actorId,
        type = conflictType
      })
    end
    return false, conflictType, incumbent
  end
  self.conflictByActor[proposal.actorId] = nil

  local claim = {
    actorId = proposal.actorId,
    fromX = proposal.fromX,
    fromY = proposal.fromY,
    toX = proposal.toX,
    toY = proposal.toY,
    intent = proposal.intent,
    urgency = proposal.urgency or 0,
    routeCommitted = proposal.routeCommitted == true,
    establishedTick = tick,
    lastValidatedTick = tick
  }
  self.byActor[claim.actorId] = claim
  local key = destinationKey(claim)
  self.byDestination[key] = self.byDestination[key] or {}
  self.byDestination[key][claim.actorId] = claim
  self.byEdge[edgeKey(claim.fromX, claim.fromY, claim.toX, claim.toY)] = claim
  self.counters.movementClaimsPublished = self.counters.movementClaimsPublished + 1
  self:_event("PUBLISHED", claim, "MOVEMENT_REQUEST")
  return true, claim
end

function MovementClaims:validateActor(actorId, runtime, position, tick)
  local claim = self.byActor[actorId]
  if not claim then return false end
  local motion = runtime and runtime.motion
  local request = runtime and runtime.movementRequest
  local requestMatches = request and request.traversalMode == "WALK"
    and request.rejectionReason == nil
    and request.destinationX == claim.toX and request.destinationY == claim.toY
  local motionMatches = motion and motion.active
    and motion.destinationX == claim.toX and motion.destinationY == claim.toY
  if motion and (motion.justCompleted or motion.recoveryReason) then
    return self:clear(actorId, tick,
      motion.justCompleted and "MOVEMENT_COMPLETED" or motion.recoveryReason)
  end
  if request and request.rejectionReason and request.rejectionReason ~= "MOVEMENT_ACTIVE" then
    return self:clear(actorId, tick, "MOVEMENT_REJECTED")
  end
  if position and position.cellX == claim.toX and position.cellY == claim.toY then
    return self:clear(actorId, tick, "DESTINATION_REACHED")
  end
  if not requestMatches and not motionMatches then
    return self:clear(actorId, tick, "MOVE_CANCELED")
  end
  claim.lastValidatedTick = tick
  if motionMatches then
    return false
  end
  if tick - claim.establishedTick >= STALE_TICKS then
    return self:clear(actorId, tick, "STALE_CLAIM", "EXPIRED")
  end
  return false
end

function MovementClaims:validateAll(resolveActor, tick)
  local actorIds = {}
  for actorId in pairs(self.byActor) do actorIds[#actorIds + 1] = actorId end
  table.sort(actorIds, function(left, right)
    return tostring(left) < tostring(right)
  end)
  for _, actorId in ipairs(actorIds) do
    local runtime, position = resolveActor(actorId)
    self:validateActor(actorId, runtime, position, tick)
  end
end

function MovementClaims:markVacatingWait()
  self.counters.vacatingCellWaits = self.counters.vacatingCellWaits + 1
end

function MovementClaims:snapshot()
  local result = {}
  for key, value in pairs(self.counters) do result[key] = value end
  result.activeMovementClaims = 0
  for _ in pairs(self.byActor) do result.activeMovementClaims = result.activeMovementClaims + 1 end
  result.averageClaimLifetimeTicks = result.movementClaimsCleared > 0
    and result.claimLifetimeTicks / result.movementClaimsCleared or 0
  return result
end

return MovementClaims