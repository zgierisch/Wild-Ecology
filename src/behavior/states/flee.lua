local Flee = {}

function Flee.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "FLEE"
  return "FLEE"
end

return Flee
