local NavigationGoal = {}

function NavigationGoal.fromFlockSearch(search)
  if not search then
    return { kind = "SEARCH", source = "search" }
  end
  if search.cueSource == "perceived" and search.cuePosition then
    return {
      kind = "PROXIMITY",
      source = "perceived",
      targetEntityId = search.targetEntityId,
      destination = { cellX = search.cuePosition.cellX, cellY = search.cuePosition.cellY }
    }
  end
  if search.cueSource == "last_seen" and search.cuePosition then
    return {
      kind = "POSITION",
      source = "last_seen",
      targetEntityId = search.targetEntityId,
      destination = { cellX = search.cuePosition.cellX, cellY = search.cuePosition.cellY }
    }
  end
  if search.cueSource == "social_signal" and search.cueDirection then
    return {
      kind = "DIRECTIONAL_REGION",
      source = "social_signal",
      targetEntityId = search.targetEntityId,
      direction = search.cueDirection
    }
  end
  return { kind = "SEARCH", source = "search" }
end

function NavigationGoal.signature(goal)
  if not goal then
    return "none"
  end
  if goal.kind == "POSITION" or goal.kind == "PROXIMITY" then
    return table.concat({ goal.kind, goal.source or "", goal.targetEntityId or "", goal.destination.cellX, goal.destination.cellY }, ":")
  end
  return table.concat({ goal.kind or "", goal.source or "", goal.targetEntityId or "", goal.direction or "" }, ":")
end

return NavigationGoal