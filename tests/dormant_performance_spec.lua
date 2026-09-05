package.path = package.path .. ";./?.lua;./?/init.lua"

local DormantCohort = require("src.dormant.dormant_cohort")
local Simulator = require("src.dormant.dormant_cohort_simulator")
local Entity = require("src.entities.entity")

local HOUR = 3600
local durations = {
	{ label = "1h", seconds = HOUR },
	{ label = "1d", seconds = 24 * HOUR },
	{ label = "30d", seconds = 30 * 24 * HOUR },
	{ label = "180d", seconds = 180 * 24 * HOUR }
}

local function scenario(actorCount, elapsed)
	local actors, entitiesById, positions = {}, {}, {}
	for index = 1, actorCount do
		local id = string.format("bench-%02d", index)
		local entity = Entity.newWildPokemon({ id = id, species = "PIDGEY",
			level = 4, personalitySeed = index, firstEncounteredTick = 0 })
		entity.relationships = {}
		actors[index] = entity
		entitiesById[id] = entity
		positions[id] = { cellX = index * 4, cellY = 0 }
	end
	for index, entity in ipairs(actors) do
		local target = actors[(index % actorCount) + 1]
		entity.relationships[target.id] = {
			familiarity = 5, affinity = 1, trust = 0, fear = 0,
			hostility = 0, lastUpdatedTick = 0
		}
	end
	local cohort = DormantCohort.capture("BENCH", actors, 0,
		{ positions = positions, reachableWater = false })
	local started = os.clock()
	local result = Simulator.advance(cohort, entitiesById, elapsed)
	return result, (os.clock() - started) * 1000
end

print("actors,duration,runtime_ms,segments,pair_candidates,total_possible_pairs")
local totalRuntime = 0
for _, actorCount in ipairs({ 10, 20, 50 }) do
	for _, duration in ipairs(durations) do
		local result, runtimeMs = scenario(actorCount, duration.seconds)
		totalRuntime = totalRuntime + runtimeMs
		assert(result.segments <= Simulator.MAX_SEGMENTS,
			"catch-up duration must not exceed the segment cap")
		assert(result.pairCandidates == actorCount,
			"directed ring should produce one sparse candidate per actor")
		assert(result.totalPossibleDirectedPairs == actorCount * (actorCount - 1),
			"diagnostic denominator should include all possible directed pairs")
		print(string.format("%d,%s,%.3f,%d,%d,%d", actorCount,
			duration.label, runtimeMs, result.segments, result.pairCandidates,
			result.totalPossibleDirectedPairs))
	end
end
assert(totalRuntime < 5000,
	"the complete dormant catch-up matrix should remain coarse and bounded")

return true