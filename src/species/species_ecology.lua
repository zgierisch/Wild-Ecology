local Archetypes = require("src.species.ecology_archetypes")
local Profiles = require("src.species.profiles")

local SpeciesEcology = {}
local resolvedCache = {}
local counters = { resolveCalls = 0, sharedReads = 0, copies = 0, cacheMisses = 0 }

local ACTIVITY_PROFILES = {
	DIURNAL = true, NOCTURNAL = true, CREPUSCULAR = true,
	FLEXIBLE = true, WEAK_CIRCADIAN = true
}
local HABITATS = {
	GENERAL = true, OPEN_GRASS = true, WOODLAND_EDGE = true,
	GROUND_COVER = true, SETTLEMENT_EDGE = true, ROCKY_EDGE = true,
	CAVE = true, FRESH_WATER = true, SHORELINE = true,
	SHELTERED_GRASS = true, POWERED_SITE = true
}
local REST_SITES = {
	SHELTER = true, COVER = true, ELEVATED_COVER = true,
	DENSE_COVER = true, BURROW = true, CAVE_WALL = true,
	ROCKY_COVER = true, AQUATIC_COVER = true, SHALLOWS = true,
	POWERED_SITE = true
}
local CAPABILITIES = {
	WALK = true, FLY = true, CLIMB = true, SQUEEZE = true,
	SWIM = true, JUMP = true, BURROW = true, TELEPORT = true
}
local FOOD_OPPORTUNITY_TYPES = {
	TALL_GRASS_FORAGE = true
}
local CONCEALMENT_SITES = {
	TALL_GRASS = true
}
local SCHEMA = {
	root = { archetype = true, activityProfile = true, social = true,
		physiology = true, movement = true, habitat = true, restSites = true,
		concealmentSites = true, biologicalCapabilities = true, feeding = true,
		home = true, join = true },
	social = { modifier = true, familyModifier = true, desiredGroupSize = true },
	physiology = { thirstRate = true, hungerRate = true,
		fatigueRate = true, restRecovery = true },
	feeding = { acceptedOpportunityTypes = true },
	movement = { wanderScale = true },
	home = { radius = true, attachment = true, roamingTolerance = true },
	join = { familiarity = true, trust = true, affinity = true, maxThreat = true }
}

local FALLBACK = {
	archetype = "solitary", activityProfile = "FLEXIBLE",
	social = { modifier = 0.25, familyModifier = 0.75, desiredGroupSize = 1 },
	physiology = { thirstRate = 1, hungerRate = 1,
		fatigueRate = 1, restRecovery = 1 },
	feeding = { acceptedOpportunityTypes = {} },
	movement = { wanderScale = 1 },
	home = { radius = 2, attachment = 1, roamingTolerance = 2 },
	habitat = { "GENERAL" },
	restSites = { "SHELTER", "COVER" }, concealmentSites = {},
	biologicalCapabilities = { WALK = true }
}

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

local function merge(target, source)
	for key, value in pairs(source or {}) do
		if type(value) == "table" and type(target[key]) == "table"
			and #value == 0 and #target[key] == 0 then
			merge(target[key], value)
		else
			target[key] = copy(value)
		end
	end
	return target
end

local function bounded(name, value, minimum, maximum)
	assert(type(value) == "number", name .. " must be numeric")
	assert(value >= minimum and value <= maximum,
		name .. " must be between " .. minimum .. " and " .. maximum)
end

local function validateKeys(name, value, allowed)
	assert(type(value) == "table", name .. " must be a table")
	for key in pairs(value) do
		assert(allowed[key], "unknown ecology field " .. name .. "." .. tostring(key))
	end
end

local function validateRankedList(name, values, allowed)
	assert(type(values) == "table" and #values > 0,
		"at least one " .. name .. " preference is required")
	for index, value in ipairs(values) do
		assert(type(value) == "string" and allowed[value],
			"unknown " .. name .. " value at index " .. index .. ": " .. tostring(value))
	end
end

local function validateDefinition(name, definition, archetypes, requireComplete)
	validateKeys(name, definition, SCHEMA.root)
	if definition.archetype ~= nil then
		assert(type(definition.archetype) == "string", name .. ".archetype must be a string")
		assert(archetypes[definition.archetype],
			"unknown ecology archetype: " .. definition.archetype)
	end
	for _, section in ipairs({ "social", "physiology", "movement", "home", "join" }) do
		if definition[section] ~= nil then
			validateKeys(name .. "." .. section, definition[section], SCHEMA[section])
		end
	end
	if definition.feeding ~= nil then
		validateKeys(name .. ".feeding", definition.feeding, SCHEMA.feeding)
		local accepted = definition.feeding.acceptedOpportunityTypes
		if accepted ~= nil then
			assert(type(accepted) == "table",
				name .. ".feeding.acceptedOpportunityTypes must be a table")
			for index, opportunityType in ipairs(accepted) do
				assert(FOOD_OPPORTUNITY_TYPES[opportunityType],
					"unknown food opportunity type at index " .. index .. ": "
					.. tostring(opportunityType))
			end
			for key in pairs(accepted) do
				assert(type(key) == "number" and key >= 1 and key <= #accepted
					and key % 1 == 0,
					name .. ".feeding.acceptedOpportunityTypes must be an array")
			end
		end
	end
	if definition.activityProfile ~= nil then
		assert(ACTIVITY_PROFILES[definition.activityProfile],
			"unknown activity profile: " .. tostring(definition.activityProfile))
	end
	if definition.habitat ~= nil then
		validateRankedList("habitat", definition.habitat, HABITATS)
	end
	if definition.restSites ~= nil then
		validateRankedList("rest-site", definition.restSites, REST_SITES)
	end
	if definition.concealmentSites ~= nil then
		assert(type(definition.concealmentSites) == "table",
			name .. ".concealmentSites must be a table")
		for index, concealmentType in ipairs(definition.concealmentSites) do
			assert(CONCEALMENT_SITES[concealmentType],
				"unknown concealment site at index " .. index .. ": "
				.. tostring(concealmentType))
		end
		for key in pairs(definition.concealmentSites) do
			assert(type(key) == "number" and key >= 1
				and key <= #definition.concealmentSites and key % 1 == 0,
				name .. ".concealmentSites must be an array")
		end
	end
	if definition.biologicalCapabilities ~= nil then
		for capability, value in pairs(definition.biologicalCapabilities) do
			assert(CAPABILITIES[capability],
				"unknown biological capability: " .. tostring(capability))
			assert(type(value) == "boolean",
				"biological capability " .. capability .. " must be boolean")
		end
	end
	if requireComplete then SpeciesEcology.validate(definition) end
