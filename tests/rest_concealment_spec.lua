package.path = package.path .. ";./?.lua;./?/init.lua"

local Concealment = require("src.world.concealment")
local Controller = require("src.behavior.controller")
local Disturbance = require("src.world.disturbance")
local Emergence = require("src.world.emergence")
local Entity = require("src.entities.entity")
local RestSiteResolver = require("src.needs.rest_site_resolver")
local RuntimeState = require("src.core.runtime_state")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEquals failed") .. ": expected "
      .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "expected truthy value") end
end

local function actor(id, species, seed)
  local entity = Entity.newWildPokemon({ id = id, species = species,
    level = 4, personalitySeed = seed or 1, firstEncounteredTick = 0 })
  entity.runtimeState = { state = "SETTLED", stateEnteredTick = 0,
    motion = { active = false }, rejectedMoves = {} }
  return entity
end

local function map(id, rows, grassCells)
  local cells = {}
  for _, cell in ipairs(grassCells or {}) do
    cells[WorldSemantics.cellKey(cell.cellX, cell.cellY)] = {
      terrain = "TALL_GRASS", grass = true, walkable = true,
      validLanding = true, cover = "HIGH"
    }
  end
  return WorldSemantics.fromOverview({ mapId = id, width = #rows[1],
    height = #rows, rows = rows }, { cells = cells })
end

local function context(semantics, position)
  return {
    ecologyPhase = 0,
    hasTarget = false,
    allowTargeting = false,
    position = position,
    mapId = semantics.mapId,
    targetPositions = {},
    candidates = {},
    occupiedCells = {},
    currentOccupiedCells = {},
    occupancyDetails = {},
    worldSemantics = semantics,
    locomotionPacing = true
  }
end

local grassMap = map("REST_GRASS", { "....." }, {
  { cellX = 1, cellY = 0 }, { cellX = 3, cellY = 0 }
})

RestSiteResolver.resetScanCount()
local calm = actor("calm", "RATTATA", 1)
calm.drives.FATIGUE.value = 0.1
calm.drives.FATIGUE.lastUpdatedTick = 0
assertEquals(Controller.tick(calm, {}, nil,
  context(grassMap, { cellX = 0, cellY = 0 }), 31), "SETTLED",
  "excellent cover must not create REST motivation")
assertEquals(RestSiteResolver.getScanCount(), 0,
  "low fatigue must not trigger a rest-site scan")

local currentGrass = actor("current-grass", "RATTATA", 2)
currentGrass.drives.FATIGUE.value = 0.82
currentGrass.drives.FATIGUE.lastUpdatedTick = 0
assertEquals(Controller.tick(currentGrass, {}, nil,
  context(grassMap, { cellX = 1, cellY = 0 }), 31), "REST",
  "motivated actor on acceptable current cover should REST")
assertEquals(currentGrass.runtimeState.restTraveling, false,
  "acceptable current cell should avoid movement")
assertTrue(currentGrass.runtimeState.concealmentRequest ~= nil,
  "compatible current grass should request concealed rest")

local traveler = actor("traveler", "RATTATA", 3)
traveler.drives.FATIGUE.value = 0.79
traveler.drives.FATIGUE.lastUpdatedTick = 0
assertEquals(Controller.tick(traveler, {}, nil,
  context(grassMap, { cellX = 0, cellY = 0 }), 31), "REST",
  "fatigue should select REST before site choice")
assertEquals(traveler.runtimeState.restTraveling, true,
  "a worthwhile nearby grass site should produce REST travel")
assertEquals(traveler.runtimeState.navigation.ownerBehavior, "REST",
  "REST travel should use generic NavigationExecution ownership")
assertEquals(traveler.runtimeState.movementRequest.direction, "RIGHT",
  "generic WALK navigation should approach the selected site")
assertEquals(traveler.runtimeState.restingActive, false,
  "fatigue recovery must not begin while traveling")
traveler.runtimeState.motion.justCompleted = true
Controller.tick(traveler, {}, nil,
  context(grassMap, { cellX = 1, cellY = 0 }), 32)
assertEquals(traveler.runtimeState.restingActive, true,
  "arrival through generic navigation should begin actual REST")
assertTrue(traveler.runtimeState.concealmentRequest ~= nil,
  "arrival at selected grass should request concealment")

local unsupported = actor("unsupported", "MAGNEMITE", 4)
unsupported.drives.FATIGUE.value = 0.8
unsupported.drives.FATIGUE.lastUpdatedTick = 0
assertEquals(Controller.tick(unsupported, {}, nil,
  context(grassMap, { cellX = 0, cellY = 0 }), 31), "REST",
  "unsupported species must still be able to rest")
assertEquals(unsupported.runtimeState.restTraveling, false,
  "unsupported species must visibly rest in place instead of seeking grass")
assertEquals(unsupported.runtimeState.concealmentRequest, nil,
  "unsupported species must not hide in grass")

local exhausted = actor("exhausted", "RATTATA", 5)
exhausted.drives.FATIGUE.value = 0.95
exhausted.drives.FATIGUE.lastUpdatedTick = 0
Controller.tick(exhausted, {}, nil,
  context(grassMap, { cellX = 0, cellY = 0 }), 31)
assertEquals(exhausted.runtimeState.restTravelBudget, 0,
  "extreme fatigue should eliminate discretionary travel")
assertEquals(exhausted.runtimeState.restTraveling, false,
  "extreme fatigue should rest locally")

local hidden = actor("persistent-hidden", "RATTATA", 6)
hidden.relationships.peer = { trust = 12, familiarity = 8, affinity = 3 }
hidden.drives.FATIGUE.value = 0.8
hidden.drives.FATIGUE.lastUpdatedTick = 10
local relationship = hidden.relationships.peer
local identity = hidden.id
Concealment.enter(hidden, {
  mapId = grassMap.mapId,
  concealmentType = "TALL_GRASS",
  anchorCell = { cellX = 1, cellY = 0 }
}, 10)
RuntimeState.reset(hidden)
assertTrue(Concealment.isConcealed(hidden, grassMap.mapId),
  "concealment should preserve local ecological presence")
assertEquals(hidden.id, identity, "concealment must preserve persistent identity")
assertEquals(hidden.relationships.peer, relationship,
  "concealment must preserve sparse relationship objects")
assertEquals(hidden.runtimeState.movementRequest, nil,
  "concealment reset must discard runtime movement")
local fatigueBefore = hidden.drives.FATIGUE.value
Concealment.updateRest(hidden, 100)
assertTrue(hidden.drives.FATIGUE.value < fatigueBefore,
  "concealed REST should use canonical fatigue recovery")

local weak = Disturbance.new({ kind = "ACTOR_MOVEMENT", intensity = 0.2,
  radius = 2, tick = 101, sourcePosition = { cellX = 1, cellY = 0 } })
local weakResponse = Concealment.respond(hidden, weak)
assertEquals(weakResponse.action, "REMAIN_ASLEEP",
  "weak disturbance may leave a concealed actor asleep")
assertEquals(hidden.locationState.awareness, "ASLEEP",
  "weak disturbance should not wake this actor")

local moderate = Disturbance.new({ kind = "ACTOR_MOVEMENT", intensity = 0.45,
  radius = 2, tick = 102, sourcePosition = { cellX = 1, cellY = 0 } })
local moderateResponse = Concealment.respond(hidden, moderate)
assertEquals(moderateResponse.action, "WAKE_HIDDEN",
  "moderate disturbance should wake without forcing emergence")
assertEquals(hidden.locationState.awareness, "AWAKE",
  "waking should be represented separately from emergence")
assertEquals(moderateResponse.requestEmergence, false,
  "wake-without-emergence should remain hidden")
assertTrue(moderateResponse.cue ~= nil,
  "disturbed concealed presence should expose a rustle cue")

local bold = actor("bold-battle", "RATTATA", 7)
bold.temperament.boldness = 1
Concealment.enter(bold, { mapId = grassMap.mapId,
  concealmentType = "TALL_GRASS", anchorCell = { cellX = 1, cellY = 0 } }, 1)
local sensitive = actor("sensitive-battle", "RATTATA", 8)
sensitive.temperament.boldness = 0
Concealment.enter(sensitive, { mapId = grassMap.mapId,
  concealmentType = "TALL_GRASS", anchorCell = { cellX = 1, cellY = 0 } }, 1)
local battle = Disturbance.new({ kind = "BATTLE", intensity = 0.32,
  radius = 3, tick = 2, sourcePosition = { cellX = 1, cellY = 0 } })
assertEquals(Concealment.respond(bold, battle).action, "REMAIN_ASLEEP",
  "battle disturbance must not automatically wake every actor")
local sensitiveBattle = Concealment.respond(sensitive, battle)
assertEquals(sensitiveBattle.action, "WAKE_HIDDEN",
  "contextual sensitivity should vary battle response")
assertTrue(sensitiveBattle.cue ~= nil,
  "battle disturbance may produce a grass cue")
assertEquals(next(sensitive.relationships), nil,
  "battle disturbance must not allocate relationships")

local strong = Disturbance.new({ kind = "BATTLE", intensity = 0.95,
  radius = 2, tick = 3, sourcePosition = { cellX = 1, cellY = 0 },
  threatening = true })
local strongResponse = Concealment.respond(sensitive, strong)
assertEquals(strongResponse.requestEmergence, true,
  "strong nearby battle disturbance may request emergence")
assertEquals(strongResponse.requestFlee, true,
  "severe threatening disturbance may hand off to existing FLEE")

local emergenceCell = Emergence.selectCell(sensitive, grassMap, {})
assertTrue(emergenceCell ~= nil,
  "legal bounded emergence should find a nearby playable cell")
local blocked = {}
for cellX = 0, 2 do
  blocked[WorldSemantics.cellKey(cellX, 0)] = true
end
assertEquals(Emergence.selectCell(sensitive, grassMap, blocked), nil,
  "blocked emergence should leave the actor concealed")
assertTrue(Concealment.isConcealed(sensitive),
  "failed emergence selection must not discard concealed presence")

return true