-- lua tools/lua/dump_waves.lua <level_full.lua> <first_equation_round> <last_round>
-- Prints the level's wave table (static rounds + equation rounds) as JSON.
Script = {Level = {}, Mode = {}}
Game = setmetatable({}, {__index = function() return function() return 0 end end})
dofile(arg[1])
local L = Script.Level
local function json(v)
  if type(v) == "table" then
    local out, n = {}, #v
    if n > 0 then
      for i = 1, n do out[#out + 1] = json(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, x in pairs(v) do out[#out + 1] = string.format("%q:%s", k, json(x)) end
    table.sort(out)
    return "{" .. table.concat(out, ",") .. "}"
  end
  return tostring(v)
end
local waves = L.BuildWaveTableFull and L.BuildWaveTableFull() or {}
local eq = L.ZombieWaveEquationFull or L.ZombieWaveEquation
for r = #waves + 1, tonumber(arg[3]) do waves[r] = eq(r) end
print(json(waves))
