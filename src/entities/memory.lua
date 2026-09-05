local Memory = {}

function Memory.recordEvent(entity, eventName, payload)
  entity.memory = entity.memory or {}
  entity.memory.events = entity.memory.events or {}
  table.insert(entity.memory.events, {
    event = eventName,
    payload = payload,
    t = payload and payload.tick or os.time()
  })

  if #entity.memory.events > 50 then
    table.remove(entity.memory.events, 1)
  end
end

return Memory
