local Settled = {}

function Settled.tick(entity)
  local runtime = entity.runtimeState or {}
  entity.runtimeState = runtime
  runtime.intent = "SETTLED"
  runtime.targetEntityId = nil
  runtime.targetDestination = nil
  runtime.spatialGoal = nil
  runtime.navigation = nil
  runtime.movementRequest = nil
  return "SETTLED"
end

return Settled