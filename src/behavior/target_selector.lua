local Utility = require("src.behavior.utility")

local TargetSelector = {}

local function relationshipFor(entity, targetId)
  return entity and entity.relationships and entity.relationships[targetId] or {}
end

local function targetScore(entity, target, context)
  local distance = target.distance
  local relationship = relationshipFor(entity, target.id)
  local novelty = target.novelty or 0
  local curiosity = entity.temperament and entity.temperament.curiosity or 0
  local affinity = relationship.affinity or 0
  local trust = relationship.trust or 0

  if context.behavior == "APPROACH" then
    return affinity + trust * 0.5 - (distance or 0) + curiosity * 10
  end

  return novelty + curiosity * 10 - (distance or 0) * 0.25
end

function TargetSelector.choose(entity, candidates, context)
  local bestTarget = nil
  local bestScore = -math.huge

  for _, target in ipairs(candidates or {}) do
    if target and target.id and target.id ~= entity.id then
      local score = targetScore(entity, target, context or {})
      if score > bestScore or (score == bestScore and tostring(target.id) < tostring(bestTarget and bestTarget.id or "~")) then
        bestTarget = target
        bestScore = score
      end
    end
  end

  if not bestTarget then
    return nil, 0
  end

  return bestTarget, bestScore
end

function TargetSelector.buildContext(entity, candidates, behavior)
  local target, score = TargetSelector.choose(entity, candidates, { behavior = behavior })
  return {
    hasTarget = target ~= nil,
    targetEntityId = target and target.id or nil,
    targetScore = score,
    target = target
  }
end

return TargetSelector