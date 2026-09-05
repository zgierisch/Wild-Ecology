local Utility = {}
local behaviorScoreRuns = 0

function Utility.getBehaviorScoreRunCount()
  return behaviorScoreRuns
end

local function clamp(value, minV, maxV)
  if value < minV then
    return minV
  end
  if value > maxV then
    return maxV
  end
  return value
end

function Utility.scoreFlee(rel)
  return (rel and rel.threatMemory or 0) + (rel and rel.hostility or 0)
end

-- Being right next to something is unsettling on its own, independent of
-- accumulated threat memory: low trust and low boldness make that discomfort
-- worse, high trust/boldness let it be tolerated. Only near range (<=2)
-- counts as "too close" so ordinary mid/far proximity never contributes.
-- Conspecifics (same species) don't read closeness as awkward the way an
-- unfamiliar player does, so their fear scales down sharply.
function Utility.proximityFear(rel, distance, temperament, conspecific)
  if distance == nil or distance > 2 then
    return 0
  end
  local trust = rel and rel.trust or 0
  local boldness = (temperament and temperament.boldness) or 0
  local wariness = clamp(1 - (trust / 100) - (boldness * 0.5), 0, 1)
  local closeness = 3 - distance
  local magnitude = conspecific and 3 or 15
  return wariness * closeness * magnitude
end

