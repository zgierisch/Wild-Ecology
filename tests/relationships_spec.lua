local Relationships = require("src.entities.relationships")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local wildA = { id = "wild:a", relationships = {} }
local wildB = { id = "wild:b", relationships = {} }

local rel, applied = Relationships.observeCalmProximity(wildA, "player", 10, 3)
assertEquals(applied, true, "first calm proximity should apply")
assertEquals(rel.familiarity, 1, "familiarity should increase on first calm proximity")

local rel2, applied2 = Relationships.observeCalmProximity(wildA, "player", 11, 3)
assertEquals(applied2, false, "cooldown should block rapid trust farming")
assertEquals(rel2.familiarity, 1, "familiarity should not increase during cooldown")

local rel3, applied3 = Relationships.observeCalmProximity(wildA, "player", 14, 3)
assertEquals(applied3, true, "calm proximity should apply after cooldown")
assertEquals(rel3.familiarity, 2, "familiarity should increase after cooldown")

local relB = Relationships.getOrCreate(wildB, "player")
assertEquals(relB.familiarity, 0, "relationships are directional and sparse per entity")

return true
