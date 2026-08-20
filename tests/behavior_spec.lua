local Controller = require("src.behavior.controller")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local entity = { id = "wild:test:0001" }

local calmRelationship = {
	trust = 10,
	threatMemory = 0,
	hostility = 0
}

local fleeRelationship = {
	trust = 2,
	threatMemory = 2,
	hostility = 1
}

local calmState = Controller.tick(entity, calmRelationship)
assertEquals(calmState, "IDLE", "high trust and low threat should select IDLE")

local fleeState = Controller.tick(entity, fleeRelationship)
assertEquals(fleeState, "FLEE", "higher threat than trust should select FLEE")

local rememberedState = Controller.tick(entity, nil)
assertEquals(rememberedState, "IDLE", "missing relationship should default to IDLE")

return true
