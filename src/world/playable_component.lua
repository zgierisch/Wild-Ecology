local WorldSemantics = require("src.world.world_semantics")

local PlayableComponent = {}

local cache = setmetatable({}, { __mode = "k" })
local buildCount = 0
local DIRECTIONS = {
  { dx = 0, dy = -1 },
  { dx = -1, dy = 0 },
  { dx = 1, dy = 0 },
  { dx = 0, dy = 1 }
}

local function key(x, y)
  return WorldSemantics.cellKey(x, y)
end

local function structurallyConnected(semantics, fromX, fromY, toX, toY)
  if not WorldSemantics.isLandingAllowed(semantics, fromX, fromY, "WALK")
    or not WorldSemantics.isLandingAllowed(semantics, toX, toY, "WALK") then
    return false
  end
  return WorldSemantics.isEdgeAllowed(semantics, fromX, fromY, toX, toY, "WALK")
    or WorldSemantics.isEdgeAllowed(semantics, toX, toY, fromX, fromY, "WALK")
end

local function build(semantics)
  buildCount = buildCount + 1
  local componentByCell = {}
  local componentSizes = {}
  local exitConnected = {}
  local componentCount = 0

  for y = 0, (semantics.height or 0) - 1 do
    for x = 0, (semantics.width or 0) - 1 do
      local startKey = key(x, y)
      if not componentByCell[startKey]
        and WorldSemantics.isLandingAllowed(semantics, x, y, "WALK") then
        componentCount = componentCount + 1
        local queue = { { cellX = x, cellY = y } }
        local head = 1
        componentByCell[startKey] = componentCount
        componentSizes[componentCount] = 0
        while head <= #queue do
          local current = queue[head]
          head = head + 1
          componentSizes[componentCount] = componentSizes[componentCount] + 1
          local transition = WorldSemantics.transitionAt(
            semantics, current.cellX, current.cellY
          )
          if transition and transition.kind == "OVERWORLD_EXIT" then
            exitConnected[componentCount] = true
          end
          for _, direction in ipairs(DIRECTIONS) do
            local nextX = current.cellX + direction.dx
            local nextY = current.cellY + direction.dy
            local nextKey = key(nextX, nextY)
            if not componentByCell[nextKey]
              and structurallyConnected(
                semantics, current.cellX, current.cellY, nextX, nextY
              ) then
              componentByCell[nextKey] = componentCount
              queue[#queue + 1] = { cellX = nextX, cellY = nextY }
            end
          end
        end
      end
    end
  end

  local exitConnectedComponentCount = 0
  for _ in pairs(exitConnected) do
    exitConnectedComponentCount = exitConnectedComponentCount + 1
  end
  local result = {
    componentByCell = componentByCell,
    componentSizes = componentSizes,
    exitConnected = exitConnected,
    componentCount = componentCount,
    exitConnectedComponentCount = exitConnectedComponentCount,
    buildNumber = buildCount
  }
  cache[semantics] = result
  return result
end

function PlayableComponent.currentPlayerCell(mod, mapId)
  local world = mod and mod.world
  if not world or type(world.current) ~= "function" then
    return nil, "PLAYER_POSITION_UNAVAILABLE"
  end
  local ok, current = pcall(world.current, world)
  if not ok or type(current) ~= "table" then
    return nil, "PLAYER_POSITION_UNAVAILABLE"
  elseif mapId and current.mapId and current.mapId ~= mapId then
    return nil, "PLAYER_MAP_MISMATCH"
  elseif type(current.x) ~= "number" or type(current.y) ~= "number" then
    return nil, "PLAYER_POSITION_UNAVAILABLE"
  end
  return { cellX = current.x, cellY = current.y }
end

local function outsideDirection(semantics, cell)
  local directions = {}
  if cell.cellY < 0 then directions[#directions + 1] = "north" end
  if cell.cellY >= semantics.height then directions[#directions + 1] = "south" end
  if cell.cellX < 0 then directions[#directions + 1] = "west" end
  if cell.cellX >= semantics.width then directions[#directions + 1] = "east" end
  if #directions ~= 1 then
    return nil, #directions > 1 and "OUTSIDE_MAP_MULTIPLE_BOUNDARIES"
      or "OUTSIDE_MAP_NO_CONNECTION"
  end
  return directions[1]
end

local function insideConnectionExtension(semantics, connection, direction, cell)
  if direction == "north" then
    return connection.destinationHeight ~= nil
      and cell.cellY >= -connection.destinationHeight
  elseif direction == "south" then
    return connection.destinationHeight ~= nil
      and cell.cellY < semantics.height + connection.destinationHeight
  elseif direction == "west" then
    return connection.destinationWidth ~= nil
      and cell.cellX >= -connection.destinationWidth
  end
  return connection.destinationWidth ~= nil
    and cell.cellX < semantics.width + connection.destinationWidth
end

local function projectedSource(semantics, direction, cell)
  if direction == "north" then
    return cell.cellX, 0
  elseif direction == "south" then
    return cell.cellX, semantics.height - 1
  elseif direction == "west" then
    return 0, cell.cellY
  end
  return semantics.width - 1, cell.cellY
end

local function resolveSeed(semantics, rawPlayerCell)
  if WorldSemantics.isInside(semantics, rawPlayerCell.cellX, rawPlayerCell.cellY) then
    if not WorldSemantics.isLandingAllowed(
      semantics, rawPlayerCell.cellX, rawPlayerCell.cellY, "WALK"
    ) then
      return nil, "PLAYER_IN_BOUNDS_NON_WALK"
    end
    return {
      cellX = rawPlayerCell.cellX,
      cellY = rawPlayerCell.cellY,
      source = "DIRECT"
    }
  end

  local direction, outsideReason = outsideDirection(semantics, rawPlayerCell)
  if not direction then
    return nil, outsideReason
  end
  local sourceX, sourceY = projectedSource(semantics, direction, rawPlayerCell)
  local directionFound = false
  local matches = {}
  for _, connection in ipairs(semantics.connections or {}) do
    if connection.direction == direction then
      directionFound = true
      if insideConnectionExtension(semantics, connection, direction, rawPlayerCell) then
        for _, source in ipairs(connection.usableSourceCells or {}) do
          if source.cellX == sourceX and source.cellY == sourceY then
            matches[#matches + 1] = {
              cellX = sourceX,
              cellY = sourceY,
              source = "MAP_CONNECTION",
              direction = string.upper(direction)
            }
          end
        end
      end
    end
  end
  local matchCount = #matches
  local match = matches[1]
  if matchCount > 1 then
    return nil, "AMBIGUOUS_CONNECTION"
  elseif matchCount == 0 then
    return nil, directionFound and "OUTSIDE_MAP_CONNECTION_MISMATCH"
      or "OUTSIDE_MAP_NO_CONNECTION"
  end
  return match
end

function PlayableComponent.inspect(mod, mapId, semantics)
  local rawPlayerCell, playerReason = PlayableComponent.currentPlayerCell(mod, mapId)
  if not semantics or not rawPlayerCell then
    return {
      status = "UNAVAILABLE",
      reason = playerReason or "PLAYER_POSITION_UNAVAILABLE",
      rawPlayerCell = rawPlayerCell,
      playerCell = rawPlayerCell,
      componentCount = semantics and (cache[semantics] or build(semantics)).componentCount or nil
    }
  end
  local components = cache[semantics] or build(semantics)
  local componentSeedCell, seedReason = resolveSeed(semantics, rawPlayerCell)
  if not componentSeedCell then
    return {
      status = "UNAVAILABLE",
      reason = seedReason,
      rawPlayerCell = rawPlayerCell,
      playerCell = rawPlayerCell,
      componentCount = components.componentCount,
      exitConnectedComponentCount = components.exitConnectedComponentCount,
      buildNumber = components.buildNumber
    }
  end
  local activeId = components.componentByCell[
    key(componentSeedCell.cellX, componentSeedCell.cellY)
  ]
  if not activeId then
    return {
      status = "UNAVAILABLE",
      reason = seedReason or "COMPONENT_SEED_NOT_WALKABLE",
      rawPlayerCell = rawPlayerCell,
      playerCell = rawPlayerCell,
      componentSeedCell = componentSeedCell,
      componentSeedSource = componentSeedCell and componentSeedCell.source or nil,
      componentSeedDirection = componentSeedCell and componentSeedCell.direction or nil,
      componentCount = components.componentCount,
      exitConnectedComponentCount = components.exitConnectedComponentCount,
      buildNumber = components.buildNumber
    }
  end
  return {
    status = "READY",
    reason = "READY",
    rawPlayerCell = rawPlayerCell,
    playerCell = rawPlayerCell,
    componentSeedCell = {
      cellX = componentSeedCell.cellX,
      cellY = componentSeedCell.cellY
    },
    componentSeedSource = componentSeedCell.source,
    componentSeedDirection = componentSeedCell.direction,
    activeComponentId = activeId,
    playableCells = components.componentSizes[activeId],
    componentCount = components.componentCount,
    exitConnected = components.exitConnected[activeId] == true,
    exitConnectedComponentCount = components.exitConnectedComponentCount,
    componentByCell = components.componentByCell,
    buildNumber = components.buildNumber
  }
end

function PlayableComponent.contains(component, x, y)
  return component ~= nil
    and component.status == "READY"
    and component.componentByCell[key(x, y)] == component.activeComponentId
end

function PlayableComponent.getBuildCount()
  return buildCount
end

return PlayableComponent