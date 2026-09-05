local Idle = {}

function Idle.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "IDLE"
  return "IDLE"
end

return Idle
