-- Export every frame of art/sprites/<char>.aseprite back to
-- art/sprites/<char>/<move>_<n>.png, so hand edits made in Aseprite flow into
-- the CPC data (tools/cpc_export.py reads those PNGs).
--
--   aseprite -b --script-param repo=<repo> --script-param char=trump --script tools/aseprite_export.lua
--
-- Frame widths/offsets come from art/sprites/<char>.json: a normal frame is
-- the 32 columns starting at x=16, a wide frame is the full 64.

local repo = app.params["repo"] or PF_REPO  -- PF_* globals: set when run from the MCP
local char = app.params["char"] or PF_CHAR
local sep = package.config:sub(1, 1)
local function path(...) return table.concat({ repo, ... }, sep) end

local f = assert(io.open(path("art", "sprites", char .. ".json"), "r"))
local tbl = json.decode(f:read("a"))
f:close()

local spr = app.open(path("art", "sprites", char .. ".aseprite"))
local frameNo = 1
for _, move in ipairs(tbl.moves) do
  for _, fr in ipairs(move.frames) do
    local full = Image(spr.spec)
    full:clear(0)
    full:drawSprite(spr, frameNo)
    local x = 16 + fr.offset_x
    local out = Image(fr.width, spr.height, ColorMode.INDEXED)
    out:clear(0)
    out:drawImage(full, Point(-x, 0))
    out:saveAs{ filename = path("art", "sprites", char, fr.file .. ".png"), palette = spr.palettes[1] }
    frameNo = frameNo + 1
  end
end
spr:close()
print(char .. ": exported " .. (frameNo - 1) .. " frames")
