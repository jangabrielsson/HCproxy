--[[
%% properties
%% globals
Test
%% autostart
--]]

if not _EMULATED then dofile("Runner.lua") end

if fibaro:getSourceTriggerType()=='autostart' then
  fibaro:setGlobal("Test","0")
else
  local i = tonumber(fibaro:getGlobalValue("Test"))
  print("Value="..i)
  if i < 400 then
    --fibaro:sleep(1000)
    fibaro:setGlobal("Test",i+1)
  end
end