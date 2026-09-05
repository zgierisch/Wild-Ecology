local Save = require("src.core.save")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local storedState = nil
local persistenceAdapter = {
	load = function()
		return storedState
	end,
	save = function(_, value)
		storedState = value
		return true
	end
}

-- Schema v8 adds durable local home areas after v7 concealment.
storedState = {
	schemaVersion = 5,
	simulationTick = 75,
	populations = { ROUTE_2 = { members = { prior = {
		personalitySeed = 19,
		drives = {
			THIRST = { value = 0.44, lastUpdatedTick = 50 },
			FATIGUE = { value = 0.33, lastUpdatedTick = 50 }
		},
		relationships = { player = { familiarity = 7, trust = 3 } },
		runtimeState = { state = "TARGET" }
	} } } }
}
Save.init(persistenceAdapter)
local versionSix = Save.getState()
assertEquals(versionSix.schemaVersion, 8, "v5 saves should migrate to schema v8")
assertEquals(versionSix.populations.ROUTE_2.members.prior.drives.THIRST.value,
	0.44, "v6 migration must preserve thirst")
assertEquals(versionSix.populations.ROUTE_2.members.prior.drives.FATIGUE.value,
	0.33, "v6 migration must preserve fatigue")
assertEquals(versionSix.populations.ROUTE_2.members.prior.relationships.player.familiarity,
	7, "v6 migration must preserve relationships")
assertEquals(type(versionSix.populations.ROUTE_2.members.prior.drives.HUNGER),
	"table", "v6 migration should add hunger")
assertEquals(versionSix.populations.ROUTE_2.members.prior.drives.HUNGER.lastUpdatedTick,
	75, "migrated hunger should use deterministic simulation-time provenance")
assertEquals(versionSix.populations.ROUTE_2.members.prior.runtimeState, nil,
	"v6 migration must not retain runtime state")
assertEquals(versionSix.populations.ROUTE_2.members.prior.home, nil,
	"migration must not invent home without trustworthy live placement semantics")
local migratedHunger = versionSix.populations.ROUTE_2.members.prior.drives.HUNGER.value
Save.init(persistenceAdapter)
assertEquals(Save.getState().populations.ROUTE_2.members.prior.drives.HUNGER.value,
	migratedHunger, "v6 migration should be idempotent")

-- Migrate a legacy-shaped state that is missing fields.
storedState = {
	schemaVersion = 1,
	populations = {
		ROUTE_1 = {
			members = {
				legacy = {
					relationships = { player = { threatMemory = 40 } },
					runtimeState = {
						fearCurrent = 1,
						targetEntityId = "player",
						movementRequest = { direction = "UP" }
					}
				}
			}
		}
	}
}
Save.init(persistenceAdapter)
local migrated = Save.getState()
if not migrated then
	error("Save.getState should return a state table")
end
assertEquals(type(migrated.populations), "table", "migrated state should include populations")
assertEquals(migrated.nextEntitySerial, 1, "migrated state should include nextEntitySerial")
assertEquals(migrated.schemaVersion, 8, "legacy saves should migrate through the home-area schema")
assertEquals(migrated.populations.ROUTE_1.members.legacy.relationships.player.threatMemory, 40, "migration should preserve legacy general threat memory")
assertEquals(migrated.populations.ROUTE_1.members.legacy.relationships.player.directThreatMemory, 0, "legacy general memory should not become direct-threat provenance")
assertEquals(type(migrated.populations.ROUTE_1.members.legacy.drives.THIRST), "table",
	"legacy entities should receive persistent thirst state")
assertEquals(migrated.populations.ROUTE_1.members.legacy.drives.THIRST.value < 0.25, true,
	"legacy entities must migrate at a calm thirst baseline")
assertEquals(type(migrated.populations.ROUTE_1.members.legacy.drives.FATIGUE), "table",
	"legacy entities should receive persistent fatigue state")
assertEquals(type(migrated.populations.ROUTE_1.members.legacy.drives.HUNGER), "table",
	"legacy entities should receive persistent hunger state")
assertEquals(type(migrated.populations.ROUTE_1.members.legacy.ecology.circadian), "table",
	"legacy entities should receive stable circadian identity variation")
assertEquals(migrated.ecologyClock.mode, "SIMULATION",
	"legacy saves should receive the explicit frozen-while-closed clock policy")
assertEquals(type(migrated.dormantCohorts), "table",
	"legacy saves should receive dormant cohort storage")
assertEquals(migrated.populations.ROUTE_1.members.legacy.runtimeState, nil,
	"load migration should discard transient runtime state from older saves")

