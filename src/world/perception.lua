local Perception = {}

function Perception.observe(_entity, _nearbyEntities)
  return {
    notice = {},
    calmProximity = {}
  }
end

return Perception
