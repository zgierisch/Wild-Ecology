local SeekFlock = {}

function SeekFlock.tick(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.intent = "SEEK_FLOCK"
  return "SEEK_FLOCK"
end

return SeekFlock