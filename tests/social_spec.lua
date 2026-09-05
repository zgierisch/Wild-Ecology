local Social = require("src.behavior.social")

local flockingEntity = {
	id = "wild:route01:pidgey",
	species = "PIDGEY",
	ecology = { family = "A", socialModifier = 1.5, familySocialModifier = 1.25 },
	relationships = {}
}
local solitaryEntity = {
	id = "wild:route01:solitary",
	ecology = { socialModifier = 0.25 },
	relationships = {}
}
local sameFamilyEntity = {
	id = "wild:route01:pidgey2",
	species = "PIDGEY",
	ecology = { family = "A", socialModifier = 1.5, familySocialModifier = 1.25 },
	relationships = {}
}
flockingEntity.species = "PIDGEY"

local flockingRelationship = Social.observeNearby(flockingEntity, "wild:route01:associate", 2, 10, sameFamilyEntity)
local solitaryRelationship = Social.observeNearby(solitaryEntity, "wild:route01:associate", 2, 10)
if flockingRelationship.affinity <= solitaryRelationship.affinity then
	error("flocking species should gain stronger nearby affinity than solitary species")
end
if flockingRelationship.familiarity <= solitaryRelationship.familiarity then
	error("flocking species should gain stronger nearby familiarity than solitary species")
end

local unrelatedSpecies = {
	id = "wild:route01:rattata",
	species = "RATTATA",
	ecology = { family = "A", socialModifier = 0.65, familySocialModifier = 1.1 }
}
local unrelatedRelationship = Social.observeNearby(flockingEntity, unrelatedSpecies.id, 2, 11, unrelatedSpecies)
if unrelatedRelationship.affinity ~= 1.5 then
	error("different species should not receive the family modifier")
end
if flockingRelationship.affinity <= unrelatedRelationship.affinity then
	error("same-species family contact should be stronger than different-species contact")
end

local defaultEntity = { id = "wild:route01:default", relationships = {} }
local defaultNear = Social.observeNearby(defaultEntity, "wild:route01:associate", 2, 10)
if not defaultNear then
	error("nearby social observation should create a relationship")
end
if defaultNear.familiarity ~= 0.25 or defaultNear.affinity ~= 0.25 then
	error("unprofiled species should use the conservative social modifier")
end

local distant = Social.observeNearby(defaultEntity, "wild:route01:other", 5, 11)
if distant.affinity ~= 0.0625 then
	error("distant social contact should be weaker for conservative species")
end

return true