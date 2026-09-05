local Perception = require("src.world.perception")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local observer = { id = "wild:route01:0001" }
local player = { id = "player", kind = "trainer" }
local associate = { id = "wild:route01:0002", kind = "pokemon" }

local firstObservation = Perception.observe(observer, {
		{ name = Perception.EVENTS.ENTITY_SEEN, target = player },
		{ name = Perception.EVENTS.ENTITY_NEAR, target = associate }
	}, 10)

assertEquals(#firstObservation.events, 2, "perception should retain all valid generic observations")
assertEquals(firstObservation.relationships[player.id] ~= nil, true, "player should use the generic relationship path")
assertEquals(firstObservation.relationships[associate.id], nil,
	"level-triggered nearness alone should not allocate persistent relationship state")
assertEquals(observer.relationships[player.id].familiarity, 1, "seeing an entity should increase familiarity")
assertEquals(observer.relationships[associate.id], nil,
	"level-triggered nearness should remain a perception fact")
assertEquals(observer.memory.events[1].event, Perception.EVENTS.ENTITY_SEEN, "perception should record the event")
assertEquals(observer.memory.events[1].t, 10, "perception should record the simulation tick")
assertEquals(observer.memory.events[1].payload.targetEntityId, player.id, "perception should persist the target entity ID")
assertEquals(observer.memory.events[1].payload.target, nil, "perception should not persist runtime target objects")

Perception.observe(observer, {
		{ name = Perception.EVENTS.ENTITY_APPROACHING, target = player, threatDelta = 3 },
		{ name = Perception.EVENTS.ENTITY_FLED, target = associate }
}, 11)

assertEquals(observer.runtimeState.perceivedFear[player.id], 3, "approaching events should update transient perceived fear")
assertEquals(observer.relationships[associate.id].threatMemory, 2, "fled events should update target threat memory")
assertEquals(observer.relationships[player.id].threatMemory, 0, "a generic approach should not create persistent threat identity")

Perception.observe(observer, {
		{ name = Perception.EVENTS.ENTITY_ATTACKED, target = player, threatDelta = 4 }
	}, 12)
assertEquals(observer.relationships[player.id].threatMemory, 4, "attacked events should update persistent threat memory")
assertEquals(observer.relationships[player.id].directThreatMemory, 4, "attacks should record explicit direct-threat provenance")
assertEquals(observer.runtimeState.directThreatEvidence[player.id].reason, "ENTITY_ATTACKED", "attacks should expose severe transient evidence")

for index = 1, 55 do
	Perception.observe(observer, {
			{ name = Perception.EVENTS.ENTITY_RESTING, target = associate }
		}, index + 11)
end
assertEquals(#observer.memory.events, 50, "perception memory should remain bounded")

-- A trusted friend rushing over shouldn't build lasting fear the way an
-- unfamiliar approach does.
local trustingObserver = { id = "wild:route01:0003" }
local friend = { id = "wild:route01:0004", kind = "pokemon" }
trustingObserver.relationships = { [friend.id] = { trust = 90, familiarity = 0, affinity = 0, threatMemory = 0, hostility = 0, lastSeenTick = 0, importance = 0.1 } }
Perception.observe(trustingObserver, {
		{ name = Perception.EVENTS.ENTITY_APPROACHING, target = friend, threatDelta = 3 }
	}, 1)
assertEquals(trustingObserver.relationships[friend.id].threatMemory, 0, "a trusted associate's approach should not become lasting threat")

return true