local WorldSemantics = require("src.world.world_semantics")

local WorldTopology = {}

local OUTWARD_DIRECTION = {
  UP = "north",
  DOWN = "south",
  LEFT = "west",
  RIGHT = "east"
}

local function movementDirection(source, destination)
  if destination.cellX < source.cellX then return "LEFT" end
  if destination.cellX > source.cellX then return "RIGHT" end
  if destination.cellY < source.cellY then return "UP" end
  if destination.cellY > source.cellY then return "DOWN" end
  return nil
end

function WorldTopology.classifyTransition(semantics, source, destination)
  if not semantics or not source or not destination then
    return { status = "UNKNOWN", executable = false }
  end
  if WorldSemantics.isInside(semantics, destination.cellX, destination.cellY) then
    return { status = "SAME_MAP", executable = true }
  end

  local transition = WorldSemantics.transitionAt(
    semantics, source.cellX, source.cellY)
  local direction = OUTWARD_DIRECTION[movementDirection(source, destination)]
  if transition and transition.topologyKind == "CONNECTION"
    and transition.direction == direction then
    return {
      status = "KNOWN_VALID_CONNECTION",
      executable = false,
      executionStatus = "KNOWN_CONNECTION_BUT_NOT_EXECUTABLE",
      sourceMapId = semantics.mapId,
      source = { cellX = source.cellX, cellY = source.cellY },
      direction = transition.direction,
      destinationMapId = transition.destinationMapId,
      destination = transition.destinationX ~= nil and {
        cellX = transition.destinationX,
        cellY = transition.destinationY
      } or nil
    }
  end
  return {
    status = "HARD_BOUNDARY",
    executable = false,
    sourceMapId = semantics.mapId,
    source = { cellX = source.cellX, cellY = source.cellY }
  }
end

function WorldTopology.transitionsTo(semantics, destinationMapId)
  local results = {}
  for _, connection in ipairs(semantics and semantics.connections or {}) do
    if destinationMapId == nil or connection.destinationMapId == destinationMapId then
      for _, source in ipairs(connection.usableSourceCells or {}) do
        results[#results + 1] = {
          status = "KNOWN_VALID_CONNECTION",
          executable = false,
          executionStatus = "KNOWN_CONNECTION_BUT_NOT_EXECUTABLE",
          sourceMapId = semantics.mapId,
          source = { cellX = source.cellX, cellY = source.cellY },
          direction = connection.direction,
          destinationMapId = connection.destinationMapId,
          destination = source.destinationX ~= nil and {
            cellX = source.destinationX,
            cellY = source.destinationY
          } or nil
        }
      end
    end
  end
  table.sort(results, function(left, right)
    if left.direction ~= right.direction then return left.direction < right.direction end
    if left.source.cellY ~= right.source.cellY then
      return left.source.cellY < right.source.cellY
    end
    return left.source.cellX < right.source.cellX
  end)
  return results
end

return WorldTopology