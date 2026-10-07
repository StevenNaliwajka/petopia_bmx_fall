-- Export a map's city layout as JSON, for tools/city/preview.py.
--   lua5.1 tools/city/export.lua gm_skatepark > layout.json
-- Runs the real sh_city.lua / sh_city_maps.lua with just enough of GMod
-- stubbed for them to load: the builder itself is plain Lua.
SERVER, CLIENT = false, true
bit = { bor = function(...) return 0 end }
game = { GetMap = function() return arg[1] or "gm_skatepark" end }
local root = (arg[0]:match("^(.*)/tools/city/") or ".") .. "/lua/"
dofile(root .. "petopia_bmx_fall/sh_city.lua")
dofile(root .. "petopia_bmx_fall/sh_city_maps.lua")
local L = BMX.City.Build(BMX.City.Maps[arg[1] or "gm_skatepark"])
local out = {}
local function w(s) out[#out + 1] = s end
local function num(x) return string.format("%.3f", x) end
w('{"materials":{')
local first = true
for k, m in pairs(BMX.City.Materials) do
    if not first then w(",") end first = false
    w(string.format('"%s":{"tex":"%s","alpha":%s', k, m.tex, m.alpha and "true" or "false"))
    if m.color then w(string.format(',"color":[%s,%s,%s]', num(m.color[1]), num(m.color[2]), num(m.color[3]))) end
    w("}")
end
w('},"faces":{')
first = true
for mat, list in pairs(L.faces) do
    if not first then w(",") end first = false
    w('"' .. mat .. '":[')
    for i, q in ipairs(list) do
        local t = {}
        for j = 1, 17 do t[j] = num(q[j]) end
        w((i > 1 and "," or "") .. "[" .. table.concat(t, ",") .. "]")
    end
    w("]")
end
w('},"lines":[')
for i, l in ipairs(L.lines) do
    w((i > 1 and "," or "") .. string.format('{"axis":"%s","at":%s,"from":%s,"to":%s,"deck":%s}', l.axis, num(l.at), num(l.from), num(l.to), num(l.deck)))
end
w('],"signs":[')
for i, s in ipairs(L.signs) do
    -- not every sign has text (a station sign reads its line) or a colour
    -- (an ad has its own palette): the preview gets a name and a grey
    local c = s.color or s.bg or { 128, 128, 128 }
    local text = (s.text or s.metro or s.look or "sign"):gsub('[\\"]', "")
    local face = s.face or s.pos
    w((i > 1 and "," or "") .. string.format('{"text":"%s","pos":[%s,%s,%s],"normal":[%s,%s,%s],"w":%s,"h":%s,"color":[%d,%d,%d]}',
        text, num(face[1]), num(face[2]), num(face[3]), num(s.normal[1]), num(s.normal[2]), num(s.normal[3] or 0),
        num(s.fw or s.w), num(s.fh or s.h), c[1], c[2], c[3]))
end
w('],"quads":' .. L.quads .. ',"buildings":' .. #L.buildings .. '}')
io.write(table.concat(out))
