local WorldSemantics = require("src.world.world_semantics")
local TraversalCapabilities = require("src.navigation.traversal_capabilities")

local TraversalEvaluator = {}

local SPECIAL_EDGE_MODES = { "FLY", "CLIMB", "SQUEEZE", "JUMP", "BURROW" }

local function capabilityEnabled(capabilities, mode)
  local capability = capabilities and capabilities[mode]
  return capability == true or type(capability) == "table" and capability.enabled ~= false
end

local function modeAllowed(mode, allowedModes)
  return allowedModes == nil or allowedModes[mode] == true
end

function TraversalEvaluator.evaluateAdjacent(entity, semantics, source, destination, options)
  local settings = options or {}
  if not source or not destination
    or not WorldSemantics.isInside(semantics, source.cellX, source.cellY)
    or not WorldSemantics.isInside(semantics, destination.cellX, destination.cellY) then
    return { legal = false, reason = "SIMULATION_BOUNDARY" }
  end
  local capabilities = settings.capabilities or TraversalCapabilities.forEntity(entity)
  local cell = WorldSemantics.cellAt(semantics, destination.cellX, destination.cellY)
  local edge = WorldSemantics.edgeAt(semantics, source.cellX, source.cellY, destination.cellX, destination.cellY)

  if modeAllowed("WALK", settings.allowedModes)
    and capabilityEnabled(capabilities, "WALK")
    and WorldSemantics.isEdgeAllowed(semantics, source.cellX, source.cellY, destination.cellX, destination.cellY, "WALK")
    and WorldSemantics.isLandingAllowed(semantics, destination.cellX, destination.cellY, "WALK") then
    return { legal = true, mode = "WALK", cost = 1 }
  end
  if modeAllowed("SWIM", settings.allowedModes)
    and capabilityEnabled(capabilities, "SWIM")
    and WorldSemantics.isEdgeAllowed(semantics, source.cellX, source.cellY, destination.cellX, destination.cellY, "SWIM")
    and WorldSemantics.isLandingAllowed(semantics, destination.cellX, destination.cellY, "SWIM") then
    return { legal = true, mode = "SWIM", cost = cell.swimCost or 2 }
  end
  for _, mode in ipairs(SPECIAL_EDGE_MODES) do
    if edge and modeAllowed(mode, settings.allowedModes)
      and capabilityEnabled(capabilities, mode)
      and WorldSemantics.isEdgeAllowed(semantics, source.cellX, source.cellY, destination.cellX, destination.cellY, mode)
      and WorldSemantics.isLandingAllowed(semantics, destination.cellX, destination.cellY, mode) then
      return { legal = true, mode = mode, cost = edge.cost or 2 }
    end
  end
  return { legal = false, reason = cell.kind or "UNKNOWN_BARRIER" }
end

local function lineOfSightClear(semantics, source, destination)
  local steps = math.max(math.abs(destination.cellX - source.cellX), math.abs(destination.cellY - source.cellY))
  for step = 1, steps - 1 do
    local x = math.floor(source.cellX + (destination.cellX - source.cellX) * step / steps + 0.5)
    local y = math.floor(source.cellY + (destination.cellY - source.cellY) * step / steps + 0.5)
    if WorldSemantics.blocksLineOfSight(semantics, x, y) then
      return false
    end
  end
  return true
end

function TraversalEvaluator.evaluateTeleport(entity, semantics, source, destination, options)
  local settings = options or {}
  local capabilities = settings.capabilities or TraversalCapabilities.forEntity(entity)
  local teleport = capabilities.TELEPORT
  if not modeAllowed("TELEPORT", settings.allowedModes) or not capabilityEnabled(capabilities, "TELEPORT") then
    return { legal = false, reason = "CAPABILITY_REQUIRED" }
  end
  if not source or not destination or not WorldSemantics.isInside(semantics, destination.cellX, destination.cellY) then
    return { legal = false, reason = "SIMULATION_BOUNDARY" }
  end
  local landing = WorldSemantics.cellAt(semantics, destination.cellX, destination.cellY)
  if landing.validLanding ~= true then
    return { legal = false, reason = "INVALID_LANDING" }
  end
  local distance = math.max(math.abs(destination.cellX - source.cellX), math.abs(destination.cellY - source.cellY))
  local maxRange = type(teleport) == "table" and teleport.maxRange or 4
  if distance == 0 or distance > maxRange then
    return { legal = false, reason = "OUT_OF_RANGE" }
  end
  if type(teleport) == "table" and teleport.requiresLineOfSight == true
    and not lineOfSightClear(semantics, source, destination) then
    return { legal = false, reason = "LINE_OF_SIGHT_BLOCKED" }
  end
  return { legal = true, mode = "TELEPORT", cost = type(teleport) == "table" and teleport.cost or 3 }
end

return TraversalEvaluator