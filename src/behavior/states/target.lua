local Target = {}

function Target.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "TARGET"
  return "TARGET"
end

return Target
