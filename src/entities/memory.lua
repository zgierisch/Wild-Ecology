local Memory = {}

function Memory.recordEvent(entity, eventName, payload)
  entity.memory = entity.memory or {}
  table.insert(entity.memory, {
    event = eventName,
    payload = payload,
    t = os.time()
  })

  if #entity.memory > 50 then
    table.remove(entity.memory, 1)
  end
end

return Memory
