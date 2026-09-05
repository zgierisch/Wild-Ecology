package.path = package.path .. ";./?.lua;./?/init.lua"

local EcologyInspector = require("src.debug.ecology_inspector")
local DormantCohort = require("src.dormant.dormant_cohort")
local Simulator = require("src.dormant.dormant_cohort_simulator")
local Entity = require("src.entities.entity")

local entity = Entity.newWildPokemon({ id = "inspect-1", species = "PIDGEY",
	level = 4, personalitySeed = 42, firstEncounteredTick = 0,
	home = { mapId = "ROUTE_1", spawnX = 4, spawnY = 5,
		area = { mapId = "ROUTE_1", anchorCell = { cellX = 4, cellY = 5 },
			radius = 3, establishedTick = 0,
			provenance = "POPULATION_PLACEMENT" } } })
entity.runtimeState = {
	state = "RETURN_HOME", goalSelfPosition = {
		cellX = 9, cellY = 5, mapId = "ROUTE_1"
	}, behaviorScores = { RETURN_HOME = 54 },
	homeReturnDestination = { cellX = 7, cellY = 5 }
}
local sample = { source = "SIMULATION", phase = 0.5, hour = 12, minute = 0,
	second = 0, band = "DAY", dayIndex = 1, monotonicEcologyTime = 129600 }
local actorReport = EcologyInspector.actor(entity, sample, 0)
assert(actorReport:find("source=SIMULATION", 1, true),
	"actor report should identify the clock source")
assert(actorReport:find("profile=DIURNAL", 1, true),
	"actor report should expose circadian identity")
assert(actorReport:find("FATIGUE value=", 1, true),
	"actor report should expose persistent drives")
assert(actorReport:find("HUNGER value=", 1, true),
	"actor report should expose persistent hunger")
assert(actorReport:find("HOME established=true map=ROUTE_1", 1, true),
	"actor report should expose durable home identity")
assert(actorReport:find("score=54.00 active=true destination=7,5", 1, true),
	"actor report should expose compact RETURN_HOME state")
assert(actorReport:find("REST motivated=false", 1, true),
	"actor report should expose compact REST state")
assert(actorReport:find("CONCEALMENT state=VISIBLE", 1, true),
	"actor report should expose visible versus concealed location state")

local cohort = DormantCohort.capture("ROUTE_1", { entity }, 0,
	{ reachableWater = true })
Simulator.advance(cohort, { [entity.id] = entity }, 24 * 3600)
local cohortReport = EcologyInspector.cohort(cohort, sample)
assert(cohortReport:find("members=1", 1, true),
	"cohort report should expose materialized membership")
assert(cohortReport:find("opportunities=1", 1, true),
	"cohort report should expose generalized coarse opportunity evidence")
assert(cohortReport:find("segments=48", 1, true),
	"cohort report should expose bounded catch-up work")

return true