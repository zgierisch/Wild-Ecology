local Rest = {}

function Rest.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "REST"
  if entity.runtimeState.restTraveling ~= true then
    entity.runtimeState.movementRequest = nil
  end
  return "REST"
end

return Rest