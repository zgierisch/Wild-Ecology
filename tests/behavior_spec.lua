local Controller = require("src.behavior.controller")
local Relationships = require("src.entities.relationships")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local entity = { id = "wild:test:0001" }

local Utility = require("src.behavior.utility")
local TargetSelector = require("src.behavior.target_selector")

local targetEntity = {
	id = "wild:test:target",
	temperament = { curiosity = 1 },
	relationships = {
		player = { trust = 90, affinity = 70 }
	}
}
local chosenTarget, chosenScore = TargetSelector.choose(targetEntity, {
	{ id = "wild:test:far", distance = 5, novelty = 10 },
	{ id = "player", distance = 2, novelty = 1 }
}, { behavior = "APPROACH" })
if not chosenTarget then
	error("approach target selection should return a candidate")
end
assertEquals(chosenTarget.id, "player", "approach should choose the strongest trusted target")
assertEquals(chosenScore > 0, true, "target selection should return a useful score")

local scoredEntity = {
	id = "wild:test:scored",
	temperament = { curiosity = 1, sociability = 0, boldness = 0.5 }
}
local investigateScores = Controller.scoreBehaviors(scoredEntity, { trust = 0 }, {
	hasTarget = true,
	purposefulTarget = true,
	novelty = 50,
	allowTargeting = true
})
local investigateState = Utility.highestBehavior(investigateScores)
assertEquals(investigateState, "INVESTIGATE", "novel curious entities should prioritize investigation")

local noPurposeScores = Controller.scoreBehaviors({
	id = "wild:test:no-purpose",
	temperament = { curiosity = 1 }
}, {}, { hasTarget = false })
local noPurposeState = Utility.highestBehavior(noPurposeScores)
assertEquals(noPurposeState, "SETTLED", "a calm actor without a purposeful target should settle")
local visibleButDistantScores = Controller.scoreBehaviors({
	id = "wild:test:distant-player",
	temperament = { curiosity = 1 }
}, {}, { hasTarget = true, purposefulTarget = false })
assertEquals(Utility.highestBehavior(visibleButDistantScores), "SETTLED", "a visible but irrelevant target should not disturb equilibrium")

local settledEntity = {
	id = "wild:test:settled",
	runtimeState = {
		state = "SETTLED",
		targetEntityId = "stale",
		targetDestination = { cellX = 2, cellY = 2 },
		spatialGoal = { kind = "POSITION" },
		navigation = { ownerBehavior = "TARGET" },
		movementRequest = { direction = "RIGHT" }
	}
}
Controller.executeCurrentIntent(settledEntity, {
	position = { cellX = 1, cellY = 1 }, locomotionPacing = true
}, 1)
assertEquals(settledEntity.runtimeState.intent, "SETTLED",
	"SETTLED should be an explicit behavior outcome")
assertEquals(settledEntity.runtimeState.targetEntityId, nil,
	"SETTLED should own no entity target")
assertEquals(settledEntity.runtimeState.navigation, nil,
	"SETTLED should own no navigation episode")
assertEquals(settledEntity.runtimeState.movementRequest, nil,
	"SETTLED should emit no movement request")

local hysteresisEntity = { id = "wild:test:hysteresis", temperament = { curiosity = 1 } }
local hysteresisState = Controller.tick(hysteresisEntity, {}, nil, {
	hasTarget = true,
	novelty = 50
}, 1)
assertEquals(hysteresisState, "INVESTIGATE", "utility engine should select the highest-scoring behavior")
local heldState = Controller.tick(hysteresisEntity, {}, nil, {
	hasTarget = false,
	allowTargeting = false
}, 2)
assertEquals(heldState, "IDLE", "target loss should override minimum state duration")
local releasedState = Controller.tick(hysteresisEntity, {}, nil, {
	hasTarget = false,
	allowTargeting = false
}, 5)
assertEquals(releasedState, "IDLE", "target loss should remain idle after the transition")