end

function SpeciesEcology.validate(profile)
	assert(type(profile.archetype) == "string", "ecology archetype is required")
	assert(ACTIVITY_PROFILES[profile.activityProfile],
		"unknown activity profile: " .. tostring(profile.activityProfile))
	for key, value in pairs(profile.physiology or {}) do bounded("physiology." .. key, value, 0.5, 2) end
	validateDefinition("resolved", { feeding = profile.feeding },
		Archetypes, false)
	bounded("movement.wanderScale", profile.movement.wanderScale, 0.5, 1.5)
	bounded("home.radius", profile.home.radius, 1, 5)
	bounded("home.attachment", profile.home.attachment, 0.5, 1.5)
	bounded("home.roamingTolerance", profile.home.roamingTolerance, 1, 6)
	bounded("social.modifier", profile.social.modifier, 0, 2)
	bounded("social.familyModifier", profile.social.familyModifier, 0, 2)
	bounded("social.desiredGroupSize", profile.social.desiredGroupSize, 1, 12)
	validateRankedList("habitat", profile.habitat, HABITATS)
	validateRankedList("rest-site", profile.restSites, REST_SITES)
	validateDefinition("resolved", {
		concealmentSites = profile.concealmentSites or {}
	}, Archetypes, false)
	if profile.join then
		for key, value in pairs(profile.join) do bounded("join." .. key, value, 0, 100) end
	end
	return true
end

function SpeciesEcology.validateDefinitions(archetypes, profiles)
	for archetypeId, archetype in pairs(archetypes or {}) do
		assert(type(archetypeId) == "string" and archetypeId ~= "",
			"ecology archetype id is required")
		validateDefinition("archetype." .. archetypeId, archetype, archetypes, false)
		local resolved = merge(copy(FALLBACK), archetype)
		resolved.archetype = archetypeId
		SpeciesEcology.validate(resolved)
	end
	for species, profile in pairs(profiles or {}) do
		assert(type(species) == "string" and species ~= "", "species id is required")
		assert(type(profile.archetype) == "string",
			"species." .. species .. ".archetype is required")
		validateDefinition("species." .. species, profile, archetypes, false)
		local resolved = merge(copy(FALLBACK), archetypes[profile.archetype])
		merge(resolved, profile)
		resolved.archetype = profile.archetype
		SpeciesEcology.validate(resolved)
	end
	return true
end

function SpeciesEcology.resolve(species)
	counters.resolveCalls = counters.resolveCalls + 1
	if species ~= nil and resolvedCache[species] then
		counters.copies = counters.copies + 1
		return copy(resolvedCache[species])
	end
	counters.cacheMisses = counters.cacheMisses + 1
	local override = Profiles[species] or {}
	local archetypeId = override.archetype or FALLBACK.archetype
	assert(Archetypes[archetypeId], "unknown ecology archetype: " .. tostring(archetypeId))
	local result = merge(copy(FALLBACK), Archetypes[archetypeId])
	merge(result, override)
	result.speciesId = species
	result.archetype = archetypeId
	SpeciesEcology.validate(result)
	if species ~= nil then
		resolvedCache[species] = result
	end
	counters.copies = counters.copies + 1
	return copy(result)
end

function SpeciesEcology.getResolved(species)
	counters.sharedReads = counters.sharedReads + 1
	if species ~= nil and resolvedCache[species] then
		return resolvedCache[species]
	end
	if species == nil then
		return SpeciesEcology.resolve(nil)
	end
	SpeciesEcology.resolve(species)
	return resolvedCache[species]
end

function SpeciesEcology.getCounters()
	local result = {}
	for key, value in pairs(counters) do result[key] = value end
	return result
end

function SpeciesEcology.resetCounters()
	for key in pairs(counters) do counters[key] = 0 end
end

function SpeciesEcology.clearCache()
	resolvedCache = {}
end

function SpeciesEcology.inspect(species)
	local profile = SpeciesEcology.resolve(species)
	return string.format(
		"SPECIES ECOLOGY species=%s archetype=%s activity=%s social=%.2f group=%d thirst=%.2f fatigue=%.2f recovery=%.2f wander=%.2f habitat=%s rest=%s",
		tostring(species), profile.archetype, profile.activityProfile,
		profile.social.modifier, profile.social.desiredGroupSize,
		profile.physiology.thirstRate, profile.physiology.fatigueRate,
		profile.physiology.restRecovery, profile.movement.wanderScale,
		table.concat(profile.habitat, ","), table.concat(profile.restSites, ","))
end

SpeciesEcology.validateDefinitions(Archetypes, Profiles)

return SpeciesEcology