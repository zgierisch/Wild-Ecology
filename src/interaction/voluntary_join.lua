local Profiles = require("src.species.profiles")

local VoluntaryJoin = {}

function VoluntaryJoin.canJoin(entity, rel)
  local profile = Profiles[entity.species]
  if not profile or not profile.join or not rel then
    return false
  end

  local rule = profile.join
  return rel.familiarity >= rule.familiarity
    and rel.trust >= rule.trust
    and rel.affinity >= rule.affinity
    and rel.threatMemory <= rule.maxThreat
end

return VoluntaryJoin