local lostTargetEntity = { id = "wild:test:lost-target", temperament = { curiosity = 1 }, runtimeState = { state = "INVESTIGATE" } }
local lostTargetState = Controller.tick(lostTargetEntity, {}, nil, {
	hasTarget = false,
	position = { cellX = 4, cellY = 4 }
}, 20)
assertEquals(lostTargetState, "IDLE", "target-seeking behavior should exit immediately when its target is lost")

local actionEntity = { id = "wild:test:actions", temperament = { curiosity = 1 } }
local investigateAction = Controller.tick(actionEntity, {}, nil, {
	hasTarget = true,
	novelty = 50
}, 1)
assertEquals(investigateAction, "INVESTIGATE", "investigate should have a concrete state handler")
assertEquals(actionEntity.runtimeState.intent, "INVESTIGATE", "investigate handler should expose its intent")

-- Intent must track the CURRENT state, not just linger on the last
-- purposeful behavior; IDLE/FLEE previously never updated it.
local idleAfterInvestigate = Controller.tick(actionEntity, {}, nil, { hasTarget = false }, 2)
assertEquals(idleAfterInvestigate, "IDLE", "losing the target should return to idle")
assertEquals(actionEntity.runtimeState.intent, "IDLE", "idle handler should update intent instead of leaving it stale")

local fleeIntentEntity = { id = "wild:test:nearby-not-threat" }
local fleeIntentState = Controller.tick(fleeIntentEntity, nil, 1)
assertEquals(fleeIntentState, "ALERT", "close proximity without threat provenance should not trigger direct flee")
assertEquals(fleeIntentEntity.runtimeState.intent, "IDLE", "alert state should remain stationary without a direct threat")

local approachEntity = {
	id = "wild:test:approach",
	temperament = { curiosity = 1 },
	relationships = {}
}
local approachRelationship = { trust = 100, affinity = 100 }
local approachAction = Controller.tick(approachEntity, approachRelationship, nil, {
	hasTarget = true,
	novelty = 0,
	candidates = {
		{ id = "player", distance = 2, novelty = 0 }
	}
}, 1)
assertEquals(approachAction, "APPROACH", "trusted targets should select approach")
assertEquals(approachEntity.runtimeState.intent, "APPROACH", "approach handler should expose its intent")
assertEquals(approachEntity.runtimeState.targetEntityId, "player", "approach should retain the selected target ID")

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
local calmState = Controller.tick(entity, calmRelationship, 6)
assertEquals(calmState, "SETTLED", "high trust and low threat should select SETTLED")

local identifiedThreat = { primaryThreatId = "player", primaryThreatScore = 1, primaryThreatReason = "HOSTILITY" }
local fleeStateFar = Controller.tick(entity, fleeRelationship, 8, { threatAssessment = identifiedThreat })
assertEquals(fleeStateFar, "SETTLED", "an out-of-range threat should not disturb equilibrium")

local fleeState = Controller.tick(entity, fleeRelationship, 1, { threatAssessment = identifiedThreat }, 40)
assertEquals(fleeState, "FLEE", "higher threat than trust should select FLEE")

local lowTrustRadius = Utility.fleeRadius({ trust = 0, threatMemory = 20, hostility = 0 })
local highTrustRadius = Utility.fleeRadius({ trust = 80, threatMemory = 20, hostility = 0 })
assertEquals(highTrustRadius < lowTrustRadius, true, "higher trust should shrink the flee radius")

local closeFlee, closeRadius = Utility.shouldFleeAtDistance({ trust = 10, threatMemory = 20, hostility = 0 }, 2)
assertEquals(closeFlee, true, "close range should flee when threat outweighs trust")
assertEquals(closeRadius >= 1, true, "flee radius should remain valid")

local farSafe, farRadius = Utility.shouldFleeAtDistance({ trust = 10, threatMemory = 20, hostility = 0 }, 8)
assertEquals(farSafe, false, "far range should not flee when outside the radius")
assertEquals(farRadius >= 1, true, "flee radius should remain valid")

