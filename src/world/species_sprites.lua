-- Registers one overworld sprite per known species, reusing that species'
-- already-imported battle front art from the `pokemon` registry -- no new
-- art assets needed. Same approach verified against the reference mod
-- "Wilds of Kanto" (YoDrehDenSwagAuf/overworld-spawn-mod docs/DEVELOPER_
-- GUIDE.md: "SPRITE_OW_WILD_<SPECIES> per mod.content.pokemon entry
-- (battle front or fallback)", "Pre-register all species sprites at
-- load", "No registry writes after load").
local DebugLogger = require("src.debug.logger")
local Quantizer = require("src.world.sprite_quantizer")

local SpeciesSprites = {}

-- Shares main.lua's "dev_log_generation" LOG SETTINGS toggle so registration
-- diagnostics show up alongside the other generation logs, gated the same
-- way (mod.save-backed, see generator.lua's generationLogEnabled).
local GENERATION_LOG_OPTION_KEY = "dev_log_generation"

local function generationLogEnabled(mod)
  local save = mod and mod.save
  if save and save.get then
    local ok, value = pcall(function()
      return save:get(GENERATION_LOG_OPTION_KEY, false)
    end)
    if ok then
      return value == true
    end
  end
  return false
end

local function logSprites(mod, message)
  if not generationLogEnabled(mod) then
    return
  end
  DebugLogger.log("generation", message)
end

local registeredSpriteIdBySpecies = {}
local walkerSourceBySpecies = {}
local bakeAttemptedBySpecies = {}
local lastDiagnostics = nil

local function spriteIdFor(speciesId)
  return "SPRITE_OW_WILD_" .. tostring(speciesId)
end

-- Imported offline by tools/build_ow_sprites.py from user-supplied sheets into
-- Gen1Recomp's native 16x96 6-frame walker format. The generated directory is
-- intentionally local and ignored by Git; missing files use spriteFront.
local function walkerSpritePath(dex)
  local dexNumber = tonumber(dex)
  if not dexNumber then
    return nil
  end
  return string.format("generated-assets/ow_sprites/%03d.png", dexNumber)
end

local function walkerCachePath(dex)
  return string.format("wild_ecology_ow_cache/%03d.png", tonumber(dex) or 0)
end

-- Entry-chunk only: gen1recomp freezes content registries after mod load,
-- so this must run once during WildEcology.start, never on a later spawn.
function SpeciesSprites.registerAll(mod)
  if not (mod and mod.content and mod.content.pokemon and mod.content.pokemon.each
    and mod.content.sprites and mod.content.sprites.register) then
    lastDiagnostics = { skipped = true, reason = "mod.content.pokemon/sprites unavailable" }
    logSprites(mod, "sprite registration SKIPPED: mod.content.pokemon or mod.content.sprites unavailable")
    return
  end

  local iterated, withWalkerSheet, withSpriteFront, registered = 0, 0, 0, 0
  local ok, err = pcall(function()
    for speciesId, record in mod.content.pokemon:each() do
      iterated = iterated + 1
      if not registeredSpriteIdBySpecies[speciesId] then
        local spriteId = spriteIdFor(speciesId)
        local walkerRelativePath = walkerSpritePath(record and record.dex)
        local walkerExists = walkerRelativePath and mod.info and mod:info(walkerRelativePath) ~= nil

        local registerOk, registerErr = false, nil
        if walkerExists then
          withWalkerSheet = withWalkerSheet + 1
          -- Runtime color quantization (love.image/love.filesystem-based
          -- baking) is DISABLED for now: it caused sprites to stop loading
          -- entirely, then a game crash, with no concrete error text to
          -- diagnose further. Register the plain unquantized sheet
          -- directly instead -- known to load correctly (just washed-out
          -- colors), which is strictly better than broken/crashed.
          local sourcePath = mod.assets:path(walkerRelativePath)
          registerOk, registerErr = pcall(mod.content.sprites.register, mod.content.sprites, spriteId, {
            image = sourcePath,
            frames = 6,
            frameWidth = 16,
            frameHeight = 16,
            walker = true,
            trueColor = true
          })
        elseif record and record.spriteFront then
          withSpriteFront = withSpriteFront + 1
          registerOk, registerErr = pcall(mod.content.sprites.register, mod.content.sprites, spriteId, {
            image = record.spriteFront,
            frames = 1,
            walker = false,
            trueColor = true
          })
        end

        if registerOk then
          registeredSpriteIdBySpecies[speciesId] = spriteId
          registered = registered + 1
        elseif registerErr then
          logSprites(mod, string.format("sprite register FAILED species=%s id=%s err=%s", tostring(speciesId), spriteId, tostring(registerErr)))
        end
      else
        registered = registered + 1
      end
    end
  end)

  lastDiagnostics = { skipped = false, ok = ok, err = err, iterated = iterated, withWalkerSheet = withWalkerSheet, withSpriteFront = withSpriteFront, registered = registered }
  if not ok then
    logSprites(mod, string.format("sprite registration loop ERRORED after %d entries: %s", iterated, tostring(err)))
  else
    logSprites(mod, string.format("sprite registration done: iterated=%d walkerSheets=%d spriteFrontFallback=%d registered=%d", iterated, withWalkerSheet, withSpriteFront, registered))
  end
end

-- Returns the registered overworld sprite id for a species, or nil if it
-- was never successfully registered (e.g. registerAll never ran, or that
-- species has no spriteFront) -- callers fall back to a generic default.
function SpeciesSprites.get(speciesId)
  return registeredSpriteIdBySpecies[speciesId]
end

-- Bakes the quantized cache copy for one species, ONCE, the first time
-- it's actually needed (e.g. right before that species spawns) -- not at
-- mod load for all ~810 registered species. Safe to call every spawn:
-- it's a cheap mod:info() existence check after the first successful (or
-- failed) attempt.
function SpeciesSprites.ensureBaked(mod, speciesId)
  local mapping = walkerSourceBySpecies[speciesId]
  if not mapping then
    return false, "no walker sheet registered for this species"
  end

  if mod and mod.info then
    local ok, info = pcall(mod.info, mod, mapping.cachePath)
    if ok and info ~= nil then
      return true
    end
  end

  if bakeAttemptedBySpecies[speciesId] then
    return false, "already attempted and failed"
  end
  bakeAttemptedBySpecies[speciesId] = true

  local bakedOk, bakeErr = Quantizer.bake(mapping.sourcePath, mapping.cachePath)
  if not bakedOk then
    logSprites(mod, string.format("sprite quantize FAILED species=%s, using unquantized source: %s", tostring(speciesId), tostring(bakeErr)))
  end
  return bakedOk, bakeErr
end

-- Last registerAll() outcome, for diagnostics/tests: { skipped, reason } or
-- { skipped=false, ok, err, iterated, withSpriteFront, registered }.
function SpeciesSprites.diagnostics()
  return lastDiagnostics
end

return SpeciesSprites
