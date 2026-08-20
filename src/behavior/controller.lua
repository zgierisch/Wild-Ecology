local Idle = require("src.behavior.states.idle")
local Flee = require("src.behavior.states.flee")
local Utility = require("src.behavior.utility")

local Controller = {}

local STATE_HANDLERS = {
  IDLE = Idle,
  FLEE = Flee
}

function Controller.chooseState(entity, playerRelationship)
  entity.runtimeState = entity.runtimeState or { state = "IDLE" }

  local rel = playerRelationship or {}
  local trust = rel.trust or 0
  local fleeScore = Utility.scoreFlee(rel)

  if fleeScore > trust then
    return "FLEE", fleeScore
  end

  return "IDLE", fleeScore
end

function Controller.tick(entity, playerRelationship)
  local state, fleeScore = Controller.chooseState(entity, playerRelationship)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.state = state
  entity.runtimeState.fleeScore = fleeScore

  local handler = STATE_HANDLERS[state] or Idle
  return handler.tick(entity)
end

return Controller