local trustDrivenFarSafe, trustDrivenRadius = Utility.shouldFleeAtDistance({ trust = 70, threatMemory = 20, hostility = 0 }, 4)
assertEquals(trustDrivenFarSafe, false, "higher trust should let the Pokémon tolerate closer approach")
assertEquals(trustDrivenRadius < closeRadius, true, "higher trust should reduce the flee radius")

local heterospecificFear = Utility.proximityFear({ trust = 10 }, 1, {}, false)
local conspecificFear = Utility.proximityFear({ trust = 10 }, 1, {}, true)
assertEquals(conspecificFear < heterospecificFear, true, "same-species closeness should not scale fear like an unfamiliar player does")

local rememberedState = Controller.tick({ id = "wild:test:no-relationship" }, nil, 6)
assertEquals(rememberedState, "SETTLED", "missing relationship should default to SETTLED")

local proximityFleeState = Controller.tick({ id = "wild:test:proximity" }, nil, 1)
assertEquals(proximityFleeState, "ALERT", "nearby presence alone should not create a direct threat")

local trustedProximityState = Controller.tick({ id = "wild:test:trusted-proximity" }, { trust = 90, threatMemory = 0, hostility = 0 }, 1)
assertEquals(trustedProximityState, "SETTLED", "high trust should preserve passive equilibrium at close range")

-- A curious, moderately-trusted Pokemon that gets forced into proximity
-- FLEE should stay there while the player remains close, instead of
-- flip-flopping back to APPROACH every tick (the exit check must use the
-- same full FLEE score, including proximity fear, as the entry check).
local oscillationEntity = { id = "wild:test:no-oscillation", temperament = { curiosity = 1 } }
local oscillationRelationship = { trust = 15, affinity = 50, threatMemory = 0, hostility = 1 }
local oscillationContext = {
	hasTarget = true,
	purposefulTarget = true,
	threatAssessment = identifiedThreat,
	currentFear = 0.6
}
local oscillationTick1 = Controller.tick(oscillationEntity, oscillationRelationship, 1, oscillationContext, 1)
assertEquals(oscillationTick1, "FLEE", "proximity fear should force flee despite curiosity and affinity")
local oscillationTick2 = Controller.tick(oscillationEntity, oscillationRelationship, 1, oscillationContext, 2)
assertEquals(oscillationTick2, "FLEE", "flee should persist while still crowded instead of oscillating back to approach")

-- Restlessness: standing idle for a while should eventually prompt ambient
-- wandering on its own, with no target and no explicit reason, instead of
-- freezing in IDLE forever. Start with a genuine transient IDLE episode
-- baseline so the test isolates elapsed-time utility.
local restlessEntity = {
	id = "wild:test:restless",
	temperament = { curiosity = 0, sociability = 0 },
	runtimeState = { state = "SETTLED", stateEnteredTick = 2 }
}
local wanderedOff = false
for tick = 3, 300 do
	local state = Controller.tick(restlessEntity, {}, nil, { hasTarget = false }, tick)
	if state == "TARGET" then
		wanderedOff = true
		break
	end
end
assertEquals(wanderedOff, true, "settled restlessness should eventually justify ambient wandering")

-- targetEntityId belongs exclusively to entity-directed behaviors
-- (APPROACH/INVESTIGATE/FLEE). While ambient TARGET is mid-step
-- (motion.active), the target selector may still propose a nearby entity
-- that tick; targetEntityId must stay nil and the ambient destination must
-- be left untouched rather than leaking that entity's ID into the display.
local wanderingEntity = {
	id = "wild:test:wandering-motion",
	temperament = { curiosity = 0 },
	runtimeState = { state = "SETTLED", stateEnteredTick = -300 }
}
Controller.tick(wanderingEntity, {}, nil, { hasTarget = false, position = { cellX = 5, cellY = 5 } }, 1)
assertEquals(wanderingEntity.runtimeState.state, "TARGET", "should be ambiently wandering")
assertEquals(wanderingEntity.runtimeState.targetEntityId, nil, "ambient wandering should not claim an entity target")
local destinationBeforeMotion = wanderingEntity.runtimeState.targetDestination

