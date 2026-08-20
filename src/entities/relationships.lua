local Relationships = {}

local function clamp(value, minV, maxV)
  if value < minV then
    return minV
  end
  if value > maxV then
    return maxV
  end
  return value
end

function Relationships.getOrCreate(entity, targetEntityId)
  entity.relationships = entity.relationships or {}

  if not entity.relationships[targetEntityId] then
    entity.relationships[targetEntityId] = {
      familiarity = 0,
      trust = 0,
      affinity = 0,
      threatMemory = 0,
      hostility = 0,
      lastSeenTick = 0,
      importance = 0.1
    }
  end

  return entity.relationships[targetEntityId]
end

function Relationships.observeCalmProximity(entity, targetEntityId)
  local rel = Relationships.getOrCreate(entity, targetEntityId)
  rel.familiarity = clamp(rel.familiarity + 1, 0, 100)
  rel.trust = clamp(rel.trust + 1, 0, 100)
  rel.lastSeenTick = rel.lastSeenTick + 1
  return rel
end

return Relationships
