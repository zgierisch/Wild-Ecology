-- Runtime color quantization: loads a source sprite's raw pixel data via
-- love.image, snaps each opaque pixel to the nearest color in a small
-- target palette, and bakes the result to a cache file. The SOURCE asset
-- (assets/ow_sprites/*.png) is never modified on disk -- only a derived
-- cache copy is written (once, at mod load) and registered instead.
local Quantizer = {}

-- Approximate 4-tone palette; tune once verified against the actual
-- in-game palette the player sees.
Quantizer.DEFAULT_PALETTE = {
  { 255, 255, 255 },
  { 173, 216, 172 },
  { 82, 138, 84 },
  { 20, 20, 20 }
}

local function nearestPaletteColor(r, g, b, palette)
  local best, bestDistance = palette[1], math.huge
  for _, color in ipairs(palette) do
    local dr, dg, db = r - color[1], g - color[2], b - color[3]
    local distance = dr * dr + dg * dg + db * db
    if distance < bestDistance then
      bestDistance = distance
      best = color
    end
  end
  return best
end

-- Quantizes the image at `sourcePath` (a LÖVE-loadable path, e.g.
-- mod.assets:path(...)) and writes the result to `cachePath` (a plain
-- LÖVE virtual path under the writable save area -- never an absolute
-- getSaveDirectory() path). Returns true on success, or false + a reason
-- string on any failure so the caller can fall back to the unquantized
-- source image instead of breaking mod load.
function Quantizer.bake(sourcePath, cachePath, palette)
  if not (love and love.image and love.filesystem) then
    return false, "love.image/love.filesystem unavailable"
  end

  local okData, imageData = pcall(love.image.newImageData, sourcePath)
  if not okData or not imageData then
    return false, "failed to load source image data: " .. tostring(imageData)
  end

  palette = palette or Quantizer.DEFAULT_PALETTE
  local okMap, mapErr = pcall(function()
    imageData:mapPixel(function(_x, _y, r, g, b, a)
      if a <= 0 then
        return r, g, b, a
      end
      local color = nearestPaletteColor(r * 255, g * 255, b * 255, palette)
      return color[1] / 255, color[2] / 255, color[3] / 255, a
    end)
  end)
  if not okMap then
    return false, "quantize failed: " .. tostring(mapErr)
  end

  local okEncode, fileData = pcall(function()
    return imageData:encode("png")
  end)
  if not okEncode or not fileData then
    return false, "encode failed: " .. tostring(fileData)
  end

  local okWrite, writeErr = pcall(function()
    return love.filesystem.write(cachePath, fileData:getString())
  end)
  if not okWrite or writeErr == false then
    return false, "write failed: " .. tostring(writeErr)
  end

  return true
end

return Quantizer
