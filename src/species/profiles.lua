local Profiles = {
  PIDGEY = {
    archetype = "flocking_bird",
    social = { modifier = 1.5, familyModifier = 1.25, desiredGroupSize = 3 },
    physiology = { thirstRate = 1.1, hungerRate = 1.05,
      fatigueRate = 0.9, restRecovery = 1.1 },
    feeding = { acceptedOpportunityTypes = { "TALL_GRASS_FORAGE" } },
    habitat = { "OPEN_GRASS", "WOODLAND_EDGE" },
    restSites = { "ELEVATED_COVER", "DENSE_COVER" },
    concealmentSites = { "TALL_GRASS" },
    join = {
      familiarity = 60,
      trust = 50,
      affinity = 20,
      maxThreat = 10
    }
  },
  RATTATA = {
    archetype = "small_forager"
  },
  SPEAROW = {
    archetype = "flocking_bird",
    physiology = { thirstRate = 1.15, hungerRate = 1.1,
      fatigueRate = 0.95, restRecovery = 1.05 },
    movement = { wanderScale = 1.15 },
    habitat = { "OPEN_GRASS", "ROCKY_EDGE" },
    restSites = { "ELEVATED_COVER", "SHELTER" }
  },
  CATERPIE = {
    archetype = "sheltered_grazer"
  },
  ZUBAT = {
    archetype = "cave_flyer"
  },
  GEODUDE = {
    archetype = "rocky_solitary"
  },
  ONIX = {
    archetype = "rocky_solitary",
    movement = { wanderScale = 0.62 }
  },
  GOLDEEN = {
    archetype = "aquatic_schooler"
  },
  MAGIKARP = {
    archetype = "aquatic_schooler",
    movement = { wanderScale = 0.68 },
    social = { modifier = 1, familyModifier = 1.1, desiredGroupSize = 3 }
  },
  ABRA = {
    archetype = "elusive_solitary"
  },
  MAGNEMITE = {
    archetype = "weak_circadian_construct"
  }
}

return Profiles
