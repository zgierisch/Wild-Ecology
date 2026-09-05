local WorldSemantics = require("src.world.world_semantics")

local NavigationEpisode = {}

function NavigationEpisode.rejectionMatches(record, position, mapId)
  if record == true then return true end
  return type(record) == "table"
    and (record.mapId == nil or record.mapId == mapId)
    and (record.cellX == nil or record.cellX == position.cellX)
    and (record.cellY == nil or record.cellY == position.cellY)
end

function NavigationEpisode.staticEdgeFromRequest(request)
  if not request or request.sourceX == nil or request.sourceY == nil
    or request.destinationX == nil or request.destinationY == nil then
    return nil
  end
  return WorldSemantics.edgeKey(
    request.sourceX, request.sourceY,
    request.destinationX, request.destinationY)
end

function NavigationEpisode.advanceRoute(route)
  if not route then return false end
  route.index = (route.index or 1) + 1
  return route.index > #route.actions
end

function NavigationEpisode.currentAction(route)
  return route and route.actions[route.index or 1] or nil
end

function NavigationEpisode.sourceMatches(action, position)
  return action ~= nil and action.source ~= nil and position ~= nil
    and action.source.cellX == position.cellX
    and action.source.cellY == position.cellY
end

function NavigationEpisode.requestForAction(action, route, details)
  local settings = details or {}
  return {
    direction = action.direction,
    traversalMode = action.mode,
    targetEntityId = settings.targetEntityId,
    goalKind = settings.goalKind,
    sourceX = action.source.cellX,
    sourceY = action.source.cellY,
    destinationX = action.destination.cellX,
    destinationY = action.destination.cellY,
    routeLength = route and #route.actions or 0,
    routeIndex = route and route.index or nil,
    waypoint = settings.waypoint,
    issuedTick = settings.tick
  }
end

return NavigationEpisode