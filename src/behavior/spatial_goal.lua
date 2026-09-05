local SpatialGoal = {}

function SpatialGoal.position(destination, options)
  local settings = options or {}
  return {
    kind = "POSITION",
    targetPosition = destination,
    destination = destination,
    radius = 0,
    minRange = 0,
    maxRange = 0,
    alignment = "ANY",
    objective = "TOWARD",
    allowOverlap = true,
    mapId = settings.mapId,
    traversalMode = settings.traversalMode or "WALK",
    source = settings.source
  }
end

function SpatialGoal.proximity(targetEntityId, targetPosition, radius, options)
  local settings = options or {}
  return {
    kind = "PROXIMITY",
    targetEntityId = targetEntityId,
    targetPosition = targetPosition,
    radius = radius or 1,
    minRange = settings.minRange or 0,
    maxRange = settings.maxRange or radius or 1,
    alignment = settings.alignment or "ANY",
    objective = settings.objective or "TOWARD",
    allowOverlap = settings.allowOverlap == true,
    mapId = settings.mapId,
    traversalMode = settings.traversalMode or "WALK",
    source = settings.source
  }
end

function SpatialGoal.signature(goal)
  if not goal then return "none" end
  local target = goal.targetPosition or {}
  return table.concat({
    tostring(goal.kind or ""),
    tostring(goal.source or ""),
    tostring(goal.targetEntityId or ""),
    tostring(goal.mapId or ""),
    tostring(goal.traversalMode or "WALK"),
    tostring(target.cellX or ""),
    tostring(target.cellY or ""),
    tostring(goal.radius or ""),
    tostring(goal.minRange or ""),
    tostring(goal.maxRange or ""),
    tostring(goal.alignment or "ANY"),
    tostring(goal.objective or "TOWARD"),
    tostring(goal.allowOverlap == true)
  }, ":")
end

function SpatialGoal.resolve(targetEntityId, targetPositions, radius, options)
  local targetPosition = targetPositions and targetPositions[targetEntityId]
  if not targetPosition then
    return nil
  end

  return SpatialGoal.proximity(targetEntityId, {
    cellX = targetPosition.cellX,
    cellY = targetPosition.cellY
  }, radius, options)
end

function SpatialGoal.isSatisfied(goal, position)
  if not goal or not goal.targetPosition or not position then
    return false
  end

  local dx = math.abs(position.cellX - goal.targetPosition.cellX)
  local dy = math.abs(position.cellY - goal.targetPosition.cellY)
  local distance = math.max(dx, dy)
  if goal.objective == "AWAY" then
    return distance >= goal.radius
  end

  if dx == 0 and dy == 0 and not goal.allowOverlap then
    return false
  end

  if goal.alignment == "CARDINAL" then
    return (dx == 0 and dy <= goal.radius)
      or (dy == 0 and dx <= goal.radius)
  end

  return distance <= goal.radius
end

return SpatialGoal