local Save = require("src.core.save")
local PopulationManager = require("src.population.manager")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local storedState = nil
local mockMod = {
	storage = {
		get = function(_)
			return storedState
		end,
		set = function(_, value)
			storedState = value
		end
	}
}

Save.init(mockMod)
local entityA = PopulationManager.getOrCreatePhase0Entity()
entityA.level = 5
Save.flush()

Save.init(mockMod)
local entityB = PopulationManager.getOrCreatePhase0Entity()
assertEquals(entityB.id, "wild:route01:0001", "phase 0 should recreate the same stable entity id")
assertEquals(entityB.level, 5, "entity should persist through storage roundtrip")

return true
