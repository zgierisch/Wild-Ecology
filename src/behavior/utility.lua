local Utility = {}

function Utility.scoreFlee(rel)
  return (rel and rel.threatMemory or 0) + (rel and rel.hostility or 0)
end

return Utility