wanderingEntity.runtimeState.motion = { active = true }
Controller.tick(wanderingEntity, {}, nil, {
	position = { cellX = 5, cellY = 5 },
	targetEntityId = "wild:test:other-nearby-pokemon",
	candidates = { { id = "wild:test:other-nearby-pokemon", distance = 1, novelty = 0 } },
	hasTarget = true
}, 2)
assertEquals(wanderingEntity.runtimeState.state, "TARGET", "should remain ambiently wandering")
assertEquals(wanderingEntity.runtimeState.targetEntityId, nil, "a nearby entity proposed mid-step must not leak into targetEntityId")
assertEquals(wanderingEntity.runtimeState.targetDestination, destinationBeforeMotion, "the ambient destination should be untouched while a step is in flight")

local lowTrustRadius = Utility.fleeRadius({ trust = 0, threatMemory = 0, hostility = 0 })
local highTrustRadius = Utility.fleeRadius({ trust = 80, threatMemory = 0, hostility = 0 })
assertEquals(highTrustRadius < lowTrustRadius, true, "higher trust should shrink the flee radius")

local fleeNear, nearRadius = Utility.shouldFleeAtDistance({ trust = 10, threatMemory = 10, hostility = 0 }, 2)
assertEquals(fleeNear, true, "close range should flee when score exceeds trust")
assertEquals(nearRadius >= 1, true, "flee radius should always be valid")

local fleeFar, farRadius = Utility.shouldFleeAtDistance({ trust = 10, threatMemory = 10, hostility = 0 }, 8)
assertEquals(fleeFar, false, "far range should not flee outside the radius")
assertEquals(farRadius >= 1, true, "flee radius should always be valid")

local bandNear, multiplierNear = Utility.distanceBand(2)
assertEquals(bandNear, "near", "distance 2 should be near")
assertEquals(multiplierNear, 1, "near distance should use full multiplier")

local bandMid, multiplierMid = Utility.distanceBand(5)
assertEquals(bandMid, "mid", "distance 5 should be mid")
assertEquals(multiplierMid > 0 and multiplierMid < 1, true, "mid distance should be reduced")

local bandFar, multiplierFar = Utility.distanceBand(8)
assertEquals(bandFar, "far", "distance 8 should be far")
assertEquals(multiplierFar > 0 and multiplierFar < multiplierMid, true, "far distance should be smaller than mid")

local bandOut, multiplierOut = Utility.distanceBand(9)
assertEquals(bandOut, "out", "distance above 8 should be out")
assertEquals(multiplierOut, 0, "out of range should have no effect")

local distance = Utility.chebyshevDistance({ cellX = 1, cellY = 2 }, { cellX = 4, cellY = 6 })
assertEquals(distance, 4, "chebyshev distance should use the larger axis delta")

local weightedDelta, deltaMultiplier = Utility.weightedDelta(10, 5)
assertEquals(deltaMultiplier, multiplierMid, "weighted delta should report the band multiplier")
assertEquals(weightedDelta < 10 and weightedDelta > 0, true, "weighted delta should be reduced at mid range")

local socialEntity = { id = "wild:test:0101", relationships = {} }
local socialPlayerRel = Relationships.getOrCreate(socialEntity, "player")
socialPlayerRel.trust = 8
socialPlayerRel.threatMemory = 0
socialPlayerRel.hostility = 0

local socialStateBefore = Controller.tick(socialEntity, socialPlayerRel)
assertEquals(socialStateBefore, "SETTLED", "low player threat should start in SETTLED")

local associateRel = Relationships.getOrCreate(socialEntity, "wild:ally:0001")
associateRel.trust = 100
associateRel.familiarity = 30

