local ReturnHome = {}

function ReturnHome.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "RETURN_HOME"
  return "RETURN_HOME"
end

return ReturnHome