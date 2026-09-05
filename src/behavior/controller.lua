local Idle = require("src.behavior.states.idle")
local Settled = require("src.behavior.states.settled")
local Flee = require("src.behavior.states.flee")
local Target = require("src.behavior.states.target")
local EcologyPhysiology = require("src.species.ecology_physiology")
local Investigate = require("src.behavior.states.investigate")
local Approach = require("src.behavior.states.approach")
local SeekFlock = require("src.behavior.states.seek_flock")
local SatisfyNeed = require("src.behavior.states.satisfy_need")
local Rest = require("src.behavior.states.rest")
local ReturnHome = require("src.behavior.states.return_home")
local CircadianSystem = require("src.circadian.circadian_system")
local Utility = require("src.behavior.utility")
local Fear = require("src.behavior.fear")
local TargetSelector = require("src.behavior.target_selector")
local SpatialGoal = require("src.behavior.spatial_goal")
local Steering = require("src.behavior.steering")
local FleeEscape = require("src.behavior.flee_escape")
local EscapeHeading = require("src.behavior.escape_heading")
local FlockSearch = require("src.behavior.flock_search")
local IntentEpisode = require("src.behavior.intent_episode")
local LocomotionPolicy = require("src.behavior.locomotion_policy")
local Motivation = require("src.behavior.motivation")
local Drives = require("src.needs.drives")
local NeedStrategy = require("src.needs.need_strategy")
local RestSiteResolver = require("src.needs.rest_site_resolver")
local HomeReturn = require("src.behavior.home_return")
local HomeostasisTelemetry = require("src.debug.homeostasis_telemetry")
local NavigationGoal = require("src.navigation.navigation_goal")
local NavigationExecution = require("src.navigation.navigation_execution")
local NavigationEpisode = require("src.navigation.navigation_episode")
local WorldSemantics = require("src.world.world_semantics")
local HomeArea = require("src.world.home_area")
local Relationships = require("src.entities.relationships")

local Controller = {}

-- simulationTick advances once per successful ecology sync that reaches
-- WildEcology.init. The sync is update-hook driven, but world/semantics/save
-- gates and startup synchronization mean this is not an unconditional engine
-- frame clock. These durations are simulation-domain behavior policy only.
local MINIMUM_STATE_DURATION = 30
local SCORE_HYSTERESIS = 8
local NAVIGATION_CYCLE_COOLDOWN = 180
local FLEE_NO_PROGRESS_THRESHOLD = 3
local OCCUPANCY_STALE_WATCHDOG_TICKS = NAVIGATION_CYCLE_COOLDOWN
local FLEE_STATIC_REJECTION_THRESHOLD = 2
local FLEE_ESCAPE_DEPTH = 6
local FLEE_ESCAPE_EXPANSIONS = 96
local FLEE_RECENT_CELL_LIMIT = 6
local FLEE_INTENT_MIN_TICKS = 30
local FLEE_EXIT_SAFE_TICKS = 30
local FLEE_PLAN_WATCHDOG_TICKS = OCCUPANCY_STALE_WATCHDOG_TICKS
local TARGET_DIRECTIONS = {
  { id = "target_up", dx = 0, dy = -1 },
  { id = "target_down", dx = 0, dy = 1 },
  { id = "target_left", dx = -1, dy = 0 },
  { id = "target_right", dx = 1, dy = 0 }
}

-- See src/entities/entity.lua's seededUnitInterval comment: the game
-- runtime is LuaJIT, so no bitwise operators and doubles-only precision.
-- This modular-multiplication mix (odd constants comparable in size to
-- MIX_MODULUS) fixes the same drift bug for the +1-per-reroll wander
-- `counter` step.
local MIX_MODULUS = 67108864 -- 2^26

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function copyPosition(position)
  return position and { cellX = position.cellX, cellY = position.cellY } or nil
end

local function resolveEscapeReference(runtimeState, decisionContext, assessedThreatId, tick)
  local position = decisionContext.position
  local currentThreatPosition = assessedThreatId and decisionContext.targetPositions
    and decisionContext.targetPositions[assessedThreatId] or nil
  if assessedThreatId and currentThreatPosition then
    return {
      kind = "CURRENT_THREAT_POSITION",
      entityId = assessedThreatId,
      sourceThreatId = assessedThreatId,
      position = copyPosition(currentThreatPosition),
      confidence = 1
    }
  end

  local lastKnownAge = runtimeState.fleeThreatPositionTick
    and math.max(0, tick - runtimeState.fleeThreatPositionTick) or nil
  local lastKnownConfidence = lastKnownAge
    and clamp(1 - lastKnownAge / 90, 0, 1) or 0
  if runtimeState.fleeThreatPosition and lastKnownConfidence > 0 then
    return {
      kind = "LAST_KNOWN_THREAT_POSITION",
      entityId = nil,
      sourceThreatId = runtimeState.fleeThreatEntityId,
      position = copyPosition(runtimeState.fleeThreatPosition),
      confidence = lastKnownConfidence,
      age = lastKnownAge
    }
  end

  local socialBias = runtimeState.socialEscapeBias
  local socialConfidence = runtimeState.socialEscapeBiasConfidence or 0
  if decisionContext.socialAlarmTargetPosition and socialConfidence >= 0.2 then
    return {
      kind = "SOCIAL_ESCAPE_VECTOR",
      entityId = nil,
      position = copyPosition(decisionContext.socialAlarmTargetPosition),
      direction = {
        dx = socialBias and socialBias.dx or 0,
        dy = socialBias and socialBias.dy or 0
      },
      confidence = socialConfidence
    }
  end

  local heading = runtimeState.escapeHeading or {}
  local headingDx, headingDy = heading.dx or 0, heading.dy or 0
  return {
    kind = "HEADING_INERTIA",
    entityId = nil,
    position = position and {
      cellX = position.cellX - headingDx * 3,
      cellY = position.cellY - headingDy * 3
    } or nil,
    direction = { dx = headingDx, dy = headingDy },
    confidence = 0
  }
end

local function escapeThreatSourceId(reference)
  return reference and (reference.sourceThreatId or reference.entityId) or nil
end

local function sameDirectThreatSource(leftKind, leftSourceId, rightKind, rightSourceId)
  local directKinds = {
    CURRENT_THREAT_POSITION = true,
    LAST_KNOWN_THREAT_POSITION = true
  }
  return leftSourceId ~= nil and leftSourceId == rightSourceId
    and directKinds[leftKind] == true and directKinds[rightKind] == true
end

function Controller.isEmergencyThreat(runtimeState, assessment)
  local runtime = runtimeState or {}
  local threat = assessment or {}
  return threat.primaryThreatSevere == true
    or (threat.primaryThreatId ~= nil
      and (threat.primaryThreatDistance or math.huge) <= 1
      and (runtime.fearCurrent or 0) >= 0.85
      and threat.primaryThreatReason ~= "TRAINER_WARINESS")
end

function Controller.validateFleeProvenance(runtimeState, movementRequest)
  local runtime = runtimeState or {}
  local request = movementRequest or {}
  local reference = runtime.escapeReference or {}
  local primaryThreatId = runtime.threatAssessment
    and runtime.threatAssessment.primaryThreatId or request.primaryThreatId
  if reference.kind == "CURRENT_THREAT_POSITION" then
    if primaryThreatId == nil then
      return false, "CURRENT_REFERENCE_WITHOUT_PRIMARY_THREAT"
    end
    if reference.entityId ~= primaryThreatId then
      return false, "CURRENT_REFERENCE_THREAT_MISMATCH"
    end
  end
  if request.escapeReferenceKind == "CURRENT_THREAT_POSITION"
    and request.escapeReferenceEntityId ~= request.primaryThreatId then
    return false, "MOVEMENT_REFERENCE_THREAT_MISMATCH"
  end
  if request.targetEntityId ~= nil and request.targetEntityId ~= primaryThreatId then
    return false, "MOVEMENT_TARGET_NOT_PRIMARY_THREAT"
  end
  return true, nil
end

function Controller.reconsiderationReason(runtimeState, nowTick, debugPreset, targetAvailable)
  local runtime = runtimeState or {}
  local tick = nowTick or 0
  if runtime.lastDecisionTick == nil then
    return "INITIAL"
  end
  if runtime.lastSchedulerDebugPreset ~= debugPreset then
    return "DEBUG_PRESET_CHANGED"
  end
  local assessment = runtime.threatAssessment or {}
  if runtime.state ~= "FLEE" and Controller.isEmergencyThreat(runtime, assessment) then
    return assessment.primaryThreatReason == "HIGH_SEVERITY_EVENT"
      and "SEVERE_EVENT" or "EMERGENCY_THREAT"
  end
  local episode = runtime.intentEpisode
  if episode and episode.intent == runtime.state and episode.status ~= "ACTIVE" then
    return "INTENT_" .. tostring(episode.status)
  end
  if (runtime.state == "APPROACH" or runtime.state == "INVESTIGATE")
    and runtime.targetEntityId ~= nil and targetAvailable == false then
    return "TARGET_INVALIDATED"
  end
  if tick >= (runtime.nextDecisionTick or 0) then
    return "CADENCE"
  end
  return nil
end

function Controller.setHomeostasisSummarySink(sink)
  HomeostasisTelemetry.setSummarySink(sink)
end

local function updateFleeRecovery(runtimeState, assessedThreatId, distance, currentFear, desiredSafetyDistance)
  if runtimeState.state ~= "FLEE" then
    return false
  end
  local safeDistance = assessedThreatId == nil
    or (distance ~= nil and distance >= (desiredSafetyDistance or 1))
  local lowDirectFear = (runtimeState.fearDirect or 0) < 0.08
  local lowSocialFear = (runtimeState.fearSocial or 0) < 0.12
  local lowCurrentFear = (currentFear or 0) < 0.12
  local safeForExit = assessedThreatId == nil and safeDistance
    and lowDirectFear and lowSocialFear and lowCurrentFear
  local recoveryEligible = assessedThreatId == nil and safeDistance
    and (runtimeState.fearSocial or 0) < 0.22
  runtimeState.fleeRecoveryTicks = recoveryEligible
    and (runtimeState.fleeRecoveryTicks or 0) + 1 or 0
  local timeProgress = clamp((runtimeState.fleeRecoveryTicks or 0) / FLEE_EXIT_SAFE_TICKS, 0, 1)
  local calmProgress = clamp(1 - (currentFear or 0), 0, 1)
  runtimeState.fleeRecoveryProgress = timeProgress * (0.35 + calmProgress * 0.65)
  runtimeState.fleeSafeTicks = safeForExit and (runtimeState.fleeSafeTicks or 0) + 1 or 0
  if assessedThreatId ~= nil then
    runtimeState.fleeExitBlockedReason = "THREAT_ACTIVE"
  elseif not safeDistance then
    runtimeState.fleeExitBlockedReason = "NOT_SAFE_DISTANCE"
  elseif not lowSocialFear then
    runtimeState.fleeExitBlockedReason = "SOCIAL_ALARM"
  elseif not lowDirectFear or not lowCurrentFear then
    runtimeState.fleeExitBlockedReason = "FEAR_TOO_HIGH"
  elseif runtimeState.fleeSafeTicks < FLEE_EXIT_SAFE_TICKS then
    runtimeState.fleeExitBlockedReason = "RECOVERY_HOLD"
  else
    runtimeState.fleeExitBlockedReason = "READY"
  end
  return safeForExit
end

local function seededUnit(seed, salt)
  local reduced = math.abs(math.floor(seed or 0)) % MIX_MODULUS
  local combined = (reduced * 40503199 + (salt or 0) * 40503) % MIX_MODULUS
  local mixed = (combined * 26146329 + 12345) % MIX_MODULUS
  return mixed / (MIX_MODULUS - 1)
end

-- A plain (personalitySeed + counter) % 4 cycles through the same 4
-- directions in the same order every time, producing a deterministic
-- repeating loop (an "L shaped" walk that never actually goes anywhere).
-- Hash the seed and mostly keep the previous heading (natural longer
-- strides), only occasionally rerolling a fresh direction.
local function directionClosestToBias(bias)
  local bestChoice, bestDot = nil, -math.huge
  for _, direction in ipairs(TARGET_DIRECTIONS) do
    local dot = direction.dx * bias.dx + direction.dy * bias.dy
    if dot > bestDot then
      bestDot = dot
      bestChoice = direction
    end
  end
  return bestChoice
end

