local EscapeHeading = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function normalize(vector)
  local dx = vector and vector.dx or 0
  local dy = vector and vector.dy or 0
  local magnitude = math.sqrt(dx * dx + dy * dy)
  if magnitude <= 0 then return { dx = 0, dy = 0 } end
  return { dx = dx / magnitude, dy = dy / magnitude }
end

local function stableSign(entity)
  local hash = math.abs(math.floor(entity and entity.personalitySeed or 0))
  local identity = tostring(entity and entity.id or "")
  for index = 1, #identity do
    hash = (hash * 131 + identity:byte(index)) % 2147483647
  end
  return hash % 2 == 0 and 1 or -1
end

local function separationVector(position, neighbors)
  local dx, dy = 0, 0
  for _, record in ipairs(neighbors or {}) do
    local other = record.entity or record
    local otherPosition = record.position
    if otherPosition and other and other.runtimeState and other.runtimeState.state == "FLEE" then
      local offsetX = position.cellX - otherPosition.cellX
      local offsetY = position.cellY - otherPosition.cellY
      local distanceSquared = math.max(1, offsetX * offsetX + offsetY * offsetY)
      dx = dx + offsetX / distanceSquared
      dy = dy + offsetY / distanceSquared
    end
  end
  return normalize({ dx = dx, dy = dy })
end

local DIRECTIONS = {
  { dx = 0, dy = -1 },
  { dx = 0, dy = 1 },
  { dx = -1, dy = 0 },
  { dx = 1, dy = 0 }
}

local function walkable(isWalkable, from, destination)
  return isWalkable and isWalkable(from, destination) == true
end

local function openSpaceVector(isWalkable, position)
  if not isWalkable then return { dx = 0, dy = 0 } end
  local dx, dy = 0, 0
  for _, direction in ipairs(DIRECTIONS) do
    local destination = {
      cellX = position.cellX + direction.dx,
      cellY = position.cellY + direction.dy
    }
    if walkable(isWalkable, position, destination) then
      local onward = 0
      for _, nextDirection in ipairs(DIRECTIONS) do
        local nextCell = {
          cellX = destination.cellX + nextDirection.dx,
          cellY = destination.cellY + nextDirection.dy
        }
        if walkable(isWalkable, destination, nextCell) then onward = onward + 1 end
      end
      dx = dx + direction.dx * onward
      dy = dy + direction.dy * onward
    end
  end
  return normalize({ dx = dx, dy = dy })
end

local function consumeResidual(residualX, residualY, direction)
  if direction == "RIGHT" then residualX = residualX - 1
  elseif direction == "LEFT" then residualX = residualX + 1
  elseif direction == "DOWN" then residualY = residualY - 1
  elseif direction == "UP" then residualY = residualY + 1 end
  return residualX, residualY
end

