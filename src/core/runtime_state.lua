local RuntimeState = {}

function RuntimeState.reset(entity)
  if type(entity) ~= "table" then
    return nil
  end

  entity.runtimeState = {
    motion = {
      active = false
    },
    movementRequest = nil,
    rejectedMoves = {},
    movementApi = nil,
    lastMovementSignature = nil
  }

  return entity.runtimeState
end

return RuntimeState
