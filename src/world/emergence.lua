local WorldSemantics = require("src.world.world_semantics")

local Emergence = {}

local function candidateScore(semantics, cell, distance)
  local described = WorldSemantics.cellAt(semantics, cell.cellX, cell.cellY)
  local openBonus = described.terrain == "OPEN_GROUND" and 20 or 0
  return openBonus - distance * 4
end

function Emergence.selectCell(entity, semantics, occupiedCells, options)
  local location = entity and entity.locationState
  local anchor = location and location.anchorCell
  if not semantics or not anchor then return nil end
  local radius = math.max(0, math.min(2, options and options.radius or 1))
  local candidates = {}
  for cellY = math.max(0, anchor.cellY - radius),
    math.min((semantics.height or 1) - 1, anchor.cellY + radius) do
    for cellX = math.max(0, anchor.cellX - radius),
      math.min((semantics.width or 1) - 1, anchor.cellX + radius) do
      local distance = math.max(math.abs(cellX - anchor.cellX),
        math.abs(cellY - anchor.cellY))
      local key = WorldSemantics.cellKey(cellX, cellY)
      local transition = WorldSemantics.transitionAt(semantics, cellX, cellY)
      local edgeLegal = distance == 0 or distance == 1
        and WorldSemantics.isEdgeAllowed(semantics,
          anchor.cellX, anchor.cellY, cellX, cellY, "WALK")
      if distance <= radius and edgeLegal and transition == nil
        and WorldSemantics.isLandingAllowed(semantics, cellX, cellY, "WALK")
        and not (occupiedCells and occupiedCells[key]) then
        candidates[#candidates + 1] = {
          cellX = cellX,
          cellY = cellY,
          distance = distance,
          score = candidateScore(semantics,
            { cellX = cellX, cellY = cellY }, distance)
        }
      end
    end
  end
  table.sort(candidates, function(left, right)
    if left.score ~= right.score then return left.score > right.score end
    if left.distance ~= right.distance then return left.distance < right.distance end
    if left.cellY ~= right.cellY then return left.cellY < right.cellY end
    return left.cellX < right.cellX
  end)
  return candidates[1]
end

return Emergence