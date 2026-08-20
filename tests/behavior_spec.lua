local Controller = require("src.behavior.controller")
local Relationships = require("src.entities.relationships")

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

local socialEntity = { id = "wild:test:0101", relationships = {} }
local socialPlayerRel = Relationships.getOrCreate(socialEntity, "player")
socialPlayerRel.trust = 8
socialPlayerRel.threatMemory = 0
socialPlayerRel.hostility = 0

local socialStateBefore = Controller.tick(socialEntity, socialPlayerRel)
assertEquals(socialStateBefore, "IDLE", "low player threat should start in IDLE")

local associateRel = Relationships.getOrCreate(socialEntity, "wild:ally:0001")
associateRel.trust = 100
associateRel.familiarity = 30

local updatedPlayerRel, socialThreatDelta = Relationships.applySocialFear(
	socialEntity,
	"wild:ally:0001",
	"player",
	100,
	12
)
assertEquals(socialThreatDelta > 0, true, "trusted associate fear should increase player threat memory")

local socialStateAfter = Controller.tick(socialEntity, updatedPlayerRel)
assertEquals(socialStateAfter, "FLEE", "socially learned threat should switch behavior to FLEE")

return true
