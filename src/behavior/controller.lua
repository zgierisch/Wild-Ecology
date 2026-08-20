local Controller = {}

function Controller.tick(entity)
  entity.runtimeState = entity.runtimeState or { state = "IDLE" }
  return entity.runtimeState.state
end

return Controller
