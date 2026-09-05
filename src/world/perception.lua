local Perception = {}

Perception.EVENTS = {
  ENTITY_SEEN = "ENTITY_SEEN",
  ENTITY_LOST = "ENTITY_LOST",
  ENTITY_APPROACHING = "ENTITY_APPROACHING",
  ENTITY_RETREATING = "ENTITY_RETREATING",
  ENTITY_NEAR = "ENTITY_NEAR",
  ENTITY_ATTACKED = "ENTITY_ATTACKED",
  ENTITY_FLED = "ENTITY_FLED",
  ENTITY_RESTING = "ENTITY_RESTING",
  ENTITY_FEEDING = "ENTITY_FEEDING",
  ENTITY_FOLLOWING = "ENTITY_FOLLOWING",
  ENTITY_IN_COMBAT = "ENTITY_IN_COMBAT"
}

local Memory = require("src.entities.memory")
local Relationships = require("src.entities.relationships")

local function eventTargetId(event)
  return event.targetEntityId or event.entityId or (event.target and event.target.id)
end

local function applyRelationshipEffect(entity, event, tick)
  local targetEntityId = eventTargetId(event)
  if not targetEntityId then
    return nil
  end

  local eventName = event.name or event.event
  return Relationships.applyPerceptionEvent(entity, targetEntityId, eventName, event, tick)
end

function Perception.observe(entity, observations, nowTick)
  local tick = nowTick or 0
  local observedEvents = {}
  local relationships = {}

  for _, observation in ipairs(observations or {}) do
    local event = observation
    if type(event) == "string" then
      event = { name = event }
    end
    if type(event) == "table" and (event.name or event.event) then
      local eventName = event.name or event.event
      local payload = {}
      for key, value in pairs(event) do
        if key ~= "target" then
          payload[key] = value
        end
      end
      payload.targetEntityId = eventTargetId(event)
      payload.tick = tick
      Memory.recordEvent(entity, eventName, payload)
      observedEvents[#observedEvents + 1] = payload
      local relationship = applyRelationshipEffect(entity, payload, tick)
      if relationship then
        relationships[eventTargetId(payload)] = relationship
      end
    end
  end

  return {
    events = observedEvents,
    relationships = relationships
  }
end

return Perception