local updatedPlayerRel, socialThreatDelta = Relationships.applySocialFear(
	socialEntity,
	"wild:ally:0001",
	"player",
	100,
	12,
	0,
	2
)
assertEquals(socialThreatDelta > 0, true, "trusted associate fear should increase player threat memory")

local socialStateAfter = Controller.tick(socialEntity, updatedPlayerRel)
assertEquals(socialStateAfter, "SETTLED", "socially learned memory alone should not create a direct FLEE target")

local dependentSeeker = {
	id = "wild:test:seeker",
	species = "PIDGEY",
	ecology = { family = "B", socialModifier = 1.5 },
	rawStats = { independence = 0.1 },
	temperament = { sociability = 0.9, curiosity = 0 },
	relationships = {}
}
local seekContext = {
	hasTarget = false,
	position = { cellX = 2, cellY = 2 },
	mapId = "ROUTE_1",
	flockSearch = {
		utility = 100,
		isolationPressure = 1,
		nearbySameSpecies = 0,
		cueSource = "social_signal",
		cueDirection = "RIGHT",
		targetEntityId = "wild:test:family-b",
		cuePosition = { cellX = 8, cellY = 2 }
	}
}
local seekState = Controller.tick(dependentSeeker, {}, nil, seekContext, 400)
assertEquals(seekState, "SEEK_FLOCK", "isolated low-independence flockers should select SEEK_FLOCK")
assertEquals(dependentSeeker.runtimeState.intent, "SEEK_FLOCK", "SEEK_FLOCK should expose its own intent")
assertEquals(dependentSeeker.runtimeState.targetEntityId, "wild:test:family-b", "search should retain the real candidate identity")
assertEquals(dependentSeeker.runtimeState.navigation.goalKind, "DIRECTIONAL_REGION", "a coarse signal should become a directional navigation goal")
assertEquals(dependentSeeker.runtimeState.goalTargetPosition.cellX == 8, false, "a coarse signal must not become an exact hidden-coordinate target")

seekContext.threatAssessment = {
	primaryThreatId = "player",
	primaryThreatScore = 100,
	primaryThreatReason = "HIGH_SEVERITY_EVENT",
	primaryThreatSevere = true,
	primaryThreatDistance = 1
}
local fleeOverridesSeek = Controller.tick(dependentSeeker, {
	trust = 0,
	threatMemory = 100,
	hostility = 20
}, 1, seekContext, 401)
seekContext.threatAssessment = nil
assertEquals(fleeOverridesSeek, "FLEE", "a severe event must immediately override SEEK_FLOCK")

local reacquiringSeeker = {
	id = "wild:test:reacquire",
	species = "PIDGEY",
	ecology = { family = "B", socialModifier = 1.5 },
	rawStats = { independence = 0.1 },
	temperament = { sociability = 0.9, curiosity = 1 },
	relationships = {},
	runtimeState = { state = "SEEK_FLOCK", stateEnteredTick = 100 }
}
local reacquiredState = Controller.tick(reacquiringSeeker, {}, 3, {
	hasTarget = true,
	purposefulTarget = true,
	conspecific = true,
	position = { cellX = 2, cellY = 2 },
	targetEntityId = "wild:test:family-b-near",
	candidates = { { id = "wild:test:family-b-near", distance = 3, novelty = 100 } },
	targetPositions = { ["wild:test:family-b-near"] = { cellX = 5, cellY = 2 } },
	flockSearch = {
		utility = 0,
		isolationPressure = 0,
		nearbySameSpecies = 1,
		reacquired = true,
		cueSource = "perceived",
		targetEntityId = "wild:test:family-b-near",
		cuePosition = { cellX = 5, cellY = 2 }
	}
}, 101)
assertEquals(reacquiredState, "INVESTIGATE", "ordinary local social behavior should take over after reacquisition")
assertEquals(reacquiringSeeker.runtimeState.intent, "INVESTIGATE", "reacquisition should stop the SEEK_FLOCK intent")

return true
