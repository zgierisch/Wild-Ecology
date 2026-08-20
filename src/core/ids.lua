local Ids = {}

function Ids.makeWildId(routeId, index)
  return string.format("wild:%s:%04d", routeId, index)
end

return Ids
