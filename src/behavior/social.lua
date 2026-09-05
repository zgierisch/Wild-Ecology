local Social = {}
local Relationships = require("src.entities.relationships")
local Config = require("src.core.config")
local SpeciesEcology = require("src.species.species_ecology")
local contactSink = nil

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

function Social.shouldFollowAssociate(rel)
  if not rel then
    return false
  end
  return (rel.trust or 0) >= 40 and (rel.affinity or 0) >= 20
end

function Social.setContactSink(sink)
  contactSink = type(sink) == "function" and sink or nil
end

function Social.observeNearby(entity, associateId, distance, nowTick, associateEntity)
  local relationship = Relationships.getOrCreate(entity, associateId)
  local tick = nowTick or 0
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.relationshipContacts =
    entity.runtimeState.relationshipContacts or {}
  local contacts = entity.runtimeState.relationshipContacts
  local contact = contacts[associateId]
  local settings = Config.relationships or {}
  local separationTicks = settings.contactSeparationTicks or 30
  local exposureIntervalTicks = settings.contactExposureIntervalTicks or 100
  local newEpisode = not contact
    or tick - (contact.lastContactTick or tick) > separationTicks
  if newEpisode then
    contact = {
      episodeId = (contact and contact.episodeId or 0) + 1,
      startTick = tick,
      lastContactTick = tick,
      lastExposureTick = nil,
      socialNearbyCount = 0,
      exposureCount = 0
    }
    contacts[associateId] = contact
  end
  contact.lastContactTick = tick
  contact.socialNearbyCount = contact.socialNearbyCount + 1
  local applyExposure = contact.lastExposureTick == nil
    or tick - contact.lastExposureTick >= exposureIntervalTicks
  if not applyExposure then
    if contactSink then
      contactSink({
        observerId = entity.id,
        subjectId = associateId,
        tick = tick,
        distance = distance,
        episodeId = contact.episodeId,
        episodeStartTick = contact.startTick,
        socialNearbyCount = contact.socialNearbyCount,
        exposureCount = contact.exposureCount,
        newEpisode = newEpisode,
        exposureApplied = false,
        relationship = Relationships.snapshot(relationship),
        relationshipRef = relationship,
        observer = entity,
        subject = associateEntity
      })
    end
    return relationship, false, contact
  end

  local before = Relationships.snapshot(relationship)

  local identityEcology = entity.ecology or {}
  local speciesEcology = SpeciesEcology.getResolved(entity.species)
  local socialModifier = speciesEcology.social.modifier
  local familyModifier = 1
  if associateEntity and associateEntity.species == entity.species
    and associateEntity.ecology and identityEcology.family
    and associateEntity.ecology.family == identityEcology.family then
    familyModifier = speciesEcology.social.familyModifier
  end
  local familiarityGain = socialModifier * familyModifier
  local affinityGain = (distance <= 2 and 1 or 0.25) * socialModifier * familyModifier
  relationship.familiarity = clamp((relationship.familiarity or 0) + familiarityGain, 0, 100)
  relationship.affinity = clamp((relationship.affinity or 0) + affinityGain, -100, 100)
  relationship.lastSeenTick = tick
  relationship.importance = math.max(relationship.importance or 0.1, 0.2)
  contact.lastExposureTick = tick
  contact.exposureCount = contact.exposureCount + 1
  if contactSink then
    contactSink({
      observerId = entity.id,
      subjectId = associateId,
      tick = tick,
      distance = distance,
      episodeId = contact.episodeId,
      episodeStartTick = contact.startTick,
      socialNearbyCount = contact.socialNearbyCount,
      exposureCount = contact.exposureCount,
      newEpisode = newEpisode,
      exposureApplied = true,
      relationship = Relationships.snapshot(relationship),
      relationshipRef = relationship,
      observer = entity,
      subject = associateEntity
    })
  end
  Relationships.recordMutation(entity, associateId, "SOCIAL_NEARBY", before,
    relationship, tick, "src.behavior.social.observeNearby", {
      contactEpisodeId = contact.episodeId,
      contactEpisodeStartTick = contact.startTick,
      contactExposureIndex = contact.exposureCount,
      contactKind = newEpisode and "EPISODE_START" or "CONTINUOUS_EXPOSURE"
    })
  return relationship, true, contact
end

return Social
