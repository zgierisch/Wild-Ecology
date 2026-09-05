local BoundedSearch = {}

local function copyEdge(edge)
  local child = {}
  for key, value in pairs(edge or {}) do child[key] = value end
  return child
end

function BoundedSearch.run(options)
  local settings = options or {}
  if not settings.start or type(settings.key) ~= "function"
    or type(settings.neighbors) ~= "function" then
    return nil, 0
  end

  local maxDepth = settings.maxDepth or 10
  local maxExpansions = settings.maxExpansions or 128
  local root = {
    position = {
      cellX = settings.start.cellX,
      cellY = settings.start.cellY
    },
    depth = 0
  }
  local queue = { root }
  local head = 1
  local visited = { [settings.key(root.position)] = true }
  local best = settings.includeStart and root or nil
  local expansions = 0

  while head <= #queue and expansions < maxExpansions do
    local node = queue[head]
    head = head + 1
    expansions = expansions + 1

    local candidate
    if settings.evaluate then
      candidate = settings.evaluate(node)
    else
      candidate = node
    end
    if candidate and (best == nil or settings.better == nil
      or settings.better(candidate, best)) then
      best = candidate
    end
    if settings.stop and settings.stop(node, candidate, best) then break end

    if node.depth < maxDepth then
      for _, edge in ipairs(settings.neighbors(node) or {}) do
        local destination = edge.position
        local destinationKey = destination and settings.key(destination) or nil
        if destinationKey and not visited[destinationKey] then
          visited[destinationKey] = true
          local child = copyEdge(edge)
          child.position = {
            cellX = destination.cellX,
            cellY = destination.cellY
          }
          child.depth = node.depth + 1
          child.parent = node
          queue[#queue + 1] = child
        end
      end
    end
  end

  return best, expansions
end

function BoundedSearch.reconstruct(node)
  local actions = {}
  while node and node.action do
    table.insert(actions, 1, node.action)
    node = node.parent
  end
  return actions
end

return BoundedSearch