return {
	solitary = {
		activityProfile = "FLEXIBLE",
		social = { modifier = 0.25, familyModifier = 0.75, desiredGroupSize = 1 },
		physiology = { thirstRate = 1, hungerRate = 1,
			fatigueRate = 1, restRecovery = 1 },
		movement = { wanderScale = 1 },
		home = { radius = 2, attachment = 1, roamingTolerance = 3 },
		habitat = { "GENERAL" }, restSites = { "SHELTER", "COVER" },
		biologicalCapabilities = { WALK = true }
	},
	flocking_bird = {
		activityProfile = "DIURNAL",
		social = { modifier = 1.2, familyModifier = 1.2, desiredGroupSize = 2 },
		physiology = { thirstRate = 1.05, hungerRate = 1.05,
			fatigueRate = 0.95, restRecovery = 1.05 },
		movement = { wanderScale = 1.08 },
		home = { radius = 3, attachment = 0.85, roamingTolerance = 4 },
		habitat = { "OPEN_GRASS", "WOODLAND_EDGE" },
		restSites = { "ELEVATED_COVER", "SHELTER" },
		biologicalCapabilities = { WALK = true, FLY = true }
	},
	small_forager = {
		activityProfile = "NOCTURNAL",
		social = { modifier = 0.65, familyModifier = 1.1, desiredGroupSize = 1 },
		physiology = { thirstRate = 1.1, hungerRate = 1.15,
			fatigueRate = 1.05, restRecovery = 1 },
		feeding = { acceptedOpportunityTypes = { "TALL_GRASS_FORAGE" } },
		movement = { wanderScale = 0.95 },
		home = { radius = 2, attachment = 1.2, roamingTolerance = 2 },
		habitat = { "GROUND_COVER", "SETTLEMENT_EDGE" },
		restSites = { "BURROW", "DENSE_COVER" },
		concealmentSites = { "TALL_GRASS" },
		biologicalCapabilities = { WALK = true, SQUEEZE = true }
	},
	sheltered_grazer = {
		activityProfile = "CREPUSCULAR",
		social = { modifier = 0.8, familyModifier = 1.25, desiredGroupSize = 2 },
		physiology = { thirstRate = 0.85, hungerRate = 0.9,
			fatigueRate = 1.1, restRecovery = 1.1 },
		feeding = { acceptedOpportunityTypes = { "TALL_GRASS_FORAGE" } },
		movement = { wanderScale = 0.78 },
		home = { radius = 2, attachment = 1.25, roamingTolerance = 2 },
		habitat = { "WOODLAND_EDGE", "GROUND_COVER" },
		restSites = { "DENSE_COVER", "SHELTER" },
		concealmentSites = { "TALL_GRASS" },
		biologicalCapabilities = { WALK = true, SQUEEZE = true }
	},
	cave_flyer = {
		activityProfile = "NOCTURNAL",
		social = { modifier = 1.15, familyModifier = 1.15, desiredGroupSize = 3 },
		physiology = { thirstRate = 0.9, hungerRate = 1.1,
			fatigueRate = 0.95, restRecovery = 1.05 },
		movement = { wanderScale = 1.05 },
		home = { radius = 3, attachment = 1.1, roamingTolerance = 3 },
		habitat = { "CAVE", "ROCKY_EDGE" },
		restSites = { "ELEVATED_COVER", "CAVE_WALL" },
		biologicalCapabilities = { WALK = true, FLY = true }
	},
	rocky_solitary = {
		activityProfile = "FLEXIBLE",
		social = { modifier = 0.3, familyModifier = 0.8, desiredGroupSize = 1 },
		physiology = { thirstRate = 0.65, hungerRate = 0.65,
			fatigueRate = 0.75, restRecovery = 0.9 },
		movement = { wanderScale = 0.72 },
		home = { radius = 3, attachment = 1.15, roamingTolerance = 2 },
		habitat = { "ROCKY_EDGE", "CAVE" },
		restSites = { "SHELTER", "ROCKY_COVER" },
		biologicalCapabilities = { WALK = true, CLIMB = true }
	},
	aquatic_schooler = {
		activityProfile = "DIURNAL",
		social = { modifier = 1.2, familyModifier = 1.2, desiredGroupSize = 4 },
		physiology = { thirstRate = 0.5, hungerRate = 0.85,
			fatigueRate = 0.9, restRecovery = 1 },
		movement = { wanderScale = 1.05 },
		home = { radius = 4, attachment = 0.8, roamingTolerance = 5 },
		habitat = { "FRESH_WATER", "SHORELINE" },
		restSites = { "AQUATIC_COVER", "SHALLOWS" },
		biologicalCapabilities = { WALK = false, SWIM = true }
	},
	elusive_solitary = {
		activityProfile = "CREPUSCULAR",
		social = { modifier = 0.15, familyModifier = 0.75, desiredGroupSize = 1 },
		physiology = { thirstRate = 0.9, hungerRate = 0.95,
			fatigueRate = 0.85, restRecovery = 1.15 },
		movement = { wanderScale = 0.9 },
		home = { radius = 2, attachment = 0.75, roamingTolerance = 5 },
		habitat = { "SETTLEMENT_EDGE", "SHELTERED_GRASS" },
		restSites = { "SHELTER", "DENSE_COVER" },
		biologicalCapabilities = { WALK = true, TELEPORT = true }
	},
	weak_circadian_construct = {
		activityProfile = "WEAK_CIRCADIAN",
		social = { modifier = 0.45, familyModifier = 1, desiredGroupSize = 2 },
		physiology = { thirstRate = 0.5, hungerRate = 0.5,
			fatigueRate = 0.65, restRecovery = 0.8 },
		movement = { wanderScale = 0.88 },
		home = { radius = 2, attachment = 1, roamingTolerance = 3 },
		habitat = { "POWERED_SITE", "ROCKY_EDGE" },
		restSites = { "POWERED_SITE", "SHELTER" },
		biologicalCapabilities = { WALK = true, FLY = true }
	}
}