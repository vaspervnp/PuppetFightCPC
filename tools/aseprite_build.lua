-- Build an editable .aseprite file for one character from art/sprites.
--
-- Run with Aseprite (batch or via the Aseprite MCP run_lua_script):
--   aseprite -b --script-param repo=<repo> --script-param char=trump --script tools/aseprite_build.lua
--
-- The canvas is 64x64 so wide (falling) frames fit; normal 32-wide frames sit
-- at x=16, which matches their offset_x of 0 against the wide frames' -16.
-- One tag per move. The sprite is indexed with the CPC game palette, pen 0
-- transparent.

local repo = app.params["repo"] or PF_REPO  -- PF_* globals: set when run from the MCP
local char = app.params["char"] or PF_CHAR
local sep = package.config:sub(1, 1)
local function path(...) return table.concat({ repo, ... }, sep) end

local f = assert(io.open(path("art", "sprites", char .. ".json"), "r"))
local tbl = json.decode(f:read("a"))
f:close()

local spr = Sprite(64, tbl.height, ColorMode.INDEXED)
local pal = Palette(16)
for i, hex in ipairs(tbl.palette) do
  local n = tonumber(hex:sub(2), 16)
  pal:setColor(i - 1, Color{ r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255 })
end
spr:setPalette(pal)
spr.transparentColor = 0
spr.layers[1].name = char

local fps_ms = 83 -- 12 fps
local frameNo = 1
local ranges = {}
for _, move in ipairs(tbl.moves) do
  local from = frameNo
  for _, fr in ipairs(move.frames) do
    if frameNo > 1 then spr:newEmptyFrame(frameNo) end
    local img = Image{ fromFile = path("art", "sprites", char, fr.file .. ".png") }
    local x = 16 + fr.offset_x
    spr:newCel(spr.layers[1], frameNo, img, Point(x, 0))
    spr.frames[frameNo].duration = fps_ms / 1000
    frameNo = frameNo + 1
  end
  ranges[#ranges + 1] = { move.name, from, frameNo - 1 }
end
-- tags last: frames appended inside an existing tag would stretch it
for _, r in ipairs(ranges) do
  local tag = spr:newTag(r[2], r[3])
  tag.name = r[1]
end

spr:saveAs(path("art", "sprites", char .. ".aseprite"))
print(char .. ": " .. (frameNo - 1) .. " frames, " .. #spr.tags .. " tags")