function EscapeHeading.update(entity, position, threatPosition, context, simulationTick)
  entity.runtimeState = entity.runtimeState or {}
  local runtime = entity.runtimeState
  local settings = context or {}
  local radial = normalize({
    dx = position.cellX - threatPosition.cellX,
    dy = position.cellY - threatPosition.cellY
  })
  if radial.dx == 0 and radial.dy == 0 and settings.socialAlignment then
    radial = normalize(settings.socialAlignment)
  end

  local independence = entity.rawStats and entity.rawStats.independence or 0.5
  local sociality = entity.temperament and entity.temperament.sociability or 0.5
  local fear = clamp(runtime.fearCurrent or 0, 0, 1)
  local recovery = clamp(settings.recoveryProgress or 0, 0, 1)
  local threatConfidence = clamp(settings.threatPositionConfidence == nil
    and 1 or settings.threatPositionConfidence, 0, 1)
  local radialWeight = (0.7 + fear * 0.5) * (0.3 + threatConfidence * 0.7)
    * (1 - recovery * 0.4)
  local lateralMagnitude = (0.12 + clamp(independence, 0, 1) * 0.3)
    * (1 - clamp(sociality, 0, 1) * 0.25)
  local lateralSign = stableSign(entity)
  local lateral = {
    dx = -radial.dy * lateralSign * lateralMagnitude,
    dy = radial.dx * lateralSign * lateralMagnitude
  }
  local observedSeparation = separationVector(position, settings.neighbors)
  local previousSeparation = runtime.escapeSeparationMomentum or { dx = 0, dy = 0 }
  local separation = normalize({
    dx = previousSeparation.dx * 0.7 + observedSeparation.dx,
    dy = previousSeparation.dy * 0.7 + observedSeparation.dy
  })
  runtime.escapeSeparationMomentum = {
    dx = previousSeparation.dx * 0.7 + observedSeparation.dx,
    dy = previousSeparation.dy * 0.7 + observedSeparation.dy
  }
  local separationWeight = (0.2 + independence * 0.1) * (0.8 + recovery * 0.4)
  local openSpace = normalize(settings.openSpace or openSpaceVector(settings.isWalkable, position))
  local openSpaceWeight = 0.04 + recovery * 0.28 + (1 - fear) * 0.1
  local social = normalize(settings.socialAlignment)
  local socialWeight = (1 - independence) * sociality * 0.18 * (0.45 + recovery * 0.55)
  local lateralWeight = lateralMagnitude * (0.8 + recovery * 0.35)
  local desired = normalize({
    dx = radial.dx * radialWeight + lateral.dx * lateralWeight / lateralMagnitude
      + separation.dx * separationWeight + openSpace.dx * openSpaceWeight + social.dx * socialWeight,
    dy = radial.dy * radialWeight + lateral.dy * lateralWeight / lateralMagnitude
      + separation.dy * separationWeight + openSpace.dy * openSpaceWeight + social.dy * socialWeight
  })

  local previous = runtime.escapeHeading
  if previous then
    local inertia = 0.82 - recovery * 0.3
    desired = normalize({
      dx = previous.dx * inertia + desired.dx * (1 - inertia),
      dy = previous.dy * inertia + desired.dy * (1 - inertia)
    })
  end
  local minimumRadialAlignment = 0.25 + threatConfidence * (1 - recovery) * 0.3
  if desired.dx * radial.dx + desired.dy * radial.dy < minimumRadialAlignment then
    desired = normalize({
      dx = radial.dx * minimumRadialAlignment + desired.dx,
      dy = radial.dy * minimumRadialAlignment + desired.dy
    })
  end

  local residualX = previous and previous.residualX or 0
  local residualY = previous and previous.residualY or 0
  local advanceResidual = previous == nil or settings.completedDirection ~= nil
  if settings.completedDirection then
    residualX, residualY = consumeResidual(residualX, residualY, settings.completedDirection)
  end
  if advanceResidual then
    residualX = residualX + desired.dx
    residualY = residualY + desired.dy
  end

  runtime.escapeHeading = {
    dx = desired.dx,
    dy = desired.dy,
    radialX = radial.dx,
    radialY = radial.dy,
    individualLateralBias = lateralSign * lateralMagnitude,
    radialWeight = radialWeight,
    lateralWeight = lateralWeight,
    separationWeight = separationWeight,
    openSpaceWeight = openSpaceWeight,
    socialAlignmentWeight = socialWeight,
    threatPositionConfidence = threatConfidence,
    recoveryProgress = recovery,
    residualX = residualX,
    residualY = residualY,
    separationX = separation.dx * separationWeight,
    separationY = separation.dy * separationWeight,
    openSpaceX = openSpace.dx * openSpaceWeight,
    openSpaceY = openSpace.dy * openSpaceWeight,
    socialAlignmentX = social.dx * socialWeight,
    socialAlignmentY = social.dy * socialWeight,
    establishedTick = previous and previous.establishedTick or simulationTick,
    age = previous and math.max(0, (simulationTick or 0) - (previous.establishedTick or simulationTick)) or 0
  }
  return runtime.escapeHeading
end

return EscapeHeading
