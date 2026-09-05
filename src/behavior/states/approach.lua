local Approach = {}

function Approach.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "APPROACH"
  return "APPROACH"
end

return Approach