function Utility.scoreBehaviors(entity, relationship, context)
  behaviorScoreRuns = behaviorScoreRuns + 1
  local temperament = entity and entity.temperament or {}
  local rel = relationship or {}
  local situation = context or {}
  local transientFear = clamp(situation.currentFear or 0, 0, 1)
  local proximityFear = Utility.proximityFear(rel, situation.distance, temperament, situation.conspecific)
  local perceivedFear = (situation.perceivedFear or 0) + proximityFear
  local fleePerceivedFear = (situation.perceivedFear or 0)
    + (situation.activeThreat == true and proximityFear or 0)
  -- Unfamiliar targets are novel by default; repeated calm exposure raises
  -- familiarity and lets investigation fade organically instead of being
  -- driven almost entirely by a flat curiosity constant. It also fades the
  -- longer the same target has been stared at this encounter, so attention
  -- naturally moves on instead of freezing on the first neighbor forever.
  local novelty = situation.novelty or clamp(100 - (rel.familiarity or 0), 0, 100)
  novelty = clamp(novelty - (situation.investigateElapsed or 0) * 6, 0, 100)
  -- Same restlessness idea as IDLE->TARGET: once an approach goal has
  -- actually been REACHED, trust/affinity alone would keep APPROACH
  -- winning forever (they don't decay), permanently parking the Pokemon
  -- next to its friend. Let time-spent-arrived erode the score instead.
  local approachSatisfiedElapsed = situation.approachSatisfiedElapsed or 0
  local driveNeed = situation.driveNeed or {}
  local driveSatisfaction = situation.driveSatisfaction or {}
  local curiosityNeed = clamp(driveNeed.curiosity or 1, 0, 1)
  local socialNeed = clamp(driveNeed.social or 1, 0, 1)
  local cohesionNeed = clamp(driveNeed.cohesion or 1, 0, 1)
  local explorationNeed = clamp(driveNeed.exploration or 1, 0, 1)
  local socialTargetSatisfied = situation.targetDistance ~= nil
    and situation.targetDistance <= (situation.goalRadius or 1)
  local separationPressure = situation.targetDistance ~= nil
    and clamp((situation.targetDistance - (situation.goalRadius or 1)) / 6, 0, 1)
    or 0
  socialNeed = math.max(socialNeed, separationPressure)
  local settledSatisfaction = math.max(
    driveSatisfaction.curiosity or 0,
    socialTargetSatisfied and (driveSatisfaction.social or 0) or 0,
    driveSatisfaction.cohesion or 0,
    driveSatisfaction.exploration or 0)
  local scores = {
    FLEE = Utility.scoreFlee(rel) + fleePerceivedFear + transientFear * 60,
    SEEK_FLOCK = (situation.seekFlockUtility or 0)
      * (situation.seekFlockSafetyFactor or 1) * cohesionNeed,
    ALERT = perceivedFear * 0.75,
    INVESTIGATE = (temperament.curiosity or 0)
      * (5 + novelty * 0.45) * curiosityNeed,
    APPROACH = socialTargetSatisfied and 0 or clamp(
      ((rel.trust or 0) * 0.35 + (rel.affinity or 0) * 0.25
        + (temperament.sociability or 0) * 10)
      * socialNeed - approachSatisfiedElapsed * 2, 0, 200),
    -- Ambient roaming requires positive restlessness. SETTLED is the calm
    -- equilibrium when no action has enough utility to disturb it.
    TARGET = situation.allowTargeting ~= false
      and clamp((situation.settledElapsed or 0) * 0.12 * explorationNeed
        - (situation.targetElapsed or 0) * 2, 0, 100)
      or 0,
    REST = clamp(math.max(0, (situation.fatigue or 0) - 0.25) * 65
      + (situation.fatigue or 0) * (situation.circadianRestBias or 0) * 28,
      0, 100),
    SATISFY_NEED = situation.needOpportunity
      and (situation.needOpportunity.score or 0) or 0,
    RETURN_HOME = situation.homeReturn
      and (situation.homeReturn.score or 0) or 0,
    IDLE = 10,
    SETTLED = 20 + settledSatisfaction * 8
  }

  if situation.approachReacquisitionSuppressed then
    scores.APPROACH = 0
  end
  if situation.recentPurposefulDwell then
    scores.TARGET = 0
  end

  if situation.hasTarget ~= true then
    scores.INVESTIGATE = 0
    scores.APPROACH = 0
  end
  -- purposefulTarget is opt-in: only zero scores when a caller explicitly
  -- marks the target as not-yet-relevant (e.g. player visible but far).
  -- Callers that don't reason about relevance keep the prior hasTarget-only
  -- contract.
  if situation.purposefulTarget == false then
    scores.INVESTIGATE = 0
    scores.APPROACH = 0
  end

  return scores
end

function Utility.highestBehavior(scores)
  local bestState = "SETTLED"
  local bestScore = -math.huge
  for state, score in pairs(scores or {}) do
    if score > bestScore or (score == bestScore and state == "SETTLED") then
      bestState = state
      bestScore = score
    end
  end
  return bestState, bestScore
end

function Utility.shouldChangeBehavior(currentState, candidateState, currentScore, candidateScore, nowTick, enteredTick, minimumDuration, hysteresis)
  if not currentState or currentState == candidateState then
    return true
  end

  if enteredTick == nil then
    return true
  end

  local elapsed = (nowTick or 0) - (enteredTick or 0)
  if elapsed < (minimumDuration or 0) then
    return false
  end

  return (candidateScore or 0) >= (currentScore or 0) + (hysteresis or 0)
end

function Utility.chebyshevDistance(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return nil
  end

  local ax = a.cellX or a.x or 0
  local ay = a.cellY or a.y or 0
  local bx = b.cellX or b.x or 0
  local by = b.cellY or b.y or 0
  local dx = math.abs(ax - bx)
  local dy = math.abs(ay - by)
  return math.max(dx, dy)
end

function Utility.distanceBand(distance)
  if distance == nil then
    return "near", 1.0
  end

  if distance <= 2 then
    return "near", 1.0
  end
  if distance <= 5 then
    return "mid", 0.35
  end
  if distance <= 8 then
    return "far", 0.1
  end
  return "out", 0.0
end

function Utility.weightedDelta(delta, distance)
  local _, multiplier = Utility.distanceBand(distance)
  return delta * multiplier, multiplier
end

function Utility.fleeRadius(rel)
  local trust = rel and rel.trust or 0
  local threatMemory = rel and rel.threatMemory or 0
  local hostility = rel and rel.hostility or 0

  local radius = 4
  radius = radius + math.floor(threatMemory / 25)
  radius = radius + (hostility > 0 and 1 or 0)
  radius = radius - math.floor(trust / 25)

  if radius < 1 then
    radius = 1
  elseif radius > 8 then
    radius = 8
  end

  return radius
end

function Utility.shouldFleeAtDistance(rel, distance, triggerRadius)
  local radius = triggerRadius or Utility.fleeRadius(rel)
  if distance == nil then
    return true, radius
  end

  return distance <= radius, radius
end

return Utility
