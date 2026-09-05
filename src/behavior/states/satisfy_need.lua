local SatisfyNeed = {}

function SatisfyNeed.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "SATISFY_NEED"
  return "SATISFY_NEED"
end

return SatisfyNeed