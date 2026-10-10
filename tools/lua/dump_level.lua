-- lua tools/lua/dump_level.lua <shared_dir> <level.lua>
-- Runs a level script's Setup/Begin with a stub Game API and prints JSON with
-- areas, links and the areas opened at start.
Script = {Level = {}, Mode = {}}
local opened, calls = {}, {}
Game = setmetatable({
  IsIPadMode = function() return false end,
  GetWaveNumber = function() return 1 end,
  GetDifficulty = function() return 3 end,
  RandomNumber = function(a) return a end,
  MatchHash = function() return false end,
}, {__index = function(_, k) return function(...) calls[#calls + 1] = k; return 0 end end})
for _, f in ipairs({"ingame.lua", "waves.lua", "scenery.lua", "maxzombies.lua", "unleash.lua"}) do
  pcall(dofile, arg[1] .. "/" .. f)
end
Script.OpenArea = function(name) opened[#opened + 1] = name end
Script.SetupInitialMeshes = function() end
Script.SetupInsideMeshes = function() end
Script.SetUpBarrels = function() end
dofile(arg[2])
local L = Script.Level
if L.Setup then pcall(L.Setup) end
if L.Begin then pcall(L.Begin) end
local function json(v)
  if type(v) == "table" then
    local out, n = {}, #v
    if n > 0 then
      for i = 1, n do out[#out + 1] = json(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, x in pairs(v) do
      if type(x) ~= "function" then out[#out + 1] = string.format("%q:%s", tostring(k), json(x)) end
    end
    table.sort(out)
    return "{" .. table.concat(out, ",") .. "}"
  elseif type(v) == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end
print(json({areas = L.Areas or {}, links = L.Links or {}, start_areas = opened,
            max_zombies = L.MaxZombiesAmount or 24}))
