local EcologyClock = require("src.time.ecology_clock")
local CircadianSystem = require("src.circadian.circadian_system")
local Drives = require("src.needs.drives")
local DormantCohort = require("src.dormant.dormant_cohort")
local HomeArea = require("src.world.home_area")

local EcologyInspector = {}

function EcologyInspector.actor(entity, clockSample, simulationTick)
	local phase = clockSample and clockSample.phase or 0
	local runtime = entity and entity.runtimeState or {}
	local location = entity and entity.locationState or {}
	local selected = runtime.restSiteSelection and runtime.restSiteSelection.selected
	local anchor = location.anchorCell or {}
	local home = entity and entity.home and entity.home.area or {}
	local homePosition, homeMapId = HomeArea.position(entity,
		runtime.goalSelfPosition)
	local homeDistance = HomeArea.distance(entity, homePosition, homeMapId)
	local homeDestination = runtime.homeReturnDestination or {}
	return table.concat({
		EcologyClock.inspect(clockSample or {
			source = "UNKNOWN", phase = phase, band = "UNKNOWN", dayIndex = 0
		}),
		CircadianSystem.inspect(entity, phase),
		Drives.inspect(entity, simulationTick),
		string.format(
			"HOME established=%s map=%s anchor=%s,%s radius=%s inside=%s distance=%s score=%.2f active=%s destination=%s,%s provenance=%s",
			tostring(entity and entity.home and entity.home.area ~= nil),
			tostring(home.mapId or "NONE"),
			tostring(home.anchorCell and home.anchorCell.cellX or "NONE"),
			tostring(home.anchorCell and home.anchorCell.cellY or "NONE"),
			tostring(home.radius or "NONE"),
			tostring(HomeArea.isInside(entity, homePosition, homeMapId)),
			tostring(homeDistance or "NONE"),
			runtime.behaviorScores and runtime.behaviorScores.RETURN_HOME or 0,
			tostring(runtime.state == "RETURN_HOME"),
			tostring(homeDestination.cellX or "NONE"),
			tostring(homeDestination.cellY or "NONE"),
			tostring(home.provenance or "NONE")),
		string.format(
			"REST motivated=%s context=%s candidates=%d budget=%d resting=%s selected=%s",
			tostring(runtime.state == "REST"),
			tostring(runtime.currentRestContext or "NONE"),
			runtime.restCandidateCount or 0, runtime.restTravelBudget or 0,
			tostring(runtime.restingActive == true),
			selected and string.format("%s:%s,%s", selected.semanticType,
				selected.cellX, selected.cellY) or "NONE"),
		string.format(
			"CONCEALMENT state=%s type=%s anchor=%s,%s awareness=%s avatar=%s cue=%s",
			tostring(location.kind or "VISIBLE"),
			tostring(location.concealmentType or "NONE"),
			tostring(anchor.cellX or "NONE"), tostring(anchor.cellY or "NONE"),
			tostring(location.awareness or "AWAKE"),
			tostring(location.kind ~= "CONCEALED"),
			tostring(runtime.concealmentCue or "NONE"))
	}, "\n")
end

function EcologyInspector.cohort(cohort, clockSample)
	local now = clockSample and clockSample.monotonicEcologyTime or 0
	local catchUp = cohort and cohort.lastCatchUp or {}
	return table.concat({
		EcologyClock.inspect(clockSample or {
			source = "UNKNOWN", phase = 0, band = "UNKNOWN", dayIndex = 0
		}),
		DormantCohort.inspect(cohort, now),
		string.format(
			"LAST CATCHUP elapsed=%.0f segments=%d drives=%d social=%d pairs=%d/%d",
			catchUp.elapsed or 0, catchUp.segments or 0,
			catchUp.driveUpdates or 0, catchUp.socialUpdates or 0,
			catchUp.pairCandidates or 0,
			catchUp.totalPossibleDirectedPairs or 0)
	}, "\n")
end

return EcologyInspector