local function buildTargetDestination(entity, position, tick, counter,
  previousDirectionId, groupHeadingBias, movementScale)
  if not position then
    return nil, nil
  end

  local seed = (entity.personalitySeed or 1) * 97 + (counter or tick or 0)
  local previousIndex = nil
  for index, direction in ipairs(TARGET_DIRECTIONS) do
    if direction.id == previousDirectionId then
      previousIndex = index
    end
  end

  local choice
  if previousIndex and seededUnit(seed, 7) < 0.65 then
    choice = TARGET_DIRECTIONS[previousIndex]
  elseif groupHeadingBias and seededUnit(seed, 21) < 0.4 then
    -- Weak directional alignment: only nudges a FRESH reroll toward the
    -- trusted group's recent heading; momentum (above) still wins most of
    -- the time, so a lone Pokemon never gets hard-locked to the herd.
    choice = directionClosestToBias(groupHeadingBias)
  else
    local pick = math.floor(seededUnit(seed, 13) * #TARGET_DIRECTIONS) + 1
    choice = TARGET_DIRECTIONS[pick]
  end

  choice = choice or TARGET_DIRECTIONS[1]

  local scale = clamp(movementScale or 1, 0.75, 1.35)
  local distance = seededUnit(seed, 29) < math.max(0, scale - 1) * 0.5 and 2 or 1
  return choice.id, {
    cellX = position.cellX + choice.dx * distance,
    cellY = position.cellY + choice.dy * distance
  }
end

local STATE_HANDLERS = {
  IDLE = Idle,
  SETTLED = Settled,
  FLEE = Flee,
  TARGET = Target,
  SEEK_FLOCK = SeekFlock,
  INVESTIGATE = Investigate,
  APPROACH = Approach,
  REST = Rest,
  RETURN_HOME = ReturnHome,
  SATISFY_NEED = SatisfyNeed
}

local function cellKey(position)
  return position and tostring(position.cellX) .. "," .. tostring(position.cellY) or nil
end

local function firstClaim(claims)
  local firstId, firstRecord
  for entityId, record in pairs(claims or {}) do
    if firstId == nil or tostring(entityId) < tostring(firstId) then
      firstId, firstRecord = entityId, record
    end
  end
  return firstId, firstRecord
end

local function suspendRouteForOccupancy(entity, owner, action, decisionContext, tick)
  local bottleneck = WorldSemantics.cellKey(
    action.destination.cellX, action.destination.cellY)
  local sameBlock = owner.blockedCell == bottleneck
  local previousOccupancyReason = owner.occupancyReason
  owner.routeSuspended = true
  owner.blockedSinceTick = sameBlock and owner.blockedSinceTick or tick
  owner.blockAgeTicks = math.max(0, tick - (owner.blockedSinceTick or tick))
  owner.blockedCell = bottleneck
  owner.recentDynamicBlockedEdge = WorldSemantics.edgeKey(
    action.source.cellX, action.source.cellY,
    action.destination.cellX, action.destination.cellY)
  owner.recentDynamicBlockedBottleneck = bottleneck
  local details = decisionContext.occupancyDetails
    and decisionContext.occupancyDetails[bottleneck] or {}
  NavigationExecution.emitOccupancyDiagnostic(
    entity, decisionContext, owner, action.source, action.destination)
  local occupantId, occupant = firstClaim(details.currentOccupants)
  local reservationId, reservation = firstClaim(details.destinationReservations)
  owner.blockerCurrentOccupantId = occupantId
  owner.blockerCurrentOccupantMoving = occupant and occupant.moving == true or false
  owner.blockerCurrentOccupantDestination = occupant and occupant.destination or nil
  owner.blockerCurrentOccupantMotionStartedTick = occupant and occupant.motionStartedTick or nil
  owner.blockerReservationOwnerId = reservationId
  owner.blockerReservationOwnerDestination = reservation and reservation.destination or nil
  local occupantDestination = owner.blockerCurrentOccupantDestination
  local movingAway = occupantId ~= nil and owner.blockerCurrentOccupantMoving
    and type(occupantDestination) == "table"
    and WorldSemantics.cellKey(
      occupantDestination.cellX, occupantDestination.cellY) ~= bottleneck
  if reservationId ~= nil then
    owner.occupancyReason = "DESTINATION_RESERVATION"
    if owner.blockAgeTicks >= OCCUPANCY_STALE_WATCHDOG_TICKS then
      return true, "STALE_OCCUPANCY_STATE"
    end
    return false
  end
  if movingAway then
    owner.occupancyReason = "MOVING_AWAY_OCCUPANT"
    if (not sameBlock or previousOccupancyReason ~= "MOVING_AWAY_OCCUPANT")
      and decisionContext.movementClaims
      and decisionContext.movementClaims.markVacatingWait then
      decisionContext.movementClaims:markVacatingWait()
    end
    if owner.blockAgeTicks >= OCCUPANCY_STALE_WATCHDOG_TICKS then
      return true, "STALE_OCCUPANCY_STATE"
    end
    return false
  end
  if occupantId ~= nil then
    owner.occupancyReason = "STATIONARY_OCCUPANT"
    return true, "STATIONARY_OCCUPANT"
  end
  owner.occupancyReason = "STALE_OCCUPANCY_STATE"
  return owner.blockAgeTicks >= OCCUPANCY_STALE_WATCHDOG_TICKS,
    "STALE_OCCUPANCY_STATE"
end

local function clearRouteOccupancyWait(owner)
  owner.routeSuspended = false
  owner.blockedSinceTick = nil
  owner.blockAgeTicks = 0
  owner.blockedCell = nil
  owner.blockerCurrentOccupantId = nil
  owner.blockerCurrentOccupantMoving = false
  owner.blockerCurrentOccupantDestination = nil
  owner.blockerCurrentOccupantMotionStartedTick = nil
  owner.blockerReservationOwnerId = nil
  owner.blockerReservationOwnerDestination = nil
  owner.occupancyReason = nil
end

local function clearResolvedSpatialGoal(runtimeState)
  runtimeState.spatialGoal = nil
  runtimeState.goalSatisfied = false
  runtimeState.goalSatisfiedSinceTick = nil
  runtimeState.goalSelfPosition = nil
  runtimeState.goalTargetPosition = nil
  runtimeState.goalDx = nil
  runtimeState.goalDy = nil
  runtimeState.goalManhattan = nil
  runtimeState.goalChebyshev = nil
end

local function destinationKey(destination)
  return destination and WorldSemantics.cellKey(
    destination.cellX, destination.cellY) or "none"
end

local function rejectionSignature(rejectedMoves, position, mapId)
  local parts = {}
  for _, direction in ipairs({ "UP", "DOWN", "LEFT", "RIGHT" }) do
    local record = rejectedMoves and rejectedMoves[direction]
    if record == true or (type(record) == "table"
      and (record.mapId == nil or record.mapId == mapId)
      and (record.cellX == nil or record.cellX == position.cellX)
      and (record.cellY == nil or record.cellY == position.cellY)) then
      parts[#parts + 1] = direction .. ":" .. tostring(record and record.reason or true)
    end
  end
  return table.concat(parts, "|")
end

local function blockerSnapshot(decisionContext, blockedCell)
  local details = blockedCell and decisionContext.occupancyDetails
    and decisionContext.occupancyDetails[blockedCell] or {}
  local occupantId, occupant = firstClaim(details.currentOccupants)
  local reservationId, reservation = firstClaim(details.destinationReservations)
  return {
    occupied = blockedCell ~= nil and decisionContext.occupiedCells
      and decisionContext.occupiedCells[blockedCell] == true or false,
    occupantId = occupantId,
    occupantMoving = occupant and occupant.moving == true or false,
    occupantPosition = destinationKey(occupant and occupant.position),
    occupantDestination = destinationKey(occupant and occupant.destination),
    reservationId = reservationId,
    reservationDestination = destinationKey(reservation and reservation.destination)
  }
end

local function socialVectorDirection(reference)
  if not reference or reference.kind ~= "SOCIAL_ESCAPE_VECTOR" then return nil end
  local direction = reference.direction or {}
  local dx, dy = direction.dx or 0, direction.dy or 0
  if dx == 0 and dy == 0 then return nil end
  if math.abs(dx) >= math.abs(dy) then return dx < 0 and "LEFT" or "RIGHT" end
  return dy < 0 and "UP" or "DOWN"
end

local function socialVectorRawSignature(reference)
  if not reference or reference.kind ~= "SOCIAL_ESCAPE_VECTOR" then return "INACTIVE" end
  local direction = reference.direction or {}
  return table.concat({
    "ACTIVE", tostring(direction.dx or 0), tostring(direction.dy or 0),
    tostring(reference.confidence or 0)
  }, ":")
end

local function observeSocialVector(runtimeState, reference)
  local rawSignature = socialVectorRawSignature(reference)
  if runtimeState.lastSocialVectorRawSignature == rawSignature then return end
  local navigationDirection = socialVectorDirection(reference)
  local materialSignature = reference and reference.kind == "SOCIAL_ESCAPE_VECTOR"
    and "ACTIVE:" .. tostring(navigationDirection or "NONE") or "INACTIVE"
  local previousMaterial = runtimeState.lastSocialVectorMaterialSignature
  FleeEscape.recordSocialVectorUpdate(previousMaterial == nil
    or previousMaterial ~= materialSignature)
  runtimeState.lastSocialVectorRawSignature = rawSignature
  runtimeState.lastSocialVectorMaterialSignature = materialSignature
end

local function captureFailedPlanningContext(execution, runtimeState, decisionContext,
    position, threatPosition, threatSourceId, escapeReference, reason, tick)
  local blockedCell = execution.blockedCell
  if blockedCell == nil then
    for _, candidate in ipairs(execution.localCandidates or {}) do
      if candidate.occupied and candidate.destination then
        blockedCell = destinationKey(candidate.destination)
        break
      end
    end
  end
  local blocker = blockerSnapshot(decisionContext, blockedCell)
  local blockedCandidates = {}
  for _, candidate in ipairs(execution.localCandidates or {}) do
    if candidate.occupied and candidate.destination then
      local candidateCell = destinationKey(candidate.destination)
      local candidateBlocker = blockerSnapshot(decisionContext, candidateCell)
      blockedCandidates[#blockedCandidates + 1] = {
        cell = candidateCell,
        occupied = candidateBlocker.occupied,
        occupantId = candidateBlocker.occupantId,
        occupantMoving = candidateBlocker.occupantMoving,
        occupantPosition = candidateBlocker.occupantPosition,
        occupantDestination = candidateBlocker.occupantDestination,
        reservationId = candidateBlocker.reservationId,
        reservationDestination = candidateBlocker.reservationDestination
      }
    end
  end
  return {
    actorCell = destinationKey(position),
    threatSourceId = threatSourceId,
    threatCell = destinationKey(threatPosition),
    escapeReferenceKind = escapeReference and escapeReference.kind or nil,
    socialVectorDirection = socialVectorDirection(escapeReference),
    blockedCell = blockedCell,
    blockedCellOccupied = blocker.occupied,
    blockerEntityId = blocker.occupantId,
    blockerMoving = blocker.occupantMoving,
    blockerPosition = blocker.occupantPosition,
    blockerDestination = blocker.occupantDestination,
    reservationOwnerId = blocker.reservationId,
    reservationDestination = blocker.reservationDestination,
    blockedCandidates = blockedCandidates,
    staticRejections = rejectionSignature(
      runtimeState.rejectedMoves, position, decisionContext.mapId),
    mapId = decisionContext.mapId,
    topologyIdentity = decisionContext.worldSemantics
      and (decisionContext.worldSemantics.generation
        or decisionContext.worldSemantics) or nil,
    failureReason = reason,
    failedTick = tick
  }
end

local function failedPlanningDirtyReason(context, runtimeState, decisionContext,
    position, threatPosition, threatSourceId, escapeReference, tick)
  if not context then return "TopologyChange" end
  if context.actorCell ~= destinationKey(position) then return "ActorMovement" end
  if context.threatSourceId ~= threatSourceId then return "ThreatIdChange" end
  local previousSocial = context.escapeReferenceKind == "SOCIAL_ESCAPE_VECTOR"
  local currentSocial = escapeReference and escapeReference.kind == "SOCIAL_ESCAPE_VECTOR"
  if previousSocial or currentSocial then
    if previousSocial ~= currentSocial
      or context.socialVectorDirection ~= socialVectorDirection(escapeReference) then
      return "SocialVectorChange"
    end
  elseif context.threatCell ~= destinationKey(threatPosition) then
    return "ThreatGeometryChange"
  end
  local topologyIdentity = decisionContext.worldSemantics
    and (decisionContext.worldSemantics.generation
      or decisionContext.worldSemantics) or nil
  if context.mapId ~= decisionContext.mapId
    or context.topologyIdentity ~= topologyIdentity then
    return "TopologyChange"
  end
  if context.staticRejections ~= rejectionSignature(
      runtimeState.rejectedMoves, position, decisionContext.mapId) then
    return "TopologyChange"
  end
  if context.blockedCell then
    local blocker = blockerSnapshot(decisionContext, context.blockedCell)
    if context.blockedCellOccupied ~= nil
      and context.blockedCellOccupied ~= blocker.occupied then
      return "BlockerMovement"
    end
    if context.reservationOwnerId ~= blocker.reservationId
      or context.reservationDestination ~= blocker.reservationDestination then
      return "ClaimChange"
    end
    if context.blockerEntityId ~= blocker.occupantId
      then return "BlockerReplacement" end
    if context.blockerMoving ~= blocker.occupantMoving
      or context.blockerPosition ~= blocker.occupantPosition
      or context.blockerDestination ~= blocker.occupantDestination then
      return "BlockerMovement"
    end
  end
  for _, previous in ipairs(context.blockedCandidates or {}) do
    local blocker = blockerSnapshot(decisionContext, previous.cell)
    if previous.occupied ~= blocker.occupied then return "BlockerMovement" end
    if previous.reservationId ~= blocker.reservationId
      or previous.reservationDestination ~= blocker.reservationDestination then
      return "ClaimChange"
    end
    if previous.occupantId ~= blocker.occupantId then return "BlockerReplacement" end
    if previous.occupantMoving ~= blocker.occupantMoving
      or previous.occupantPosition ~= blocker.occupantPosition
      or previous.occupantDestination ~= blocker.occupantDestination then
      return "BlockerMovement"
    end
  end
  if tick - (context.failedTick or tick) >= FLEE_PLAN_WATCHDOG_TICKS then
    return "Watchdog"
  end
  return nil
end

local function appendRecentCell(history, position, targetEntityId, limit, direction)
  local cells = history or {}
  cells[#cells + 1] = {
    key = cellKey(position),
    targetEntityId = targetEntityId,
    direction = direction
  }
  while #cells > (limit or 4) do
    table.remove(cells, 1)
  end
  return cells
end

local function detectShortOscillation(history)
  local count = #history
  if count < 4 then
    return false, nil
  end
  local first = history[count - 3]
  local second = history[count - 2]
  local third = history[count - 1]
  local fourth = history[count]
  if first.key == third.key
    and second.key == fourth.key
    and first.key ~= second.key then
    return true, "CELL_ABAB"
  end
  if first.direction and second.direction and third.direction and fourth.direction
    and first.direction == third.direction
    and second.direction == fourth.direction
    and first.direction ~= second.direction then
    return true, "DIRECTION_ABAB"
  end
  return false, nil
end

local function updateCompletedStepNavigation(runtimeState, decisionContext, tick, completedRequest)
  local position = decisionContext.position
  local escapeReference = runtimeState.state == "FLEE" and runtimeState.escapeReference or nil
  local targetId = escapeReference
    and (escapeReference.entityId or escapeReference.kind)
    or runtimeState.targetEntityId
    or (runtimeState.state == "TARGET" and runtimeState.targetDestination and runtimeState.targetDestination.id)
  if not position or not targetId then
    return false
  end

  local priorHistory = runtimeState.recentCommittedCells or {}
  local previousCell = priorHistory[#priorHistory]
  local previousPreviousCell = priorHistory[#priorHistory - 1]
  local immediateReversal = previousPreviousCell ~= nil and previousPreviousCell.key == cellKey(position)
  runtimeState.recentCommittedCells = appendRecentCell(
    runtimeState.recentCommittedCells,
    position,
    targetId,
    runtimeState.state == "FLEE" and FLEE_RECENT_CELL_LIMIT or 4,
    completedRequest and completedRequest.direction
  )
  local cycleDetected, cyclePattern = detectShortOscillation(runtimeState.recentCommittedCells)

  if runtimeState.state ~= "FLEE" then
    return cycleDetected
  end

  local threatPosition = escapeReference and escapeReference.position
    or decisionContext.targetPositions and decisionContext.targetPositions[targetId]
  local threatDistance = Utility.chebyshevDistance(position, threatPosition)
  local execution = runtimeState.fleeExecution
  local establishedBaseline = false
  if not execution then
    execution = {
      threatEntityId = escapeReference and escapeReference.entityId or runtimeState.targetEntityId,
      routeThreatSourceId = escapeThreatSourceId(escapeReference),
      escapeReferenceKind = escapeReference and escapeReference.kind or nil,
      bestThreatDistance = threatDistance,
      noProgressSteps = 0,
      escapeMode = false,
      recentCells = {}
    }
    runtimeState.fleeExecution = execution
    establishedBaseline = true
  end

  execution.recentCells = appendRecentCell(execution.recentCells, position, targetId, FLEE_RECENT_CELL_LIMIT)
  execution.threatDistance = threatDistance
  execution.previousCell = previousCell and previousCell.key or nil
  execution.previousPreviousCell = previousPreviousCell and previousPreviousCell.key or nil
  execution.immediateReversal = immediateReversal
  execution.oscillationDetected = cycleDetected
  execution.oscillationPattern = cyclePattern
  local intent = execution.intent
  if intent then
    intent.age = math.max(0, tick - (intent.establishedTick or tick))
    intent.lastMeaningfulProgressTick = intent.lastMeaningfulProgressTick or intent.establishedTick
  end
  if establishedBaseline then
    execution.noProgressSteps = 0
  elseif threatDistance and (not execution.bestThreatDistance or threatDistance > execution.bestThreatDistance) then
    execution.bestThreatDistance = threatDistance
    execution.noProgressSteps = 0
    if intent then
      intent.bestSafetyReached = threatDistance
      intent.lastMeaningfulProgressTick = tick
    end
    execution.recentDynamicBlockedBottlenecks = nil
    execution.stuckReason = nil
    if not execution.route then
      execution.escapeMode = false
      execution.fleeMode = "NORMAL"
      execution.routeCommitment = false
      execution.routeCommitmentReason = "MEANINGFUL_SAFETY_IMPROVEMENT"
    end
  else
    execution.noProgressSteps = (execution.noProgressSteps or 0) + 1
    if cycleDetected or execution.noProgressSteps >= FLEE_NO_PROGRESS_THRESHOLD then
      execution.escapeMode = true
      execution.routeCommitmentReason = cycleDetected and "OSCILLATION_DETECTED" or "NO_PROGRESS"
    end
  end
  return cycleDetected
end

function Controller.chooseState(entity, playerRelationship, distance, context, nowTick)
  entity.runtimeState = entity.runtimeState or { state = "IDLE" }

  local rel = playerRelationship or {}
  local runtimeState = entity.runtimeState
  local priorState = runtimeState.state or "IDLE"
  local priorTargetEntityId = runtimeState.targetEntityId
  local tick = nowTick or 0
  local decisionContext = context or {}
  local physiology = EcologyPhysiology.forEntity(entity)
  Drives.update(entity, tick, {
    state = priorState == "REST" and runtimeState.restingActive ~= true
      and "TARGET" or priorState,
    moving = runtimeState.motion and runtimeState.motion.active == true,
    driveRateMultipliers = {
      THIRST = physiology.thirstRate,
      HUNGER = physiology.hungerRate,
      FATIGUE = priorState == "REST" and runtimeState.restingActive == true
        and physiology.restRecovery
        or physiology.fatigueRate
    }
  })
  local executionOnly = decisionContext.executionOnly == true
  local stepCompleted = runtimeState.motion and runtimeState.motion.justCompleted == true
  local priorMovementRequest = runtimeState.movementRequest
  local ordinaryNavigationState = runtimeState.state == "TARGET"
    or runtimeState.state == "APPROACH"
    or runtimeState.state == "INVESTIGATE"
    or runtimeState.state == "REST"
    or runtimeState.state == "RETURN_HOME"
  if ordinaryNavigationState and runtimeState.navigation
    and runtimeState.navigation.ownerBehavior == runtimeState.state then
    NavigationExecution.observeResult(runtimeState.navigation, runtimeState,
      decisionContext, tick, priorMovementRequest, stepCompleted)
  end
  if stepCompleted and runtimeState.state == "FLEE"
    and runtimeState.fleeExecution and runtimeState.fleeExecution.route then
    local route = runtimeState.fleeExecution.route
    if NavigationEpisode.advanceRoute(route) then
      runtimeState.fleeExecution.route = nil
      runtimeState.fleeExecution.planningState = "NEEDS_REPLAN"
      runtimeState.fleeExecution.routeInvalidationReason = "ROUTE_COMPLETE"
      runtimeState.fleeExecution.routeInvalidationTick = tick
      runtimeState.fleeExecution.routeCommitment = false
      runtimeState.fleeExecution.routeCommitmentReason = "ROUTE_ENDPOINT_REACHED"
    end
  end
  if runtimeState.state == "REST" and runtimeState.navigation
    and runtimeState.navigation.goalSatisfactionState == "UNREACHABLE" then
    local selected = runtimeState.restSiteSelection
      and runtimeState.restSiteSelection.selected
    if selected then
      runtimeState.restSiteRejectedCells = runtimeState.restSiteRejectedCells or {}
      runtimeState.restSiteRejectedCells[WorldSemantics.cellKey(
        selected.cellX, selected.cellY)] = true
    end
    runtimeState.restSiteSelection = nil
    runtimeState.navigation = nil
    runtimeState.restSiteReconsiderationReason = "UNREACHABLE"
  end
  local ambientRejected = runtimeState.state == "TARGET"
    and priorMovementRequest
    and ((priorMovementRequest.rejectionReason ~= nil
      and priorMovementRequest.rejectionReason ~= "MOVEMENT_ACTIVE")
      or priorMovementRequest.reason == "NO_LEGAL_STEP")
    and (not runtimeState.navigation
      or runtimeState.navigation.goalSatisfactionState == "UNREACHABLE")
  local ambientNavigationFailed = runtimeState.state == "TARGET"
    and runtimeState.navigation
    and runtimeState.navigation.ownerBehavior == "TARGET"
    and runtimeState.navigation.goalSatisfactionState == "UNREACHABLE"
  local ambientAlreadySatisfied = runtimeState.state == "TARGET"
    and runtimeState.targetDestination
    and decisionContext.position
    and runtimeState.targetDestination.cellX == decisionContext.position.cellX
    and runtimeState.targetDestination.cellY == decisionContext.position.cellY
  local ambientEpisodeSucceeded = runtimeState.state == "TARGET"
    and ((stepCompleted and (not runtimeState.navigation
      or runtimeState.navigation.ownerBehavior ~= "TARGET"))
      or ambientAlreadySatisfied)
  local ambientEpisodeFinished = ambientEpisodeSucceeded
    or ambientRejected or ambientNavigationFailed
  local searchRejected = runtimeState.state == "SEEK_FLOCK"
    and priorMovementRequest
    and ((priorMovementRequest.rejectionReason ~= nil
      and priorMovementRequest.rejectionReason ~= "MOVEMENT_ACTIVE")
      or priorMovementRequest.reason == "NO_LEGAL_STEP")
  local navigation = runtimeState.navigation
  local motionRecovered = runtimeState.state == "SEEK_FLOCK"
    and runtimeState.motion
    and runtimeState.motion.recoveryReason ~= nil
  if motionRecovered and navigation then
    navigation.route = nil
    navigation.replanReason = "MOTION_RECOVERY"
    runtimeState.movementRequest = nil
    runtimeState.motion.recoveryReason = nil
  end
  if runtimeState.state == "SEEK_FLOCK" and stepCompleted and navigation and navigation.route then
    navigation.route.index = (navigation.route.index or 1) + 1
    navigation.replanReason = nil
    navigation.dynamicBlockedEdges = {}
    clearRouteOccupancyWait(navigation)
    if navigation.route.index > #navigation.route.actions then
      local reachedGoal = navigation.route.reachedGoal == true
      if reachedGoal and navigation.goalSource == "last_seen" then
        FlockSearch.consumeLastSeen(entity, navigation.targetEntityId)
        if decisionContext.flockSearch then
          decisionContext.flockSearch.cueSource = "search"
          decisionContext.flockSearch.cuePosition = nil
          decisionContext.flockSearch.cueDirection = nil
          decisionContext.flockSearch.targetEntityId = nil
        end
      end
      navigation.route = nil
      navigation.replanReason = reachedGoal and "GOAL_REACHED" or "SEGMENT_COMPLETE"
    end
  end
  if searchRejected and navigation then
    local sourceMismatch = priorMovementRequest.rejectionReason == "SOURCE_POSITION_MISMATCH"
    local dynamicOccupancy = priorMovementRequest.rejectionReason == "entity"
    navigation.blockedEdges = navigation.blockedEdges or {}
    if dynamicOccupancy and priorMovementRequest.sourceX ~= nil
      and priorMovementRequest.sourceY ~= nil
      and priorMovementRequest.destinationX ~= nil
      and priorMovementRequest.destinationY ~= nil then
      local persistent, releaseReason = suspendRouteForOccupancy(entity, navigation, {
        source = { cellX = priorMovementRequest.sourceX, cellY = priorMovementRequest.sourceY },
        destination = {
          cellX = priorMovementRequest.destinationX,
          cellY = priorMovementRequest.destinationY
        }
      }, decisionContext, tick)
      if persistent then
        navigation.dynamicBlockedEdges = navigation.dynamicBlockedEdges or {}
        navigation.dynamicBlockedEdges[navigation.recentDynamicBlockedEdge] = true
        navigation.route = nil
        navigation.routeSuspended = false
        navigation.routeReleased = true
        navigation.releaseReason = releaseReason
        navigation.replanReason = "PERSISTENT_DYNAMIC_OCCUPANCY"
        runtimeState.pendingOccupancyEpisodeFailure = {
          tick = tick,
          blockedCell = navigation.blockedCell
        }
      else
        navigation.replanReason = "ROUTE_WAITING_FOR_OCCUPANCY"
      end
    elseif not sourceMismatch and decisionContext.position
      and priorMovementRequest.destinationX and priorMovementRequest.destinationY then
      navigation.blockedEdges[WorldSemantics.edgeKey(
        decisionContext.position.cellX,
        decisionContext.position.cellY,
        priorMovementRequest.destinationX,
        priorMovementRequest.destinationY
      )] = true
    end
    if not dynamicOccupancy then
      navigation.route = nil
      navigation.replanReason = sourceMismatch and "SOURCE_POSITION_MISMATCH" or "EXECUTION_REJECTED"
    end
  end
  local cycleDetected = false
  if stepCompleted then
    runtimeState.motion.justCompleted = false
    cycleDetected = updateCompletedStepNavigation(runtimeState, decisionContext, tick, priorMovementRequest)
    if cycleDetected and runtimeState.state == "TARGET" then
      runtimeState.targetDestination = nil
      runtimeState.recentCommittedCells = {}
    elseif cycleDetected and runtimeState.state ~= "FLEE" then
      runtimeState.navigationAvoidTargetId = runtimeState.targetEntityId
      runtimeState.navigationAvoidUntilTick = tick + NAVIGATION_CYCLE_COOLDOWN
      runtimeState.recentCommittedCells = {}
    end
  end
  if ambientEpisodeFinished then
    if ambientEpisodeSucceeded then
      Motivation.satisfy(entity, "exploration", 1, tick, {
        source = "TARGET"
      })
    end
    runtimeState.targetDestination = nil
    runtimeState.movementRequest = nil
    runtimeState.recentCommittedCells = {}
  end
  if runtimeState.state == "SEEK_FLOCK" and (stepCompleted or searchRejected) then
    runtimeState.flockSearchDestination = nil
    runtimeState.movementRequest = nil
  end
  local currentState = runtimeState.state or "IDLE"
  local currentCircadian = CircadianSystem.evaluate(entity,
    decisionContext.ecologyPhase or 0.5)
  local currentFatigue = Drives.status(entity, "FATIGUE", tick)
  decisionContext.homeArea = entity.home and entity.home.area or nil
  decisionContext.homeReturn = HomeReturn.evaluate(entity,
    decisionContext.position, decisionContext.mapId, {
      fatigue = currentFatigue.value,
      circadianRestBias = currentCircadian.restBias
    })
  if executionOnly and runtimeState.state == "SATISFY_NEED" then
    decisionContext.needOpportunity = runtimeState.needOpportunity
  end
  local assessment = decisionContext.threatAssessment or runtimeState.threatAssessment or {}
  local assessedThreatId = assessment.primaryThreatId
  local assessedThreatPosition = assessedThreatId and decisionContext.targetPositions
    and decisionContext.targetPositions[assessedThreatId] or nil
  if assessedThreatId and assessedThreatPosition then
    runtimeState.fleeThreatPosition = copyPosition(assessedThreatPosition)
    runtimeState.fleeThreatPositionTick = tick
    runtimeState.fleeThreatEntityId = assessedThreatId
  end
  if currentState == "FLEE" then
    runtimeState.targetEntityId = assessedThreatId
  end
  local desiredSafetyDistance = runtimeState.fleeDesiredSafetyDistance
  local fleeRadius = runtimeState.fleeRadius
  local scores = runtimeState.behaviorScores or {}
  if executionOnly and currentState == "FLEE" then
    local threatPosition = assessedThreatId and decisionContext.targetPositions
      and decisionContext.targetPositions[assessedThreatId] or nil
    local executionDistance = Utility.chebyshevDistance(decisionContext.position, threatPosition)
    updateFleeRecovery(runtimeState, assessedThreatId, executionDistance,
      decisionContext.currentFear or runtimeState.fearCurrent or 0, desiredSafetyDistance)
  end
  if executionOnly and IntentEpisode.isPurposeful(currentState) then
    local executionTargetId = runtimeState.targetEntityId
    local occupancyFailure = runtimeState.pendingOccupancyEpisodeFailure
    local ordinaryNavigationFailure = runtimeState.navigation
      and runtimeState.navigation.ownerBehavior == currentState
      and runtimeState.navigation.goalSatisfactionState == "UNREACHABLE"
    local executionRejected = occupancyFailure ~= nil or ordinaryNavigationFailure or priorMovementRequest
      and ((priorMovementRequest.rejectionReason ~= nil
        and priorMovementRequest.rejectionReason ~= "MOVEMENT_ACTIVE")
        or priorMovementRequest.reason == "NO_LEGAL_STEP")
      and priorMovementRequest.rejectionReason ~= "entity"
    local rejectionSignature = occupancyFailure and table.concat({
      "occupancy", tostring(occupancyFailure.tick),
      tostring(occupancyFailure.blockedCell)
    }, ":") or ordinaryNavigationFailure and table.concat({
      "navigation", tostring(runtimeState.navigation.ownerGoalSignature),
      tostring(runtimeState.navigation.failureReason or "UNREACHABLE_STATIC")
    }, ":") or executionRejected and table.concat({
      tostring(priorMovementRequest.issuedTick or "none"),
      tostring(priorMovementRequest.direction or "none"),
      tostring(priorMovementRequest.rejectionReason or priorMovementRequest.reason or "none")
    }, ":") or nil
    local newExecutionRejection = rejectionSignature ~= nil
      and rejectionSignature ~= runtimeState.lastIntentEpisodeRejectionSignature
    if newExecutionRejection then
      runtimeState.lastIntentEpisodeRejectionSignature = rejectionSignature
    end
    runtimeState.pendingOccupancyEpisodeFailure = nil
    local episode = IntentEpisode.observe(
      entity,
      currentState,
      executionTargetId,
      assessedThreatId,
      decisionContext,
      tick,
      newExecutionRejection
    )
    runtimeState.intentEpisodeStatus = episode and episode.status or "NONE"
    runtimeState.intentEpisodeAge = episode
      and math.max(0, tick - (episode.startedTick or tick)) or 0
    runtimeState.intentCommitment = episode and episode.commitment or 0
    runtimeState.intentProgress = episode and episode.progress or 0
    if episode and episode.status ~= "ACTIVE" then
      runtimeState.executionTerminalReason = "INTENT_" .. episode.status
      runtimeState.movementRequest = nil
      return currentState, scores[currentState] or 0
    end
  end
  runtimeState.executionTerminalReason = nil
  if not executionOnly then
  local behaviorEntity = decisionContext.behaviorEntity or entity
  local targetContext = TargetSelector.buildContext(behaviorEntity, decisionContext.candidates, decisionContext.behavior)
  -- This is only what the target selector PROPOSES this tick (WHO). It must
  -- not be committed to runtimeState.targetEntityId until the behavior
  -- (WHAT) is actually decided below — otherwise ambient states like TARGET
  -- inherit an unrelated entity id that has nothing to do with them.
  local selectedEntityTargetId = decisionContext.targetEntityId or targetContext.targetEntityId
  assessedThreatId = assessment.primaryThreatId
  local avoidingSelectedTarget = selectedEntityTargetId ~= nil
    and selectedEntityTargetId == runtimeState.navigationAvoidTargetId
    and tick < (runtimeState.navigationAvoidUntilTick or 0)
  if avoidingSelectedTarget then
    selectedEntityTargetId = nil
  end
  currentState = runtimeState.state or "IDLE"
  local scoredContext = {}
  for key, value in pairs(decisionContext) do
    scoredContext[key] = value
  end
  scoredContext.hasTarget = not avoidingSelectedTarget
    and (decisionContext.hasTarget == true or targetContext.hasTarget)
  scoredContext.distance = distance
  scoredContext.targetDistance = targetContext.target
    and targetContext.target.distance or distance
  local motivation = Motivation.context(behaviorEntity, tick)
  scoredContext.driveNeed = motivation.need
  scoredContext.driveSatisfaction = motivation.satisfaction
  local needOpportunity = NeedStrategy.evaluate(entity, decisionContext, tick)
  runtimeState.needOpportunity = needOpportunity or runtimeState.state == "SATISFY_NEED"
    and runtimeState.needOpportunity or nil
  scoredContext.needOpportunity = needOpportunity
  local circadian = currentCircadian
  local fatigue = currentFatigue
  scoredContext.fatigue = fatigue.value
  scoredContext.circadianActivityBias = circadian.activityBias
  scoredContext.circadianRestBias = circadian.restBias
  scoredContext.homeReturn = decisionContext.homeReturn
  runtimeState.circadian = circadian
  scoredContext.activeThreat = assessedThreatId ~= nil
  scoredContext.seekFlockUtility = decisionContext.flockSearch and decisionContext.flockSearch.utility or 0
  -- Novelty fades the longer the same target has been stared at, so a
  -- Pokemon naturally moves on to ambient activity instead of freezing on
  -- the first neighbor it noticed forever.
  scoredContext.investigateElapsed = (runtimeState.state == "INVESTIGATE")
    and math.max(0, tick - (runtimeState.stateEnteredTick or tick))
    or 0
  -- Restlessness: standing idle for a while naturally builds a drive to
  -- wander off, and wandering for a while naturally settles back down —
  -- without this, a static TARGET score can never out-compete IDLE once
  -- hysteresis has locked an entity into either one.
  local elapsedInState = math.max(0, tick - (runtimeState.stateEnteredTick or tick))
  scoredContext.idleElapsed = (runtimeState.state == "IDLE") and elapsedInState or 0
  scoredContext.settledElapsed = (runtimeState.state == "SETTLED") and elapsedInState or 0
  scoredContext.targetElapsed = (runtimeState.state == "TARGET") and elapsedInState or 0
  if decisionContext.debugIdleElapsed ~= nil then
    scoredContext.idleElapsed = decisionContext.debugIdleElapsed
  end
  if decisionContext.debugSettledElapsed ~= nil then
    scoredContext.settledElapsed = decisionContext.debugSettledElapsed
  end
  -- Same restlessness idea for a REACHED approach target: without this, an
  -- entity that arrives next to a trusted associate has no drive to ever
  -- leave again (trust/affinity don't decay, so APPROACH keeps winning
  -- forever) and just parks there permanently until some external event
  -- (e.g. the player scaring it) forces a change. goalSatisfiedSinceTick is
  -- only set once the approach goal is actually reached (see below), so
  -- this stays 0 while still travelling toward the target.
  scoredContext.approachSatisfiedElapsed = (runtimeState.state == "APPROACH" and runtimeState.goalSatisfiedSinceTick)
    and math.max(0, tick - runtimeState.goalSatisfiedSinceTick)
    or 0
  scoredContext.currentFear = decisionContext.currentFear or runtimeState.fearCurrent or 0
  scoredContext.seekFlockSafetyFactor = assessedThreatId ~= nil
    and (1 - clamp(scoredContext.currentFear, 0, 1)) ^ 2
    or 1
  local episodeContext = {}
  for key, value in pairs(decisionContext) do episodeContext[key] = value end
  episodeContext.tick = tick
  episodeContext.hasTarget = scoredContext.hasTarget
  episodeContext.needOpportunity = runtimeState.needOpportunity
  episodeContext.circadianActivityBias = circadian.activityBias
  episodeContext.circadianRestBias = circadian.restBias
  episodeContext.homeArea = decisionContext.homeArea
  episodeContext.homeReturn = decisionContext.homeReturn
  local episode = IntentEpisode.observe(
    entity,
    currentState,
    selectedEntityTargetId,
    assessedThreatId,
    episodeContext,
    tick,
    searchRejected
  )
  local completedInvestigationTargetId = episode
    and episode.intent == "INVESTIGATE"
    and episode.targetId
    or nil
  local satisfaction = IntentEpisode.satisfactionContext(
    behaviorEntity,
    selectedEntityTargetId,
    episodeContext,
    tick,
    rel
  )
  scoredContext.approachReacquisitionSuppressed = satisfaction.approachSuppressed
  scoredContext.recentPurposefulDwell = satisfaction.dwellActive
  if satisfaction.reacquisitionReleased then
    scoredContext.idleElapsed = 0
  end
  scores = Utility.scoreBehaviors(behaviorEntity, rel, scoredContext)
  if episode and episode.intent == currentState and episode.status ~= "ACTIVE" then
    scores[currentState] = 0
  end
  local baseFleeRadius = Utility.fleeRadius(rel)
  fleeRadius, desiredSafetyDistance = Fear.escapeDistances(
    baseFleeRadius,
    scoredContext.currentFear,
    runtimeState.fearDirect,
    runtimeState.fearSocial,
    runtimeState.alarmGroundedness
  )
  local socialBiasConfidence = runtimeState.socialEscapeBiasConfidence or 0
  local socialAlarmFlee = assessedThreatId == nil
    and decisionContext.socialAlarmTargetPosition ~= nil
    and (runtimeState.fearSocial or 0) >= 0.22
    and socialBiasConfidence >= 0.2
  runtimeState.socialFleeCuePresent = decisionContext.socialAlarmTargetPosition ~= nil
  runtimeState.socialFleeFearThresholdMet = (runtimeState.fearSocial or 0) >= 0.22
  runtimeState.socialFleeConfidenceThresholdMet = socialBiasConfidence >= 0.2
  runtimeState.socialFleeCueEligible = socialAlarmFlee
  runtimeState.socialFleeEligible = true
  local safeForExit = updateFleeRecovery(runtimeState, assessedThreatId, distance,
    scoredContext.currentFear, desiredSafetyDistance)
  local fleeExitReady = runtimeState.state == "FLEE"
    and safeForExit and (runtimeState.fleeSafeTicks or 0) >= FLEE_EXIT_SAFE_TICKS
  local continuingFlee = runtimeState.state == "FLEE"
    and not fleeExitReady
  local candidateState, candidateScore = Utility.highestBehavior(scores)
  local rawCandidateState, rawCandidateScore = candidateState, candidateScore
  local assessment = decisionContext.threatAssessment or {}
  local emergencyFlee = Controller.isEmergencyThreat(runtimeState, assessment)
  local committedFlee = continuingFlee
  if emergencyFlee or committedFlee then
    candidateState = "FLEE"
    candidateScore = scores.FLEE
  end
  local currentScore = scores[currentState] or 0
  local currentStateAge = math.max(0, tick - (runtimeState.stateEnteredTick or tick))
  local canChange = Utility.shouldChangeBehavior(
    currentState,
    candidateState,
    currentScore,
    candidateScore,
    tick,
    runtimeState.stateEnteredTick,
    MINIMUM_STATE_DURATION,
    SCORE_HYSTERESIS
  )

  if emergencyFlee or committedFlee then
    canChange = true
  end
  if satisfaction.reacquisitionReleased and candidateState == "APPROACH" then
    canChange = true
  end

  local episodeAllowed, episodeReason, episodeMargin = IntentEpisode.switchDecision(
    entity,
    currentState,
    candidateState,
    currentScore,
    candidateScore
  )
  local episodeBlocked = not emergencyFlee and not committedFlee
    and episodeAllowed == false
  if episodeBlocked then
    canChange = false
  elseif episode and episode.intent == currentState
    and episode.status ~= "ACTIVE" then
    canChange = true
  end

  if avoidingSelectedTarget and (currentState == "APPROACH" or currentState == "INVESTIGATE") then
    candidateState = "IDLE"
    candidateScore = scores.IDLE or 0
    canChange = true
  end

  if ambientEpisodeFinished and not emergencyFlee and not committedFlee then
    candidateState = ambientEpisodeSucceeded and "SETTLED" or "IDLE"
    candidateScore = scores[candidateState] or 0
    canChange = true
  end

  if currentState == "INVESTIGATE" and episode
    and episode.intent == "INVESTIGATE" and episode.status == "SATISFIED"
    and candidateState == "INVESTIGATE"
    and not emergencyFlee and not committedFlee then
    candidateState = "SETTLED"
    candidateScore = scores.SETTLED or 0
    canChange = true
  end

  if currentState == "SATISFY_NEED" and episode
    and episode.intent == "SATISFY_NEED" and episode.status == "SATISFIED"
    and not emergencyFlee and not committedFlee then
    candidateState = "SETTLED"
    candidateScore = scores.SETTLED or 0
    canChange = true
    runtimeState.needOpportunity = nil
  end

  if currentState == "SATISFY_NEED" and candidateState ~= "SATISFY_NEED"
    and canChange then
    runtimeState.feedingAction = nil
  end

  if currentState == "REST" and episode
    and episode.intent == "REST" and episode.status == "SATISFIED"
    and not emergencyFlee and not committedFlee then
    candidateState = "SETTLED"
    candidateScore = scores.SETTLED or 0
    canChange = true
  end

  if currentState == "RETURN_HOME" and episode
    and episode.intent == "RETURN_HOME" and episode.status == "SATISFIED"
    and not emergencyFlee and not committedFlee then
    candidateState = "SETTLED"
    candidateScore = scores.SETTLED or 0
    canChange = true
  end

  if currentState == "FLEE" and candidateState ~= "FLEE"
    and not emergencyFlee and not committedFlee then
    canChange = true
  end

  if currentState == "SEEK_FLOCK"
    and decisionContext.flockSearch
    and decisionContext.flockSearch.nearbySameSpecies > 0 then
    canChange = true
  end

  if (currentState == "APPROACH" or currentState == "INVESTIGATE")
    and decisionContext.hasTarget ~= true
    and targetContext.hasTarget ~= true then
    canChange = true
    candidateState = "IDLE"
  end

  if canChange then
    if currentState ~= candidateState then
      runtimeState.stateEnteredTick = tick
    end
    runtimeState.state = candidateState
  end
  local selectedEpisodeTarget = runtimeState.state == "SEEK_FLOCK"
    and decisionContext.flockSearch and decisionContext.flockSearch.targetEntityId
    or selectedEntityTargetId
  IntentEpisode.afterSelection(
    entity,
    currentState,
    runtimeState.state,
    selectedEpisodeTarget,
    assessedThreatId,
    episodeContext,
    tick,
    emergencyFlee
  )
  local activeEpisode = runtimeState.intentEpisode
  runtimeState.debugPreset = decisionContext.debugPreset or "NONE"
  runtimeState.debugPresetInputs = decisionContext.debugPreset and {
    trust = rel.trust or 0,
    familiarity = rel.familiarity or 0,
    affinity = rel.affinity or 0,
    threatMemory = rel.threatMemory or 0,
    hostility = rel.hostility or 0,
    curiosity = behaviorEntity.temperament and behaviorEntity.temperament.curiosity or 0,
    boldness = behaviorEntity.temperament and behaviorEntity.temperament.boldness or 0,
    currentFear = scoredContext.currentFear or 0,
    hasTarget = scoredContext.hasTarget == true,
    purposefulTarget = scoredContext.purposefulTarget ~= false
  } or nil
  runtimeState.debugPresetOriginalInputs = decisionContext.debugPresetOriginalInputs
  runtimeState.debugPresetReplacedInputs = decisionContext.debugPresetReplacedInputs
  runtimeState.selectionReason = emergencyFlee and "EMERGENCY_FLEE"
    or committedFlee and "FLEE_EPISODE_COMMITMENT"
    or episodeBlocked and episodeReason
    or canChange and "UTILITY_WINNER"
    or "HYSTERESIS_RETAINED"
  runtimeState.emergencyFlee = emergencyFlee
  runtimeState.candidateState = candidateState
  runtimeState.candidateScore = candidateScore
  runtimeState.candidateWinner = rawCandidateState
  runtimeState.candidateWinnerScore = rawCandidateScore
  runtimeState.currentStateScore = currentScore
  runtimeState.minimumStateDuration = MINIMUM_STATE_DURATION
  runtimeState.scoreHysteresis = SCORE_HYSTERESIS
  runtimeState.rawSeekFlockUtility = scoredContext.seekFlockUtility
  runtimeState.seekFlockSafetyFactor = scoredContext.seekFlockSafetyFactor
  runtimeState.currentStateAge = currentStateAge
  runtimeState.hysteresisHeld = not canChange
  runtimeState.hysteresisReason = not canChange
    and (episodeBlocked and episodeReason or "SCORE_OR_DURATION") or "NONE"
  runtimeState.challengerIntent = candidateState
  runtimeState.challengerScore = candidateScore
  runtimeState.intentSwitchMargin = episodeMargin or SCORE_HYSTERESIS
  runtimeState.switchAllowed = canChange
  runtimeState.switchReason = runtimeState.selectionReason
  runtimeState.socialFleeDecisionReason = assessedThreatId ~= nil and "DIRECT_THREAT_PRESENT"
    or rawCandidateState ~= "FLEE" and "FLEE_SCORE_NOT_WINNER"
    or runtimeState.state ~= "FLEE" and "FLEE_SWITCH_BLOCKED"
    or "SOCIAL_FLEE_SELECTED"
  runtimeState.intentEpisodeAge = activeEpisode
    and math.max(0, tick - (activeEpisode.startedTick or tick)) or 0
  runtimeState.intentEpisodeStatus = activeEpisode and activeEpisode.status or "NONE"
  runtimeState.intentCommitment = activeEpisode and activeEpisode.commitment or 0
  runtimeState.intentProgress = activeEpisode and activeEpisode.progress or 0
  runtimeState.satisfactionAge = satisfaction.satisfactionAge

  if currentState == "FLEE" and runtimeState.state ~= "FLEE" then
    runtimeState.lastFleeEndTick = tick
    runtimeState.postFleeCalmTicks = 0
    runtimeState.fleeSafeTicks = 0
    runtimeState.fleeExitBlockedReason = "EXITED"
    runtimeState.escapeHeading = nil
    runtimeState.escapeSeparationMomentum = nil
    runtimeState.fleeThreatPosition = nil
    runtimeState.fleeThreatPositionTick = nil
    runtimeState.fleeThreatEntityId = nil
    runtimeState.escapeReference = nil
    runtimeState.firstOrdinaryDecisionTick = tick
    runtimeState.firstOrdinaryState = runtimeState.state
  elseif currentState ~= "FLEE" and runtimeState.state == "FLEE" then
    runtimeState.firstOrdinaryDecisionTick = nil
    runtimeState.firstOrdinaryState = nil
    runtimeState.firstSeekFlockTick = nil
  elseif runtimeState.state ~= "FLEE" and runtimeState.lastFleeEndTick then
    runtimeState.postFleeCalmTicks = math.max(0, tick - runtimeState.lastFleeEndTick)
  elseif runtimeState.state == "FLEE" then
    runtimeState.postFleeCalmTicks = 0
  end
  if assessedThreatId ~= nil or socialAlarmFlee then
    runtimeState.postFleeCalmTicks = 0
    runtimeState.fleeRecoveryTicks = 0
    runtimeState.fleeRecoveryProgress = 0
  end
  if runtimeState.state == "SEEK_FLOCK" and runtimeState.lastFleeEndTick
    and runtimeState.firstSeekFlockTick == nil then
    runtimeState.firstSeekFlockTick = tick
  end

  if currentState == "TARGET" and runtimeState.state ~= "TARGET" then
    runtimeState.targetDestination = nil
    runtimeState.movementRequest = nil
  elseif currentState ~= "TARGET" and runtimeState.state == "TARGET" then
    runtimeState.targetDestination = nil
  end
  if currentState == "SEEK_FLOCK" and runtimeState.state ~= "SEEK_FLOCK" then
    runtimeState.flockSearchDestination = nil
    runtimeState.searchCueSource = nil
    runtimeState.searchCueDirection = nil
    runtimeState.searchIsolationPressure = nil
    runtimeState.navigation = nil
  end
  if currentState == "REST" and runtimeState.state ~= "REST" then
    runtimeState.restSiteSelection = nil
    runtimeState.restSiteRejectedCells = nil
    runtimeState.restTraveling = nil
    runtimeState.restingActive = nil
    runtimeState.concealmentRequest = nil
  elseif currentState ~= "REST" and runtimeState.state == "REST" then
    runtimeState.restSiteRejectedCells = nil
    runtimeState.restSiteReconsiderationReason = "REST_SELECTED"
  end
  if currentState == "RETURN_HOME" and runtimeState.state ~= "RETURN_HOME" then
    runtimeState.homeReturnDestination = nil
    runtimeState.homeReturnGoal = nil
  elseif currentState ~= "RETURN_HOME" and runtimeState.state == "RETURN_HOME" then
    runtimeState.homeReturnDestination = nil
  end

  -- Novelty only decays locally while ACTIVELY investigating (see
  -- scoredContext.investigateElapsed above) and would otherwise reset back
  -- to full the instant INVESTIGATE exits, letting a target become "novel"
  -- again immediately and re-trigger INVESTIGATE right after IDLE settles
  -- -- an infinite IDLE/INVESTIGATE cycle. Commit the decay permanently to
  -- the relationship's familiarity when actually leaving INVESTIGATE, so a
  -- target that has genuinely been looked at for a while stays less novel.
  if canChange and currentState == "INVESTIGATE" and runtimeState.state ~= "INVESTIGATE" then
    local investigateElapsed = scoredContext.investigateElapsed or 0
    if investigateElapsed > 0 and completedInvestigationTargetId ~= nil then
      local familiarityGain = math.min(30, investigateElapsed * 3)
      local completedRelationship = Relationships.getOrCreate(entity,
        completedInvestigationTargetId)
      local relationshipBefore = Relationships.snapshot(completedRelationship)
      local diagnostic = {
        observerId = entity.id,
        subjectId = completedInvestigationTargetId,
        event = "INVESTIGATION_COMPLETED",
        producer = "src.behavior.controller.chooseState",
        tick = tick,
        relationshipRef = completedRelationship,
        before = relationshipBefore,
        diagnosticContext = {
          previousBehaviorState = currentState,
          selectedBehaviorState = runtimeState.state,
          selectedTargetEntityId = selectedEntityTargetId
        }
      }
      diagnostic.phase = "PRE_EVENT"
      Relationships.emitDiagnosticEvent(diagnostic)
      diagnostic.phase = "EVENT"
      Relationships.emitDiagnosticEvent(diagnostic)
      completedRelationship.familiarity = math.max(0, math.min(100,
        (completedRelationship.familiarity or 0) + familiarityGain))
      Relationships.recordMutation(entity, completedInvestigationTargetId,
        "INVESTIGATION_COMPLETED", relationshipBefore,
        completedRelationship, tick,
        "src.behavior.controller.chooseState", {
          previousBehaviorState = currentState,
          selectedBehaviorState = runtimeState.state,
          selectedTargetEntityId = selectedEntityTargetId
        })
      diagnostic.phase = "POST_EVENT"
      diagnostic.after = Relationships.snapshot(completedRelationship)
      Relationships.emitDiagnosticEvent(diagnostic)
    end
  end

  -- targetEntityId means "the real entity this behavior is currently acting
  -- on". Only entity-directed behaviors retain it; ambient/idle states must
  -- not inherit whatever the target selector merely proposed this tick.
  if runtimeState.state == "APPROACH" or runtimeState.state == "INVESTIGATE" or runtimeState.state == "FLEE" then
    runtimeState.targetEntityId = runtimeState.state == "FLEE"
      and assessedThreatId
      or selectedEntityTargetId
  elseif runtimeState.state == "SEEK_FLOCK" then
    runtimeState.targetEntityId = decisionContext.flockSearch and decisionContext.flockSearch.targetEntityId or nil
  else
    runtimeState.targetEntityId = nil
  end
  local targetChangedWithinNavigationState = priorState == runtimeState.state
    and (runtimeState.state == "APPROACH"
      or runtimeState.state == "INVESTIGATE"
      or runtimeState.state == "SEEK_FLOCK"
      or runtimeState.state == "FLEE")
    and priorTargetEntityId ~= runtimeState.targetEntityId
  if priorState ~= runtimeState.state or targetChangedWithinNavigationState then
    runtimeState.recentCommittedCells = {}
    clearResolvedSpatialGoal(runtimeState)
    runtimeState.navigation = nil
  end
  if runtimeState.state == "REST" then
    local fatigueStatus = Drives.status(entity, "FATIGUE", tick)
    local selection = runtimeState.restSiteSelection
    if not selection then
      selection = RestSiteResolver.evaluate(entity,
        decisionContext.worldSemantics, decisionContext.position,
        fatigueStatus.value, {
          excludedCells = runtimeState.restSiteRejectedCells
        })
      runtimeState.restSiteSelection = selection
    end
    local selected = selection and selection.selected or nil
    runtimeState.restCandidateCount = selection and #selection.candidates or 0
    runtimeState.restTravelBudget = selection and selection.travelBudget or 0
    runtimeState.currentRestContext = selected and selected.semanticType
      or "VISIBLE_IN_PLACE"
    if selected then
      local goal = SpatialGoal.position({
        cellX = selected.cellX, cellY = selected.cellY
      }, {
        mapId = selected.mapId,
        traversalMode = "WALK",
        source = "REST_SITE"
      })
      runtimeState.restSiteGoal = goal
      runtimeState.restTraveling = not SpatialGoal.isSatisfied(
        goal, decisionContext.position)
      runtimeState.restingActive = not runtimeState.restTraveling
      runtimeState.concealmentRequest = runtimeState.restingActive
        and selected.concealmentPossible and {
          mapId = selected.mapId,
          concealmentType = selected.concealmentKind,
          anchorCell = { cellX = selected.cellX, cellY = selected.cellY },
          requestedTick = tick
        } or nil
    else
      runtimeState.restSiteGoal = nil
      runtimeState.restTraveling = false
      runtimeState.restingActive = true
      runtimeState.concealmentRequest = nil
    end
  elseif runtimeState.state == "RETURN_HOME" then
    local destination = runtimeState.homeReturnDestination
    if not destination then
      destination = HomeArea.selectDestination(entity,
        decisionContext.worldSemantics, decisionContext.position)
      runtimeState.homeReturnDestination = destination
    end
    runtimeState.homeReturnGoal = destination and SpatialGoal.position({
      cellX = destination.cellX, cellY = destination.cellY
    }, {
      mapId = destination.mapId,
      traversalMode = "WALK",
      source = "HOME_AREA"
    }) or nil
  end
  runtimeState.selectedState = runtimeState.state
  runtimeState.selectedTarget = runtimeState.targetEntityId
  if runtimeState.state ~= "FLEE" then
    runtimeState.fleeExecution = nil
  end
  end

  runtimeState.fleeRadius = fleeRadius
  runtimeState.fleeDesiredSafetyDistance = desiredSafetyDistance
  runtimeState.behaviorScores = scores
  runtimeState.selectedScore = scores[runtimeState.state] or 0
  HomeostasisTelemetry.observe(entity, runtimeState.state, tick)
  if runtimeState.motion and runtimeState.motion.active then
    runtimeState.movementRequest = nil
    return runtimeState.state, runtimeState.selectedScore
  end
  local shouldMove, locomotionReason = LocomotionPolicy.decide(
    entity, runtimeState.state, decisionContext, tick, stepCompleted)
  if not shouldMove then
    runtimeState.movementRequest = nil
    runtimeState.locomotionPaused = true
    runtimeState.locomotionPauseReason = locomotionReason
    return runtimeState.state, runtimeState.selectedScore
  end
  runtimeState.locomotionPaused = false
  runtimeState.locomotionPauseReason = nil
  if runtimeState.state == "RETURN_HOME" then
    local goal = runtimeState.homeReturnGoal
    runtimeState.spatialGoal = goal
    runtimeState.goalSatisfied = decisionContext.homeReturn
      and decisionContext.homeReturn.inside == true
    runtimeState.goalSelfPosition = decisionContext.position
    runtimeState.goalTargetPosition = goal and goal.targetPosition or nil
    if runtimeState.goalSatisfied or not goal then
      runtimeState.movementRequest = nil
    else
      runtimeState.movementRequest = NavigationExecution.navigate(
        entity, decisionContext, goal, {
          ownerBehavior = "RETURN_HOME",
          ownerGoalSignature = SpatialGoal.signature(goal),
          tick = tick
        })
    end
  elseif runtimeState.state == "REST" then
    local goal = runtimeState.restSiteGoal
    runtimeState.spatialGoal = goal
    runtimeState.goalSatisfied = goal == nil
      or SpatialGoal.isSatisfied(goal, decisionContext.position)
    runtimeState.goalSelfPosition = decisionContext.position
    runtimeState.goalTargetPosition = goal and goal.targetPosition or nil
    runtimeState.restTraveling = not runtimeState.goalSatisfied
    runtimeState.restingActive = runtimeState.goalSatisfied
    if runtimeState.goalSatisfied then
      runtimeState.movementRequest = nil
    elseif goal then
      runtimeState.movementRequest = NavigationExecution.navigate(
        entity, decisionContext, goal, {
          ownerBehavior = "REST",
          ownerGoalSignature = SpatialGoal.signature(goal),
          tick = tick
        })
    end
  elseif runtimeState.state == "SATISFY_NEED" then
    local opportunity = runtimeState.needOpportunity
    local goal = opportunity and opportunity.goal
    local goalSignature = opportunity and opportunity.goalSignature
    runtimeState.spatialGoal = goal
    runtimeState.goalSatisfied = SpatialGoal.isSatisfied(goal, decisionContext.position)
    runtimeState.goalSelfPosition = decisionContext.position
    runtimeState.goalTargetPosition = goal and goal.targetPosition or nil
    if runtimeState.goalSatisfied then
      runtimeState.movementRequest = nil
    elseif goal then
      runtimeState.movementRequest = NavigationExecution.navigate(
        entity, decisionContext, goal, {
          ownerBehavior = "SATISFY_NEED",
          ownerGoalSignature = goalSignature,
          tick = tick
        })
    else
      runtimeState.movementRequest = nil
    end
  elseif runtimeState.state == "SEEK_FLOCK" then
    local search = decisionContext.flockSearch or {}
    local navigationGoal = NavigationGoal.fromFlockSearch(search)
    local goalSignature = NavigationGoal.signature(navigationGoal)
    local priorNavigation = runtimeState.navigation
    if priorNavigation and priorNavigation.goalSignature ~= nil
      and (priorNavigation.goalSignature ~= goalSignature
        or priorNavigation.mapId ~= decisionContext.mapId) then
      runtimeState.recentCommittedCells = {}
    end
    local routeRequest
    if navigationGoal.kind ~= "SEARCH" then
      local spatialNavigationGoal = {
        kind = navigationGoal.kind,
        source = navigationGoal.source,
        targetEntityId = navigationGoal.targetEntityId,
        targetPosition = navigationGoal.destination,
        radius = navigationGoal.kind == "PROXIMITY" and 1 or 0,
        allowOverlap = true,
        alignment = "ANY",
        objective = "TOWARD",
        mapId = decisionContext.mapId,
        traversalMode = "WALK"
      }
      routeRequest, navigation = NavigationExecution.navigate(
        entity, decisionContext, spatialNavigationGoal, {
          tick = tick,
          ownerBehavior = "SEEK_FLOCK",
          ownerGoalSignature = goalSignature,
          plannerGoal = navigationGoal,
          forcePlanner = true,
          deferOccupiedAction = true,
          isGoalSatisfied = function(goal, position)
            return goal.kind ~= "DIRECTIONAL_REGION"
              and SpatialGoal.isSatisfied(goal, position)
          end
        })
      navigation.goalSignature = goalSignature
      navigation.goalSource = navigationGoal.source
      navigation.targetEntityId = navigationGoal.targetEntityId
    else
      runtimeState.navigation = nil
      navigation = nil
    end
    local route = navigation and navigation.route or nil
    local action = NavigationEpisode.currentAction(route)
    if action and decisionContext.occupiedCells
      and decisionContext.occupiedCells[WorldSemantics.cellKey(
        action.destination.cellX, action.destination.cellY)] then
      local persistent, releaseReason = suspendRouteForOccupancy(
        entity, navigation, action, decisionContext, tick)
      if persistent then
        navigation.dynamicBlockedEdges = navigation.dynamicBlockedEdges or {}
        navigation.dynamicBlockedEdges[navigation.recentDynamicBlockedEdge] = true
        navigation.route = nil
        navigation.routeSuspended = false
        navigation.routeReleased = true
        navigation.releaseReason = releaseReason
        navigation.replanReason = "PERSISTENT_DYNAMIC_OCCUPANCY"
        runtimeState.pendingOccupancyEpisodeFailure = {
          tick = tick,
          blockedCell = navigation.blockedCell
        }
      else
        navigation.replanReason = "ROUTE_WAITING_FOR_OCCUPANCY"
      end
      route, action = navigation.route, nil
    elseif action then
      navigation.routeReleased = false
      navigation.releaseReason = nil
      clearRouteOccupancyWait(navigation)
    end
    if action then
      navigation.waypoint = route.waypoint
      runtimeState.spatialGoal = nil
      runtimeState.goalSatisfied = false
      runtimeState.goalSelfPosition = decisionContext.position
      runtimeState.goalTargetPosition = action.destination
      runtimeState.movementRequest = routeRequest
    elseif navigation and navigation.routeSuspended then
      runtimeState.spatialGoal = nil
      runtimeState.goalSatisfied = false
      runtimeState.movementRequest = nil
    else
      local targetPosition = (navigationGoal.kind == "POSITION" or navigationGoal.kind == "PROXIMITY")
        and navigationGoal.destination or nil
      if not targetPosition and decisionContext.position then
      local destination = runtimeState.flockSearchDestination
      if not destination then
        runtimeState.flockSearchCounter = (runtimeState.flockSearchCounter or 0) + 1
        local targetId, generated = buildTargetDestination(
          entity,
          decisionContext.position,
          tick,
          runtimeState.flockSearchCounter,
          runtimeState.lastFlockSearchDirectionId,
          nil
        )
        destination = generated and { id = targetId, cellX = generated.cellX, cellY = generated.cellY } or nil
        runtimeState.flockSearchDestination = destination
        runtimeState.lastFlockSearchDirectionId = targetId
      end
      targetPosition = destination and { cellX = destination.cellX, cellY = destination.cellY } or nil
      end
      local goalTargetId = runtimeState.targetEntityId or "flock_search"
      local targetPositions = targetPosition and { [goalTargetId] = targetPosition } or {}
      local goal = SpatialGoal.resolve(goalTargetId, targetPositions,
        navigationGoal.kind == "PROXIMITY" and 1
          or targetPosition == navigationGoal.destination and 1 or 0, {
        alignment = "ANY",
        allowOverlap = navigationGoal.kind == "SEARCH"
      })
      runtimeState.spatialGoal = goal
      runtimeState.goalSatisfied = SpatialGoal.isSatisfied(goal, decisionContext.position)
      runtimeState.goalSelfPosition = decisionContext.position
      runtimeState.goalTargetPosition = targetPosition
      runtimeState.movementRequest = Steering.request(decisionContext.position, goal, {
        rejectedDirections = runtimeState.rejectedMoves,
        mapId = decisionContext.mapId,
        directOnly = navigationGoal.kind == "SEARCH"
      })
    end
    runtimeState.searchCueSource = search.cueSource or "search"
    runtimeState.searchCueDirection = search.cueDirection
    runtimeState.searchIsolationPressure = search.isolationPressure or 0
  elseif runtimeState.state == "TARGET" then
    local currentPosition = decisionContext.position
    if not currentPosition then
      runtimeState.spatialGoal = nil
      runtimeState.goalSatisfied = false
      runtimeState.movementRequest = nil
      return runtimeState.state, runtimeState.selectedScore
    end
    local targetDestination = runtimeState.targetDestination
    if not targetDestination then
      runtimeState.targetCounter = (runtimeState.targetCounter or 0) + 1
      local targetId, targetPosition = buildTargetDestination(entity, currentPosition,
        tick, runtimeState.targetCounter, runtimeState.lastTargetDirectionId,
        decisionContext.groupHeadingBias,
        physiology.wanderScale)
      targetDestination = { id = targetId, cellX = targetPosition and targetPosition.cellX, cellY = targetPosition and targetPosition.cellY }
      runtimeState.targetDestination = targetDestination
      runtimeState.lastTargetDirectionId = targetId
    end
    local targetId = targetDestination.id
    local targetPosition = { cellX = targetDestination.cellX, cellY = targetDestination.cellY }
    -- targetId here is a synthetic direction placeholder (target_up/down/
    -- left/right), not a real entity \u2014 it must stay out of
    -- runtimeState.targetEntityId, which is reserved for actual entities.
    local targetPositions = decisionContext.targetPositions or {}
    targetPositions[targetId] = targetPosition
    runtimeState.spatialGoal = SpatialGoal.resolve(targetId, targetPositions, 0, {
      alignment = "ANY",
      allowOverlap = true,
      mapId = decisionContext.mapId,
      traversalMode = "WALK",
      source = "ambient_destination"
    })
    runtimeState.goalSatisfied = SpatialGoal.isSatisfied(runtimeState.spatialGoal, decisionContext.position)
    runtimeState.goalSelfPosition = decisionContext.position
    runtimeState.goalTargetPosition = targetPosition
    if decisionContext.position then
      local dx = math.abs(decisionContext.position.cellX - targetPosition.cellX)
      local dy = math.abs(decisionContext.position.cellY - targetPosition.cellY)
      runtimeState.goalDx = dx
      runtimeState.goalDy = dy
      runtimeState.goalManhattan = dx + dy
      runtimeState.goalChebyshev = math.max(dx, dy)
    else
      runtimeState.goalDx = nil
      runtimeState.goalDy = nil
      runtimeState.goalManhattan = nil
      runtimeState.goalChebyshev = nil
    end
    runtimeState.movementRequest = NavigationExecution.navigate(
      entity, decisionContext, runtimeState.spatialGoal, {
        ownerBehavior = "TARGET",
        tick = tick
      })
  elseif runtimeState.state == "FLEE" or runtimeState.state == "APPROACH" or runtimeState.state == "INVESTIGATE" then
    local goalRadius = runtimeState.state == "INVESTIGATE"
      and (decisionContext.investigateRadius or 3)
      or runtimeState.state == "FLEE"
      and (decisionContext.fleeSafetyDistance or desiredSafetyDistance or decisionContext.fleeRadius or 1)
      or (decisionContext.goalRadius or 1)
    local goalTargetId = runtimeState.targetEntityId
    local goalTargetPositions = decisionContext.targetPositions
    local escapeReference
    if runtimeState.state == "FLEE" then
      escapeReference = resolveEscapeReference(runtimeState, decisionContext, assessedThreatId, tick)
      runtimeState.escapeReference = escapeReference
      goalTargetId = escapeReference.entityId or "escape_reference"
      goalTargetPositions = escapeReference.position and {
        [goalTargetId] = escapeReference.position
      } or {}
    end
    local goal = SpatialGoal.resolve(goalTargetId, goalTargetPositions, goalRadius, {
      alignment = runtimeState.state == "APPROACH" and "CARDINAL" or "ANY",
      objective = runtimeState.state == "FLEE" and "AWAY" or "TOWARD",
      allowOverlap = false,
      mapId = decisionContext.mapId,
      traversalMode = "WALK",
      source = string.lower(runtimeState.state)
    })
    runtimeState.spatialGoal = goal
    runtimeState.goalSatisfied = SpatialGoal.isSatisfied(goal, decisionContext.position)
    if runtimeState.state == "APPROACH" and runtimeState.goalSatisfied then
      runtimeState.goalSatisfiedSinceTick = runtimeState.goalSatisfiedSinceTick or tick
    else
      runtimeState.goalSatisfiedSinceTick = nil
    end
    runtimeState.goalSelfPosition = decisionContext.position
    runtimeState.goalTargetPosition = goal and goal.targetPosition or nil
    if decisionContext.position and goal and goal.targetPosition then
      local dx = math.abs(decisionContext.position.cellX - goal.targetPosition.cellX)
      local dy = math.abs(decisionContext.position.cellY - goal.targetPosition.cellY)
      runtimeState.goalDx = dx
      runtimeState.goalDy = dy
      runtimeState.goalManhattan = dx + dy
      runtimeState.goalChebyshev = math.max(dx, dy)
    else
      runtimeState.goalDx = nil
      runtimeState.goalDy = nil
      runtimeState.goalManhattan = nil
      runtimeState.goalChebyshev = nil
    end
    local usedEscapeRoute = false
    if runtimeState.state == "FLEE" and decisionContext.position and goal and goal.targetPosition then
      local execution = runtimeState.fleeExecution
      local currentThreatSourceId = escapeThreatSourceId(escapeReference)
      local committedRoute = execution and execution.route ~= nil
      local blockedPlanning = execution and (execution.planningState == "PLAN_BLOCKED_UNCHANGED"
        or execution.planningState == "WAITING_FOR_ROUTE_CELL")
      local sameRouteThreatSource = committedRoute and sameDirectThreatSource(
        execution.routeThreatReferenceKind,
        execution.routeThreatSourceId,
        escapeReference.kind,
        currentThreatSourceId
      )
      if not execution or (not committedRoute and not blockedPlanning
        and (execution.escapeReferenceKind ~= escapeReference.kind
          or execution.routeThreatSourceId ~= currentThreatSourceId)) then
        local initialSafety = Utility.chebyshevDistance(decisionContext.position, goal.targetPosition)
        execution = {
          threatEntityId = runtimeState.targetEntityId,
          routeThreatSourceId = currentThreatSourceId,
          escapeReferenceKind = escapeReference.kind,
          bestThreatDistance = initialSafety,
          noProgressSteps = 0,
          staticRejections = 0,
          crowdBlocks = 0,
          escapeMode = false,
          fleeMode = "NORMAL",
          planningState = "LOCAL_STEERING",
          recentCells = appendRecentCell({}, decisionContext.position,
            runtimeState.targetEntityId or escapeReference.kind, FLEE_RECENT_CELL_LIMIT),
          intent = {
            threatId = runtimeState.targetEntityId,
            establishedTick = tick,
            originCell = { cellX = decisionContext.position.cellX, cellY = decisionContext.position.cellY },
            bestSafetyReached = initialSafety,
            commitmentUntilTick = tick + FLEE_INTENT_MIN_TICKS,
            lastMeaningfulProgressTick = tick
          }
        }
        runtimeState.fleeExecution = execution
        runtimeState.recentCommittedCells = appendRecentCell(
          runtimeState.recentCommittedCells,
          decisionContext.position,
          runtimeState.targetEntityId or escapeReference.kind,
          FLEE_RECENT_CELL_LIMIT
        )
      elseif committedRoute then
        execution.currentThreatSourceId = currentThreatSourceId
        execution.sameThreatSource = sameRouteThreatSource
        execution.routeRevalidated = false
        execution.routeRevalidationReason = "PENDING"
        if execution.routeThreatSourceId ~= currentThreatSourceId then
          execution.route = nil
          execution.planningState = "NEEDS_REPLAN"
          clearRouteOccupancyWait(execution)
          execution.routeInvalidationReason = "THREAT_SOURCE_CHANGED"
          execution.routeInvalidationTick = tick
          execution.routeCommitment = false
          execution.routeCommitmentReason = "THREAT_SOURCE_CHANGED"
          execution.routeRevalidationReason = "DIFFERENT_THREAT_SOURCE"
          execution.lastPlanningDirtyReason = "ThreatIdChange"
          execution.lastPlanningDirtyTick = tick
          FleeEscape.recordDirtyEvent("ThreatIdChange")
        elseif execution.routeThreatReferenceKind ~= escapeReference.kind
          and not sameRouteThreatSource then
          execution.route = nil
          execution.planningState = "NEEDS_REPLAN"
          clearRouteOccupancyWait(execution)
          execution.routeInvalidationReason = "THREAT_REFERENCE_CHANGED"
          execution.routeInvalidationTick = tick
          execution.routeCommitment = false
          execution.routeCommitmentReason = "THREAT_REFERENCE_CHANGED"
          execution.routeRevalidationReason = "INCOMPATIBLE_REFERENCE_CHANGE"
          local referenceDirtyReason = (execution.routeThreatReferenceKind == "SOCIAL_ESCAPE_VECTOR"
            or escapeReference.kind == "SOCIAL_ESCAPE_VECTOR")
            and "SocialVectorChange" or "ThreatGeometryChange"
          execution.lastPlanningDirtyReason = referenceDirtyReason
          execution.lastPlanningDirtyTick = tick
          FleeEscape.recordDirtyEvent(referenceDirtyReason)
        end
      end

      observeSocialVector(runtimeState, escapeReference)
      local escapeHeading = EscapeHeading.update(entity, decisionContext.position, goal.targetPosition, {
        neighbors = decisionContext.fleeNeighbors,
        socialAlignment = runtimeState.socialEscapeBias,
        isWalkable = decisionContext.worldSemantics and function(from, destination)
          return WorldSemantics.isLandingAllowed(
            decisionContext.worldSemantics, destination.cellX, destination.cellY, "WALK"
          ) and WorldSemantics.isEdgeAllowed(
            decisionContext.worldSemantics,
            from.cellX, from.cellY, destination.cellX, destination.cellY, "WALK"
          )
        end or nil,
        recoveryProgress = runtimeState.fleeRecoveryProgress or 0,
        threatPositionConfidence = escapeReference.confidence,
        completedDirection = stepCompleted and priorMovementRequest
          and priorMovementRequest.traversalMode == "WALK"
          and priorMovementRequest.direction or nil
      }, tick)

      if execution.planningState == "PLAN_BLOCKED_UNCHANGED"
        and execution.failedPlanningContext then
        local dirtyReason = failedPlanningDirtyReason(
          execution.failedPlanningContext, runtimeState, decisionContext,
          decisionContext.position, goal.targetPosition, currentThreatSourceId,
          escapeReference, tick)
        if dirtyReason then
          execution.planningState = "NEEDS_REPLAN"
          execution.lastPlanningDirtyReason = dirtyReason
          execution.lastPlanningDirtyTick = tick
          execution.failedPlanningContext = nil
          FleeEscape.recordDirtyEvent(dirtyReason)
        end
      end

      local rejection = priorMovementRequest and priorMovementRequest.rejectionReason
      local rejectionSignature = priorMovementRequest and table.concat({
        tostring(priorMovementRequest.issuedTick or "none"),
        tostring(priorMovementRequest.direction or "none"),
        tostring(rejection or "none")
      }, ":") or nil
      if rejection and rejection ~= "MOVEMENT_ACTIVE"
        and rejectionSignature ~= execution.lastHandledRejection then
        execution.lastHandledRejection = rejectionSignature
        local rejectedRoute = execution.route
        execution.route = nil
        execution.routeInvalidationTick = tick
        if rejection == "tile" or rejection == "bounds" then
          execution.staticRejections = (execution.staticRejections or 0) + 1
          execution.noProgressSteps = (execution.noProgressSteps or 0) + 1
          execution.routeInvalidationReason = "STATIC_REJECTION"
          execution.planningState = "NEEDS_REPLAN"
          execution.failedPlanningContext = nil
          execution.lastPlanningDirtyReason = "StaticRejection"
          execution.lastPlanningDirtyTick = tick
          if execution.staticRejections >= FLEE_STATIC_REJECTION_THRESHOLD then
            execution.escapeMode = true
            execution.stuckReason = "REPEATED_STATIC_REJECTION"
          end
        elseif rejection == "entity" then
          execution.crowdBlocks = (execution.crowdBlocks or 0) + 1
          execution.escapeMode = true
          execution.stuckReason = "CROWD_BLOCK"
          local route = rejectedRoute
          local blockedAction = route and route.actions[route.index or 1] or nil
          if blockedAction then
            local persistent, releaseReason = suspendRouteForOccupancy(
              entity, execution, blockedAction, decisionContext, tick)
            if persistent then
              execution.recentDynamicBlockedBottlenecks
                = execution.recentDynamicBlockedBottlenecks or {}
              execution.recentDynamicBlockedBottlenecks[
                execution.recentDynamicBlockedBottleneck] =
                (execution.recentDynamicBlockedBottlenecks[
                  execution.recentDynamicBlockedBottleneck] or 0) + 1
              execution.route = nil
              execution.planningState = "PLAN_BLOCKED_UNCHANGED"
              execution.routeSuspended = false
              execution.routeReleased = true
              execution.releaseReason = releaseReason
              execution.routeInvalidationReason = "PERSISTENT_DYNAMIC_OCCUPANCY"
              execution.routeInvalidationTick = tick
              execution.routeCommitment = false
            else
              execution.route = route
              execution.planningState = "WAITING_FOR_ROUTE_CELL"
              execution.routeInvalidationReason = "ROUTE_WAITING_FOR_OCCUPANCY"
            end
          end
        else
          execution.planningState = "NEEDS_REPLAN"
          execution.routeInvalidationReason = string.upper(tostring(rejection))
        end
      end

      local routeSocialChanged = execution.route
        and (execution.routeThreatReferenceKind == "SOCIAL_ESCAPE_VECTOR"
          or escapeReference.kind == "SOCIAL_ESCAPE_VECTOR")
        and (execution.routeThreatReferenceKind ~= escapeReference.kind
          or execution.routeSocialVectorDirection ~= socialVectorDirection(escapeReference))
      if routeSocialChanged then
        execution.route = nil
        execution.planningState = "NEEDS_REPLAN"
        clearRouteOccupancyWait(execution)
        execution.routeInvalidationReason = "SOCIAL_ESCAPE_VECTOR_CHANGED"
        execution.routeInvalidationTick = tick
        execution.routeCommitment = false
        execution.routeCommitmentReason = "SOCIAL_ESCAPE_VECTOR_CHANGED"
        execution.routeRevalidationReason = "SOCIAL_ESCAPE_VECTOR_CHANGED"
        execution.lastPlanningDirtyReason = "SocialVectorChange"
        execution.lastPlanningDirtyTick = tick
        FleeEscape.recordDirtyEvent("SocialVectorChange")
      end
      local threatMoved = execution.route and execution.routeThreatPosition
        and Utility.chebyshevDistance(execution.routeThreatPosition, goal.targetPosition) > 1
      if threatMoved then
        execution.route = nil
        execution.planningState = "NEEDS_REPLAN"
        execution.routeInvalidationReason = "THREAT_MOVED"
        execution.routeInvalidationTick = tick
        execution.routeCommitment = false
        execution.routeCommitmentReason = "THREAT_MOVED"
        execution.routeRevalidationReason = "THREAT_MOVED"
        execution.lastPlanningDirtyReason = "ThreatGeometryChange"
        execution.lastPlanningDirtyTick = tick
        FleeEscape.recordDirtyEvent("ThreatGeometryChange")
      end
      if execution.route and execution.routeMapId ~= decisionContext.mapId then
        execution.route = nil
        execution.planningState = "NEEDS_REPLAN"
        execution.routeInvalidationReason = "MAP_CHANGED"
        execution.routeInvalidationTick = tick
        execution.routeCommitment = false
        execution.routeCommitmentReason = "MAP_CHANGED"
        execution.routeRevalidationReason = "MAP_CHANGED"
        execution.lastPlanningDirtyReason = "TopologyChange"
        execution.lastPlanningDirtyTick = tick
        FleeEscape.recordDirtyEvent("TopologyChange")
      end

      if execution.route and execution.escapeEndpoint then
        local currentDistance = Utility.chebyshevDistance(
          decisionContext.position, goal.targetPosition)
        local endpointDistance = Utility.chebyshevDistance(
          execution.escapeEndpoint, goal.targetPosition)
        if currentDistance == nil or endpointDistance == nil
          or endpointDistance <= currentDistance then
          execution.route = nil
          execution.planningState = "NEEDS_REPLAN"
          execution.routeSuspended = false
          execution.routeInvalidationReason = "ENDPOINT_NO_LONGER_SAFER"
          execution.routeInvalidationTick = tick
          execution.routeCommitment = false
          execution.routeCommitmentReason = "ENDPOINT_NO_LONGER_SAFER"
          execution.routeRevalidationReason = "ENDPOINT_NO_LONGER_SAFER"
        else
          local baseline = execution.routeRegressionBaselineDistance or currentDistance
          execution.routeRegressionDebt = math.max(0, baseline - currentDistance)
          execution.routeTemporaryRegressionActive = execution.temporaryThreatRegression == true
            and execution.routeRegressionDebt > 0
          execution.routeRevalidated = true
          execution.routeRevalidationReason = sameRouteThreatSource
            and "SAME_SOURCE_OBSERVABILITY_CHANGED" or "GEOMETRY_VALID"
        end
      end

      local localAnalysis = decisionContext.worldSemantics
        and FleeEscape.analyzeLocal(entity, decisionContext.worldSemantics, decisionContext.position, goal.targetPosition, {
          rejectedDirections = runtimeState.rejectedMoves,
          mapId = decisionContext.mapId,
          occupiedCells = decisionContext.occupiedCells,
          currentOccupiedCells = decisionContext.currentOccupiedCells,
          vacatingCells = decisionContext.vacatingCells,
          movementClaims = decisionContext.movementClaims,
          recentCells = execution.recentCells,
          previousCellKey = execution.previousCell
        }) or nil
      execution.localCandidates = localAnalysis and localAnalysis.candidates or nil
      execution.localEscapeRecovered = false
      execution.threatDistance = localAnalysis and localAnalysis.currentThreatDistance
        or Utility.chebyshevDistance(decisionContext.position, goal.targetPosition)
      execution.threatCell = cellKey(goal.targetPosition)

      if localAnalysis and localAnalysis.usefulMoveCount > 0 then
        if execution.route then
          execution.planningState = "FOLLOWING_ROUTE"
          execution.escapeMode = true
          execution.fleeMode = "ESCAPE_ROUTE"
          execution.routeCommitment = true
          execution.routeCommitmentReason = "VALID_ROUTE_TO_SAFER_FRONTIER"
          execution.localEscapeRecovered = true
        elseif execution.planningState == "PLAN_BLOCKED_UNCHANGED" then
          execution.escapeMode = false
          execution.fleeMode = "NORMAL"
          execution.planningState = "LOCAL_STEERING"
          execution.failedPlanningContext = nil
          execution.routeCommitment = false
          execution.routeCommitmentReason = "LOCAL_ESCAPE_AVAILABLE"
          execution.localEscapeRecovered = true
        elseif execution.oscillationDetected then
          execution.escapeMode = true
          execution.fleeMode = "ESCAPE_ROUTE"
          execution.routeCommitment = false
          execution.routeCommitmentReason = "OSCILLATION_REPLAN"
          if execution.planningState ~= "PLAN_BLOCKED_UNCHANGED" then
            execution.planningState = "NEEDS_REPLAN"
          end
        else
          execution.escapeMode = false
          execution.fleeMode = "NORMAL"
          execution.routeCommitment = false
          execution.routeCommitmentReason = "LOCAL_ESCAPE_AVAILABLE"
          execution.localEscapeRecovered = false
          execution.planningState = "LOCAL_STEERING"
        end
        execution.stuckReason = nil
      elseif localAnalysis then
        execution.escapeMode = true
        execution.fleeMode = "ESCAPE_ROUTE"
        if execution.planningState == nil
          or execution.planningState == "LOCAL_STEERING" then
          execution.planningState = "NEEDS_PLAN"
        end
        if not execution.stuckReason then
          local staticCount, occupiedCount = 0, 0
          for _, candidate in ipairs(localAnalysis.candidates) do
            staticCount = staticCount + (candidate.staticLegal and 1 or 0)
            occupiedCount = occupiedCount + (candidate.occupied and 1 or 0)
          end
          execution.stuckReason = staticCount == 0 and "STATIC_BLOCK"
            or occupiedCount == staticCount and "CROWD_BLOCK"
            or "NO_USEFUL_LOCAL_MOVE"
        end
      end

      local route = execution.route
      local action = route and route.actions[route.index or 1] or nil
      if action and (not action.source
        or action.source.cellX ~= decisionContext.position.cellX
        or action.source.cellY ~= decisionContext.position.cellY) then
        execution.route = nil
        execution.planningState = "NEEDS_REPLAN"
        execution.routeInvalidationReason = "SOURCE_POSITION_MISMATCH"
        execution.routeInvalidationTick = tick
        execution.routeCommitment = false
        execution.routeCommitmentReason = "SOURCE_POSITION_MISMATCH"
        execution.routeRevalidationReason = "SOURCE_POSITION_MISMATCH"
        action = nil
      end
      if action and decisionContext.worldSemantics then
        local nextActionLegal = WorldSemantics.isLandingAllowed(
          decisionContext.worldSemantics,
          action.destination.cellX,
          action.destination.cellY,
          "WALK"
        ) and WorldSemantics.isEdgeAllowed(
          decisionContext.worldSemantics,
          action.source.cellX,
          action.source.cellY,
          action.destination.cellX,
          action.destination.cellY,
          "WALK"
        ) and cellKey(action.destination) ~= cellKey(goal.targetPosition)
        if not nextActionLegal then
          execution.route = nil
          execution.planningState = "NEEDS_REPLAN"
          execution.routeInvalidationReason = "NEXT_ACTION_INVALID"
          execution.routeInvalidationTick = tick
          execution.routeCommitment = false
          execution.routeCommitmentReason = "NEXT_ACTION_INVALID"
          execution.routeRevalidationReason = "NEXT_ACTION_INVALID"
          action = nil
        end
      end
      if action and decisionContext.occupiedCells
        and decisionContext.occupiedCells[WorldSemantics.cellKey(action.destination.cellX, action.destination.cellY)] then
        local persistent, releaseReason = suspendRouteForOccupancy(
          entity, execution, action, decisionContext, tick)
        execution.stuckReason = "CROWD_BLOCK"
        execution.routeCommitmentReason = "ROUTE_WAITING_FOR_OCCUPANCY"
        execution.routeRevalidationReason = "ROUTE_WAITING_FOR_OCCUPANCY"
        if persistent then
          execution.recentDynamicBlockedBottlenecks
            = execution.recentDynamicBlockedBottlenecks or {}
          execution.recentDynamicBlockedBottlenecks[
            execution.recentDynamicBlockedBottleneck] =
              (execution.recentDynamicBlockedBottlenecks[
                execution.recentDynamicBlockedBottleneck] or 0) + 1
          execution.route = nil
          execution.planningState = "PLAN_BLOCKED_UNCHANGED"
          execution.routeSuspended = false
          execution.routeReleased = true
          execution.releaseReason = releaseReason
          execution.routeInvalidationReason = "PERSISTENT_DYNAMIC_OCCUPANCY"
          execution.routeInvalidationTick = tick
          execution.routeCommitment = false
          execution.routeCommitmentReason = "PERSISTENT_DYNAMIC_OCCUPANCY"
          execution.routeRevalidationReason = "PERSISTENT_DYNAMIC_OCCUPANCY"
        end
        if not persistent then
          execution.planningState = "WAITING_FOR_ROUTE_CELL"
        end
        action = nil
      elseif action then
        execution.planningState = "FOLLOWING_ROUTE"
        execution.failedPlanningContext = nil
        execution.routeReleased = false
        execution.releaseReason = nil
        clearRouteOccupancyWait(execution)
      end
      if execution.planningState == "PLAN_BLOCKED_UNCHANGED" then
        if not execution.failedPlanningContext then
          execution.failedPlanningContext = captureFailedPlanningContext(
            execution, runtimeState, decisionContext, decisionContext.position,
            goal.targetPosition, currentThreatSourceId, escapeReference,
            execution.routeInvalidationReason or execution.stuckReason, tick)
        end
        local dirtyReason = failedPlanningDirtyReason(
          execution.failedPlanningContext, runtimeState, decisionContext,
          decisionContext.position, goal.targetPosition, currentThreatSourceId,
          escapeReference, tick)
        if dirtyReason then
          execution.planningState = "NEEDS_REPLAN"
          execution.lastPlanningDirtyReason = dirtyReason
          execution.lastPlanningDirtyTick = tick
          execution.failedPlanningContext = nil
          FleeEscape.recordDirtyEvent(dirtyReason)
        else
          FleeEscape.recordSuppressedPlan()
        end
      end
      local planningEligible = execution.planningState == "NEEDS_PLAN"
        or execution.planningState == "NEEDS_REPLAN"
      if execution.escapeMode and planningEligible and not action
        and not execution.routeSuspended and decisionContext.worldSemantics then
        route = FleeEscape.plan(entity, decisionContext.worldSemantics, decisionContext.position, goal.targetPosition, {
          maxDepth = FLEE_ESCAPE_DEPTH,
          maxExpansions = FLEE_ESCAPE_EXPANSIONS,
          rejectedDirections = runtimeState.rejectedMoves,
          mapId = decisionContext.mapId,
          occupiedCells = decisionContext.occupiedCells,
          currentOccupiedCells = decisionContext.currentOccupiedCells,
          vacatingCells = decisionContext.vacatingCells,
          movementClaims = decisionContext.movementClaims,
          recentCells = execution.recentCells,
          dynamicBlockedBottlenecks = execution.recentDynamicBlockedBottlenecks,
          preferredHeading = escapeHeading
        })
        execution.route = route
        execution.planningState = route and "FOLLOWING_ROUTE"
          or "PLAN_BLOCKED_UNCHANGED"
        execution.routeMapId = decisionContext.mapId
        execution.routeThreatPosition = { cellX = goal.targetPosition.cellX, cellY = goal.targetPosition.cellY }
        execution.routeThreatSourceId = currentThreatSourceId
        execution.routeThreatReferenceKind = escapeReference.kind
        execution.routeSocialVectorDirection = socialVectorDirection(escapeReference)
        execution.routeEstablishedTick = tick
        execution.currentThreatSourceId = currentThreatSourceId
        execution.sameThreatSource = route ~= nil
          and execution.routeThreatSourceId == currentThreatSourceId
        execution.routeRevalidated = route ~= nil
        execution.routeRevalidationReason = route and "NEW_BOUNDED_ROUTE" or "NO_ESCAPE_ROUTE"
        execution.escapeRouteLength = route and #route.actions or 0
        execution.escapeEndpoint = route and route.endpoint or nil
        execution.endpointSafetyScore = route and route.endpointSafetyScore or nil
        execution.endpointThreatDistance = route and route.endpointThreatDistance or nil
        execution.endpointMobility = route and route.endpointMobility or nil
        execution.nextStepThreatDelta = route and route.nextStepThreatDelta or nil
        execution.temporaryThreatRegression = route and route.temporaryThreatRegression or false
        execution.routeRegressionBaselineDistance = route and execution.threatDistance or nil
        execution.routeRegressionDebt = route
          and math.max(0, -(route.nextStepThreatDelta or 0)) or 0
        execution.routeTemporaryRegressionActive = route
          and route.temporaryThreatRegression == true or false
        execution.recentPathPenalty = route and route.recentPathPenalty or 0
        execution.routeCommitment = route ~= nil
        execution.routeCommitmentReason = route and "BOUNDED_ESCAPE_ROUTE" or "NO_ESCAPE_ROUTE"
        execution.failedPlanningContext = route and nil
          or captureFailedPlanningContext(
            execution, runtimeState, decisionContext, decisionContext.position,
            goal.targetPosition, currentThreatSourceId, escapeReference,
            "NO_ESCAPE_ROUTE", tick)
        if route and execution.intent then
          execution.intent.heading = route.actions[1] and route.actions[1].direction or nil
          execution.intent.routeId = string.format("%s,%s", route.endpoint.cellX, route.endpoint.cellY)
        end
        action = route and route.actions[route.index or 1] or nil
      end
      execution.routeExpectedSource = action and copyPosition(action.source) or nil
      execution.routeNextAction = action and action.direction or nil
      execution.localGreedyCandidate = nil
      local bestLocalDelta = -math.huge
      for _, candidate in ipairs(localAnalysis and localAnalysis.candidates or {}) do
        if candidate.staticLegal and not candidate.occupied and not candidate.rejected
          and candidate.threatDelta > bestLocalDelta then
          bestLocalDelta = candidate.threatDelta
          execution.localGreedyCandidate = candidate.direction
        end
      end
      execution.localGreedySuppressedByRoute = action ~= nil
      if action then
        runtimeState.movementRequest = {
          direction = action.direction,
          traversalMode = "WALK",
          targetEntityId = runtimeState.targetEntityId,
          primaryThreatId = assessedThreatId,
          escapeReferenceKind = escapeReference.kind,
          escapeReferenceEntityId = escapeReference.entityId,
          goalKind = "FLEE_ESCAPE_ROUTE",
          sourceX = action.source.cellX,
          sourceY = action.source.cellY,
          destinationX = action.destination.cellX,
          destinationY = action.destination.cellY,
          routeLength = #execution.route.actions,
          routeIndex = execution.route.index or 1,
          waypoint = execution.route.endpoint,
          issuedTick = tick
        }
        usedEscapeRoute = true
        execution.chosenReason = execution.routeCommitmentReason
      elseif execution.escapeMode and execution.routeSuspended then
        runtimeState.movementRequest = nil
        usedEscapeRoute = true
      elseif execution.escapeMode then
        runtimeState.movementRequest = {
          direction = "STAY",
          traversalMode = "NONE",
          targetEntityId = runtimeState.targetEntityId,
          primaryThreatId = assessedThreatId,
          escapeReferenceKind = escapeReference.kind,
          escapeReferenceEntityId = escapeReference.entityId,
          goalKind = "FLEE_ESCAPE_ROUTE",
          reason = "NO_ESCAPE_ROUTE",
          issuedTick = tick
        }
        usedEscapeRoute = true
      end
    end
    if not usedEscapeRoute and runtimeState.state ~= "FLEE" then
      runtimeState.movementRequest = NavigationExecution.navigate(
        entity, decisionContext, goal, {
          ownerBehavior = runtimeState.state,
          tick = tick
        })
    elseif not usedEscapeRoute then
      local execution = runtimeState.state == "FLEE" and runtimeState.fleeExecution or nil
      runtimeState.movementRequest = Steering.request(decisionContext.position, goal, {
        rejectedDirections = runtimeState.rejectedMoves,
        mapId = decisionContext.mapId,
        occupiedCells = decisionContext.occupiedCells,
        currentOccupiedCells = decisionContext.currentOccupiedCells,
        movementClaims = decisionContext.movementClaims,
        actorId = entity.id,
        escapeMode = runtimeState.state == "FLEE"
          and runtimeState.fleeExecution
          and runtimeState.fleeExecution.escapeMode == true,
        recentCells = runtimeState.state == "FLEE"
          and runtimeState.fleeExecution
          and runtimeState.fleeExecution.recentCells
          or nil,
        previousCellKey = runtimeState.state == "FLEE"
          and runtimeState.fleeExecution
          and runtimeState.fleeExecution.previousCell
          or nil,
        desiredHeading = runtimeState.state == "FLEE" and runtimeState.escapeHeading or nil,
        headingResidual = runtimeState.state == "FLEE" and runtimeState.escapeHeading and {
          dx = runtimeState.escapeHeading.residualX,
          dy = runtimeState.escapeHeading.residualY
        } or nil
      })
      if runtimeState.movementRequest then runtimeState.movementRequest.issuedTick = tick end
      if runtimeState.state == "FLEE" and runtimeState.movementRequest then
        runtimeState.movementRequest.targetEntityId = escapeReference.entityId
        runtimeState.movementRequest.primaryThreatId = assessedThreatId
        runtimeState.movementRequest.escapeReferenceKind = escapeReference.kind
        runtimeState.movementRequest.escapeReferenceEntityId = escapeReference.entityId
      end
      if runtimeState.state == "FLEE" and runtimeState.fleeExecution then
        runtimeState.fleeExecution.chosenReason = runtimeState.movementRequest.reason or "NORMAL_LOCAL_STEERING"
      end
    end
  else
    if runtimeState.state == "IDLE" or runtimeState.state == "SETTLED"
      or runtimeState.state == "REST" then
      runtimeState.targetEntityId = nil
    end
    clearResolvedSpatialGoal(runtimeState)
    runtimeState.movementRequest = nil
  end
  if runtimeState.state == "FLEE" and runtimeState.fleeExecution then
    local execution = runtimeState.fleeExecution
    local request = runtimeState.movementRequest or {}
    execution.currentCell = decisionContext.position and cellKey(decisionContext.position) or nil
    execution.nextCell = request.destinationX ~= nil and request.destinationY ~= nil
      and tostring(request.destinationX) .. "," .. tostring(request.destinationY) or nil
    execution.reservationCount = decisionContext.reservationCount or 0
    execution.occupiedCellCount = decisionContext.occupiedCellCount or 0
    execution.nextCellReserved = execution.nextCell ~= nil
      and decisionContext.occupiedCells
      and decisionContext.occupiedCells[execution.nextCell] == true
      or false
  end
  if runtimeState.movementRequest and runtimeState.movementRequest.issuedTick == nil then
    runtimeState.movementRequest.issuedTick = tick
  end
  if runtimeState.state == "FLEE" then
    local request = runtimeState.movementRequest
    if not request then
      runtimeState.fleeStallReason = "WAITING_FOR_ESCAPE_ROUTE"
    elseif request.direction == "STAY" then
      local execution = runtimeState.fleeExecution
      local bestCandidate = nil
      if execution and request.reason == "GOAL_SATISFIED" then
        for _, candidate in ipairs(execution.localCandidates or {}) do
          if candidate.staticLegal and not candidate.occupied and not candidate.rejected
            and (candidate.threatDelta or 0) > 0
            and (not bestCandidate or candidate.threatDelta > bestCandidate.threatDelta
              or candidate.threatDelta == bestCandidate.threatDelta
              and candidate.direction < bestCandidate.direction) then
            bestCandidate = candidate
          end
        end
      end
      if bestCandidate then
        request.direction = bestCandidate.direction
        request.traversalMode = "WALK"
        request.sourceX = decisionContext.position.cellX
        request.sourceY = decisionContext.position.cellY
        request.destinationX = bestCandidate.destination.cellX
        request.destinationY = bestCandidate.destination.cellY
        request.reason = nil
        request.fleeRecoveryOverride = "LOCAL_SAFETY_IMPROVEMENT"
      end
      local reason = request.reason or request.rejectionReason
      if request.direction == "STAY" and not reason then
        reason = not goal and "NO_THREAT_POSITION"
          or SpatialGoal.isSatisfied(goal, decisionContext.position)
          and "GOAL_SATISFIED"
          or runtimeState.fleeExecution
          and runtimeState.fleeExecution.planningState == "PLAN_BLOCKED_UNCHANGED"
          and "NO_ESCAPE_ROUTE"
          or "NO_LEGAL_ESCAPE_DIRECTION"
        request.reason = reason
      end
      runtimeState.fleeStallReason = reason
      request.fleeTrace = {
        actorX = decisionContext.position and decisionContext.position.cellX,
        actorY = decisionContext.position and decisionContext.position.cellY,
        threatId = assessedThreatId,
        threatX = goal and goal.targetPosition and goal.targetPosition.cellX,
        threatY = goal and goal.targetPosition and goal.targetPosition.cellY,
        endpointX = runtimeState.fleeExecution
          and runtimeState.fleeExecution.escapeEndpoint
          and runtimeState.fleeExecution.escapeEndpoint.cellX,
        endpointY = runtimeState.fleeExecution
          and runtimeState.fleeExecution.escapeEndpoint
          and runtimeState.fleeExecution.escapeEndpoint.cellY,
        reason = reason
      }
    end
  end
  return runtimeState.state, runtimeState.selectedScore
end

function Controller.scoreBehaviors(entity, playerRelationship, context)
  return Utility.scoreBehaviors(entity, playerRelationship, context)
end

function Controller.tick(entity, playerRelationship, distance, context, nowTick)
  local state, behaviorScore = Controller.chooseState(entity, playerRelationship, distance, context, nowTick)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.state = state
  entity.runtimeState.fleeScore = Utility.scoreFlee(playerRelationship)
  entity.runtimeState.simulationTick = nowTick or entity.runtimeState.simulationTick
  entity.runtimeState.deliberationPerformed = true
  entity.runtimeState.executionUpdated = true
  entity.runtimeState.executionUpdateReason = "POST_DELIBERATION"

  local handler = STATE_HANDLERS[state] or Idle
  handler.tick(entity)
  return state, behaviorScore
end

function Controller.executeCurrentIntent(entity, context, nowTick)
  entity.runtimeState = entity.runtimeState or { state = "IDLE" }
  local executionContext = context or {}
  executionContext.executionOnly = true
  local state, behaviorScore = Controller.chooseState(entity, nil, nil, executionContext, nowTick)
  entity.runtimeState.state = state
  entity.runtimeState.simulationTick = nowTick or entity.runtimeState.simulationTick
  entity.runtimeState.deliberationPerformed = false
  entity.runtimeState.executionUpdated = true
  entity.runtimeState.executionUpdateReason = executionContext.executionUpdateReason or "CURRENT_INTENT"
  local handler = STATE_HANDLERS[state] or Idle
  handler.tick(entity)
  return state, behaviorScore
end

return Controller
