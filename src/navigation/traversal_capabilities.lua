local SpeciesEcology = require("src.species.species_ecology")
local PokemonMechanics = require("src.adapters.pokemon_mechanics")
local MoveSemantics = require("src.mechanics.move_semantics")

local TraversalCapabilities = {}

local MODES = { "WALK", "FLY", "CLIMB", "SQUEEZE", "SWIM", "JUMP", "BURROW", "TELEPORT" }
local EXECUTABLE_MODES = { WALK = true }

function TraversalCapabilities.forEntity(entity)
  local declarations = TraversalCapabilities.declarationsForEntity(entity)
  local capabilities = {}
  for _, mode in ipairs(MODES) do
    local value = declarations.biological[mode]
    if mode == "WALK" and value == nil then
      value = true
    end
    if mode == "TELEPORT" and value == true then
      value = { enabled = true, maxRange = 4, requiresLineOfSight = false }
    end
    capabilities[mode] = value or false
  end
  return capabilities
end

function TraversalCapabilities.declarationsForEntity(entity)
  local profile = SpeciesEcology.getResolved(entity and entity.species)
  local biological = {}
  for mode, value in pairs(profile.biologicalCapabilities or {}) do
    biological[mode] = value
  end
  for mode, value in pairs(entity and entity.ecology
    and entity.ecology.locomotion or {}) do
    biological[mode] = value
  end
  local learned = MoveSemantics.analyze(PokemonMechanics.snapshot(entity))
    .declaredCapabilities
  return {
    biological = biological,
    learned = learned,
    executable = TraversalCapabilities.executableModes()
  }
end

function TraversalCapabilities.executableModes()
  local copy = {}
  for mode, executable in pairs(EXECUTABLE_MODES) do
    copy[mode] = executable
  end
  return copy
end

return TraversalCapabilities