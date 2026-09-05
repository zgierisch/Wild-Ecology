local FlockSearch = require("src.behavior.flock_search")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function makeEntity(id, family, independence)
	return {
		id = id,
		species = "PIDGEY",
		ecology = { family = family, socialModifier = 1.5 },
		rawStats = { independence = independence or 0.2 },
		temperament = { sociability = 0.9 },
		relationships = {}
	}
end

local origin = { cellX = 0, cellY = 0 }
local ownFamily = makeEntity("family-b", "B")
local otherFamily = makeEntity("family-a", "A")
local seeker = makeEntity("seeker", "B")
local result = FlockSearch.update(seeker, origin, {
	{ entity = otherFamily, position = { cellX = 8, cellY = 0 } },
	{ entity = ownFamily, position = { cellX = 0, cellY = 8 } }
}, 400)
assertEquals(result.targetEntityId, "family-b", "own-family viable candidates should form the preferred tier")

local fallbackSeeker = makeEntity("fallback", "B")
local fallback = FlockSearch.update(fallbackSeeker, origin, {
	{ entity = otherFamily, position = { cellX = 8, cellY = 0 } },
	{ entity = ownFamily, position = nil }
}, 400)
assertEquals(fallback.targetEntityId, "family-a", "same-species candidates should be valid when no family cue exists")

local fallbackRankSeeker = makeEntity("fallback-rank", "B")
local familyC = makeEntity("family-c", "C")
fallbackRankSeeker.relationships[familyC.id] = { trust = 80, affinity = 80, familiarity = 80 }
local rankedFallback = FlockSearch.update(fallbackRankSeeker, origin, {
	{ entity = otherFamily, position = { cellX = 8, cellY = 0 } },
	{ entity = familyC, position = { cellX = 0, cellY = 8 } }
}, 400)
assertEquals(rankedFallback.targetEntityId, familyC.id, "relationships should rank candidates within the fallback tier")

local cueTierSeeker = makeEntity("cue-tier", "B")
cueTierSeeker.relationships[familyC.id] = { trust = 100, affinity = 100, familiarity = 100 }
FlockSearch.update(cueTierSeeker, origin, {
	{ entity = otherFamily, position = { cellX = 4, cellY = 0 }, perceived = true }
}, 10)
local cueTierResult = FlockSearch.update(cueTierSeeker, origin, {
	{ entity = familyC, position = { cellX = 8, cellY = 0 } }
}, 120)
assertEquals(cueTierResult.targetEntityId, otherFamily.id, "recent last-known cues should form a preferred source tier over coarse signals")
assertEquals(cueTierResult.cueSource, "last_seen", "source hierarchy should not be reducible to a relationship bonus")

local relationshipSeeker = makeEntity("relationships", "B")
relationshipSeeker.relationships[otherFamily.id] = { trust = 100, affinity = 100, familiarity = 100 }
local relationshipResult = FlockSearch.update(relationshipSeeker, origin, {
	{ entity = otherFamily, position = { cellX = 7, cellY = 0 } },
	{ entity = ownFamily, position = { cellX = 0, cellY = 10 } }
}, 400)
assertEquals(relationshipResult.targetEntityId, "family-b", "strong fallback relationships must not defeat the family tier")

local groupedSeeker = makeEntity("grouped", "B")
FlockSearch.update(groupedSeeker, origin, {}, 0)
local isolated = FlockSearch.update(groupedSeeker, origin, {}, 400)
local grouped = FlockSearch.update(groupedSeeker, origin, {
	{ entity = otherFamily, position = { cellX = 1, cellY = 0 }, perceived = true }
}, 401)
assertEquals(grouped.utility < isolated.utility, true, "nearby non-family conspecifics should substantially reduce isolation pressure")
assertEquals(grouped.familyPressure > 0, true, "family reunion pressure may remain among non-family conspecifics")

local originalFamily = groupedSeeker.ecology.family
groupedSeeker.groupId = "temporary-family-a-group"
FlockSearch.update(groupedSeeker, origin, {
	{ entity = otherFamily, position = { cellX = 1, cellY = 0 }, perceived = true }
}, 402)
assertEquals(groupedSeeker.ecology.family, originalFamily, "transient association must not rewrite persistent family identity")

local hiddenFamilySeeker = makeEntity("hidden", "B")
local hidden = FlockSearch.update(hiddenFamilySeeker, origin, {
	{ entity = ownFamily, position = { cellX = 30, cellY = 17 } }
}, 400)
assertEquals(hidden.targetEntityId, nil, "family identity alone must not create an omniscient pursuit target")
assertEquals(hidden.cuePosition, nil, "unusable family information must not expose live coordinates")

local signalSeeker = makeEntity("signal", "B")
local signalRelationships = signalSeeker.relationships
local signal = FlockSearch.update(signalSeeker, origin, {
	{ entity = ownFamily, position = { cellX = 10, cellY = 3 } }
}, 400)
assertEquals(signal.cueSource, "social_signal", "long-range compatible entities should create coarse social cues")
assertEquals(signal.cueDirection, "RIGHT", "coarse acquisition should expose only a cardinal direction")
assertEquals(signal.cuePosition.cellX, 6, "coarse acquisition must sample a search point rather than expose the live tile")
assertEquals(signalSeeker.memory, nil, "coarse social acquisition must not create perception events")
assertEquals(signalSeeker.relationships, signalRelationships, "coarse social acquisition must not create relationships")

local rememberedSeeker = makeEntity("remembered", "B")
FlockSearch.update(rememberedSeeker, origin, {
	{ entity = ownFamily, position = { cellX = 4, cellY = 0 }, perceived = true }
}, 10)
local remembered = FlockSearch.update(rememberedSeeker, origin, {
	{ entity = ownFamily, position = { cellX = 9, cellY = 0 } }
}, 120)
assertEquals(remembered.cueSource, "last_seen", "recent perception should outrank a coarse social signal")
assertEquals(remembered.cuePosition.cellX, 4, "last-seen search must not use the unseen target's live coordinate")
local despawnedRemembered = FlockSearch.update(rememberedSeeker, origin, {}, 121)
assertEquals(despawnedRemembered.targetEntityId, ownFamily.id, "recent sightings should survive disposal of the target avatar")
assertEquals(despawnedRemembered.cuePosition.cellX, 4, "disposed avatars must retain only the sampled last-known position")

local lowIndependence = makeEntity("dependent", "B", 0.1)
FlockSearch.update(lowIndependence, origin, {}, 0)
local dependentResult = FlockSearch.update(lowIndependence, origin, {}, 400)
assertEquals(dependentResult.utility > 50, true, "isolated low-independence flockers should develop strong search pressure")

local highIndependence = makeEntity("independent", "B", 0.95)
FlockSearch.update(highIndependence, origin, {}, 0)
local independentResult = FlockSearch.update(highIndependence, origin, {}, 400)
assertEquals(independentResult.utility < 10, true, "high independence should strongly suppress flock search")

local graceSeeker = makeEntity("grace", "B")
FlockSearch.update(graceSeeker, origin, {
	{ entity = ownFamily, position = { cellX = 1, cellY = 0 }, perceived = true }
}, 10)
local graceResult = FlockSearch.update(graceSeeker, origin, {}, 50)
assertEquals(graceResult.utility, 0, "brief separation should remain inside the isolation grace period")

return true