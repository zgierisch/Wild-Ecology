local Investigate = {}

function Investigate.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "INVESTIGATE"
  return "INVESTIGATE"
end

return Investigate