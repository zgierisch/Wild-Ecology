local PlayableComponent = require("src.world.playable_component")
local SpawnCells = require("src.world.spawn_cells")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function connection(direction, x, y, destinationWidth, destinationHeight)
	return {
		direction = direction,
		destinationWidth = destinationWidth,
		destinationHeight = destinationHeight,
		sourceCells = { { cellX = x, cellY = y } },
		usableSourceCells = { { cellX = x, cellY = y } }
	}
end

local function inspect(rows, raw, connections)
	local semantics = WorldSemantics.fromOverview({
		mapId = "CONNECTION_SEED",
		width = #rows[1],
		height = #rows,
		rows = rows
	}, nil, {
		environmentClass = "OUTDOOR",
		connections = connections,
		warps = {}
	})
	local mod = {
		world = {
			current = function()
				return { mapId = "CONNECTION_SEED", x = raw[1], y = raw[2] }
			end
		}
	}
	return PlayableComponent.inspect(mod, "CONNECTION_SEED", semantics), semantics, mod
end

local rows = {
	".....",
	".....",
	".....",
	".....",
	"....."
}
for _, case in ipairs({
	{ direction = "north", raw = { 2, -1 }, source = { 2, 0 }, width = 5, height = 4 },
	{ direction = "south", raw = { 2, 5 }, source = { 2, 4 }, width = 5, height = 4 },
	{ direction = "west", raw = { -1, 2 }, source = { 0, 2 }, width = 4, height = 5 },
	{ direction = "east", raw = { 5, 2 }, source = { 4, 2 }, width = 4, height = 5 }
}) do
	local result = inspect(rows, case.raw, {
		connection(case.direction, case.source[1], case.source[2], case.width, case.height)
	})
	assertEquals(result.status, "READY", case.direction .. " extension should resolve")
	assertEquals(result.componentSeedCell.cellX, case.source[1], case.direction .. " seed x")
	assertEquals(result.componentSeedCell.cellY, case.source[2], case.direction .. " seed y")
	assertEquals(result.componentSeedSource, "MAP_CONNECTION", case.direction .. " seed source")
	assertEquals(result.componentSeedDirection, string.upper(case.direction), case.direction .. " seed direction")
end

local deepNorth = inspect(rows, { 2, -4 }, {
	connection("north", 2, 0, 5, 4)
})
assertEquals(deepNorth.status, "READY", "the full connected-map extension depth should resolve")

local tooDeep = inspect(rows, { 2, -5 }, {
	connection("north", 2, 0, 5, 4)
})
assertEquals(tooDeep.status, "UNAVAILABLE", "coordinates beyond the connected map should not resolve")
assertEquals(tooDeep.reason, "OUTSIDE_MAP_CONNECTION_MISMATCH", "extension depth mismatch should be explicit")

local mismatch = inspect(rows, { 3, -1 }, {
	connection("north", 2, 0, 5, 4)
})
assertEquals(mismatch.status, "UNAVAILABLE", "an unmatched connection axis should not resolve")
assertEquals(mismatch.reason, "OUTSIDE_MAP_CONNECTION_MISMATCH", "source mismatch should be explicit")

local missing = inspect(rows, { 2, -1 }, {})
assertEquals(missing.reason, "OUTSIDE_MAP_NO_CONNECTION", "a missing directional connection should be explicit")

local nonWalk = inspect({ ".. .." }, { 2, 0 }, {})
assertEquals(nonWalk.reason, "PLAYER_IN_BOUNDS_NON_WALK", "an in-bounds non-WALK player cell should be explicit")

local duplicate = connection("north", 2, 0, 5, 4)
local ambiguous = inspect(rows, { 2, -1 }, { duplicate, duplicate })
assertEquals(ambiguous.reason, "AMBIGUOUS_CONNECTION", "multiple matching connection records should not select arbitrarily")

local transitionSeed, transitionSemantics = inspect(rows, { 2, -1 }, {
	connection("north", 2, 0, 5, 4)
})
assertEquals(WorldSemantics.isSpawnAllowed(transitionSemantics, 2, 0), false, "a connection source should remain non-spawnable")
assertEquals(transitionSeed.status, "READY", "a non-spawnable transition should still seed its WALK component")

local playerY = 2
local stableSemantics = transitionSemantics
local stableMod = {
	world = { current = function() return { mapId = "CONNECTION_SEED", x = 2, y = playerY } end }
}
local direct = PlayableComponent.inspect(stableMod, "CONNECTION_SEED", stableSemantics)
playerY = 0
local boundary = PlayableComponent.inspect(stableMod, "CONNECTION_SEED", stableSemantics)
playerY = -1
local extension = PlayableComponent.inspect(stableMod, "CONNECTION_SEED", stableSemantics)
assertEquals(direct.activeComponentId, boundary.activeComponentId, "body and connection source should select the same component")
assertEquals(boundary.activeComponentId, extension.activeComponentId, "connection extension should retain the same component")
assertEquals(direct.buildNumber, extension.buildNumber, "seed movement should not rebuild components")

local splitRows = { ".. .." }
local selected, splitSemantics, splitMod = inspect(splitRows, { 4, -1 }, {
	connection("south", 1, 0, 5, 4),
	connection("north", 4, 0, 5, 4)
})
assertEquals(selected.status, "READY", "a matching extension should select a component when both have exits")
assertEquals(selected.activeComponentId, 2, "the player's connection should select the matching disconnected component")
local splitAnalysis = SpawnCells.analyzeCandidates(splitMod, "CONNECTION_SEED", {
	ecology = { locomotion = { WALK = true } }
}, splitSemantics)
assertEquals(splitAnalysis.finalCandidateCount, 1, "extension seeding should retain candidates in the matching component")
assertEquals(splitAnalysis.finalCandidates[1].x, 3, "the other exit-connected component should remain excluded")
assertEquals(splitAnalysis.spawnRejectedOutsidePlayableComponent, 1, "only the disconnected component's habitat should be rejected")

return true