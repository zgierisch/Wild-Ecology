local Entity = require("src.entities.entity")
local PopulationManager = require("src.population.manager")
local Relationships = require("src.entities.relationships")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function pokemon(id, seed)
  return Entity.newWildPokemon({
    id = id,
    species = "PIDGEY",
    level = 5,
    personalitySeed = seed,
    home = { mapId = "ROUTE_TEST", zoneId = "test", spawnX = seed, spawnY = 1 }
  })
end

local player = { id = "player", kind = "trainer" }
local population = {}
local zeroValuedCreations = 0
Relationships.setMutationSink(function(mutation)
  if mutation.event == "CALM_PROXIMITY" and mutation.created then
    local relationship = mutation.relationship or {}
    if (relationship.familiarity or 0) == 0
      and (relationship.trust or 0) == 0
      and (relationship.affinity or 0) == 0
      and (relationship.threatMemory or 0) == 0
      and (relationship.directThreatMemory or 0) == 0
      and (relationship.hostility or 0) == 0 then
      zeroValuedCreations = zeroValuedCreations + 1
    end
  end
end)

for index = 1, 20 do
  local entity = pokemon("wild:calm-sparse:" .. index, index)
  population[index] = entity
  PopulationManager.updatePhase0Relationship(entity, player, 1, 9)
end

local persistentPlayerRelationships = 0
for _, entity in ipairs(population) do
  if entity.relationships[player.id] then
    persistentPlayerRelationships = persistentPlayerRelationships + 1
  end
end
assertEquals(persistentPlayerRelationships, 0,
  "out-of-range calm observation must not allocate player relationships")
assertEquals(zeroValuedCreations, 0,
  "out-of-range calm observation must not journal zero-valued creation")

local existingEntity = pokemon("wild:calm-existing", 21)
local existing = Relationships.getOrCreate(existingEntity, player.id)
existing.familiarity = 5
existing.lastSeenTick = 0
local returnedExisting = PopulationManager.updatePhase0Relationship(
  existingEntity, player, 10, 9)
assertEquals(returnedExisting, existing,
  "existing canonical relationships may retain calm metadata updates")
assertEquals(existing.lastSeenTick, 10,
  "existing relationship lastSeen metadata must remain current")

local nearEntity = pokemon("wild:calm-near", 22)
local nearRelationship, applied = PopulationManager.updatePhase0Relationship(
  nearEntity, player, 10, 2)
assertEquals(nearEntity.relationships[player.id], nearRelationship,
  "meaningful near contact must allocate canonical player relationship")
assertEquals(applied, true,
  "meaningful near calm contact must retain its normal gain")
assertEquals(nearRelationship.familiarity, 1,
  "near calm familiarity coefficient must remain unchanged")

Relationships.setMutationSink(nil)

return true