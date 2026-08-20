local Entity = require("src.entities.entity")

local Generator = {}

function Generator.makePhase0Pidgey(id)
  return Entity.newWildPokemon({
    id = id,
    species = "PIDGEY",
    level = 4,
    personalitySeed = 847219,
    home = {
      mapId = "ROUTE_1",
      zoneId = "south_grass"
    }
  })
end

return Generator