-- Persist route population content and ensure roundtrip reload works.
migrated.populations.ROUTE_1 = {
	members = {
		["wild:route01:0001"] = {
			id = "wild:route01:0001",
			species = "PIDGEY",
			level = 4,
			ecology = { activityProfile = "DIURNAL",
				circadian = { phaseOffset = 0.02, amplitudeScale = 1.01 },
				feeding = { acceptedOpportunityTypes = { "TALL_GRASS_FORAGE" } },
				physiology = { hungerRate = 1.05 },
				home = { radius = 3, attachment = 0.9, roamingTolerance = 4 },
				concealmentSites = { "TALL_GRASS" } },
			drives = {
				THIRST = { value = 0.42, lastUpdatedTick = 50, lastSatisfiedTick = 20 },
				HUNGER = { value = 0.48, lastUpdatedTick = 50, lastSatisfiedTick = 10 },
				FATIGUE = { value = 0.36, lastUpdatedTick = 50 }
			},
			relationships = {
				["wild:route01:0002"] = {
					familiarity = 12,
					trust = 8,
					affinity = 3,
					threatMemory = 4,
					directThreatMemory = 2,
					hostility = 1,
					lastSeenTick = 99
				}
			},
			locationState = {
				kind = "CONCEALED",
				mapId = "ROUTE_1",
				concealmentType = "TALL_GRASS",
				anchorCell = { cellX = 4, cellY = 5 },
				enteredTick = 50,
				awareness = "ASLEEP",
				resting = true
			},
			home = {
				mapId = "ROUTE_1", spawnX = 6, spawnY = 5,
				area = {
					mapId = "ROUTE_1",
					anchorCell = { cellX = 6, cellY = 5 },
					radius = 3,
					establishedTick = 45,
					provenance = "POPULATION_PLACEMENT"
				}
			},
			runtimeState = {
				fearCurrent = 0.8,
				targetEntityId = "wild:route01:0002",
				movementRequest = { direction = "LEFT" },
				socialEscapeBias = { dx = -1, dy = 0 },
				homeReturnDestination = { cellX = 8, cellY = 5 },
				navigation = { ownerBehavior = "RETURN_HOME" },
				behaviorScores = { RETURN_HOME = 62 }
			}
		}
	}
}
Save.flush()

assertEquals(migrated.populations.ROUTE_1.members["wild:route01:0001"].runtimeState.fearCurrent,
	0.8, "flushing must not mutate live runtime state")
assertEquals(storedState.populations.ROUTE_1.members["wild:route01:0001"].runtimeState,
	nil, "serialized population members must exclude transient runtime state")
assertEquals(storedState.populations.ROUTE_1.members["wild:route01:0001"]
	.locationState.kind, "CONCEALED",
	"serialized population members should retain concealed local presence")

Save.init(persistenceAdapter)
local reloaded = Save.getState()
if not reloaded or not reloaded.populations or not reloaded.populations.ROUTE_1 then
	error("reloaded state should include ROUTE_1 population")
end
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].species, "PIDGEY", "species should survive storage roundtrip")
local reloadedRelationship = reloaded.populations.ROUTE_1.members["wild:route01:0001"]
	.relationships["wild:route01:0002"]
assertEquals(reloadedRelationship.familiarity, 12, "directed familiarity should survive storage roundtrip")
assertEquals(reloadedRelationship.trust, 8, "directed trust should survive storage roundtrip")
assertEquals(reloadedRelationship.affinity, 3, "directed affinity should survive storage roundtrip")
assertEquals(reloadedRelationship.threatMemory, 4, "general threat memory should survive storage roundtrip")
assertEquals(reloadedRelationship.directThreatMemory, 2, "direct threat provenance should survive storage roundtrip")
assertEquals(reloadedRelationship.hostility, 1, "hostility should survive storage roundtrip")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].drives.THIRST.value,
	0.42, "biological drive values should survive storage roundtrip")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].drives.FATIGUE.value,
	0.36, "fatigue should survive storage roundtrip")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].drives.HUNGER.value,
	0.48, "hunger should survive storage roundtrip")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].ecology.circadian.phaseOffset,
	0.02, "circadian identity variation should survive storage roundtrip")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].ecology.feeding,
	nil, "static feeding profiles must not persist")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].ecology.physiology,
	nil, "static hunger physiology must not persist")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].ecology.home,
	nil, "static species home tendencies must not persist")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"]
	.ecology.concealmentSites, nil,
	"static concealment preferences must not persist")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"]
	.locationState.anchorCell.cellX, 4,
	"save/load should preserve concealed anchor state")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"]
	.locationState.awareness, "ASLEEP",
	"save/load should preserve hidden presence without materializing an avatar")
local reloadedHome = reloaded.populations.ROUTE_1.members["wild:route01:0001"].home
assertEquals(reloadedHome.area.anchorCell.cellX, 6,
	"save/load should preserve stable home anchor")
assertEquals(reloadedHome.area.radius, 3,
	"save/load should preserve ecological area radius")
assertEquals(reloadedHome.area.provenance, "POPULATION_PLACEMENT",
	"save/load should preserve home assignment provenance")
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].runtimeState,
	nil, "runtime Fear, home destinations, navigation, scores, and social cues must not reload")

return true
