-- Personality-generation ranges, family pools, and temporary sprite fallback.
-- SpeciesEcology owns biological, social, habitat, and activity baselines.
local BaseRanges = {}

BaseRanges.species = {
  PIDGEY = {
    familyPool = { "A", "B", "C" },
    -- No distinct overworld sprite assets exist yet for any species (see
    -- src/world/avatar_factory.lua); every species defaults to the one
    -- verified-working placeholder ("SPRITE_BIRD") until real per-species
    -- sprites are registered and mapped here.
    defaultSprite = "SPRITE_BIRD",
    stats = {
      curiosity = { min = 0.30, max = 0.55 },
      timidity = { min = 0.55, max = 0.85 },
      aggression = { min = 0.05, max = 0.20 },
      social = { min = 0.60, max = 0.90 },
      active = { min = 0.55, max = 0.85 },
      independence = { min = 0.20, max = 0.45 }
    }
  },
  RATTATA = {
    familyPool = { "A", "B" },
    defaultSprite = "SPRITE_BIRD",
    stats = {
      curiosity = { min = 0.35, max = 0.65 },
      timidity = { min = 0.35, max = 0.60 },
      aggression = { min = 0.15, max = 0.35 },
      social = { min = 0.35, max = 0.55 },
      active = { min = 0.45, max = 0.75 },
      independence = { min = 0.45, max = 0.75 }
    }
  },
  SPEAROW = {
    familyPool = { "A", "B" },
    defaultSprite = "SPRITE_BIRD",
    stats = {
      curiosity = { min = 0.25, max = 0.50 },
      timidity = { min = 0.35, max = 0.60 },
      aggression = { min = 0.30, max = 0.55 },
      social = { min = 0.50, max = 0.75 },
      active = { min = 0.60, max = 0.90 },
      independence = { min = 0.30, max = 0.55 }
    }
  },
  default = {
    familyPool = { "A" },
    defaultSprite = "SPRITE_BIRD",
    stats = {
      curiosity = { min = 0.35, max = 0.65 },
      timidity = { min = 0.40, max = 0.70 },
      aggression = { min = 0.05, max = 0.20 },
      social = { min = 0.35, max = 0.65 },
      active = { min = 0.35, max = 0.65 },
      independence = { min = 0.40, max = 0.70 }
    }
  }
}

function BaseRanges.get(species)
  return BaseRanges.species[species] or BaseRanges.species.default
end

return BaseRanges
