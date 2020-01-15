require("HC2_api")
ltn12 = require("ltn12")

if os.getenv("HC2DOCKER")=="TRUE" then
  _HC2_IP = "HC2proxy:8888"
end

local VERSION = 0.1
local fmt = string.format
function printf(...) io.write(fmt(...)) io.flush() end

local DOC = 
[[turnOn <id> 
turnOff <id> 
setValue <id> <property> <value>
getValue <id> <property>
setGlobal <id> <name> <value>
getGlobal <id> <name>

getDevice <id>

copy db <name>
save db <name>
list db
load db <name>
remove db <name>

list globals
list devices
list virtualDevices
list rooms

help
start <file>|<sceneID>
stop <file>|<sceneID>

exit
]]

local PROMPT = "HC2proxy"
local INTRO = 
[[HC2proxy command line interface v%s.
See 'help' for commands
]]

local function getID(id) return id~="" and id or GID end

local COMMANDS = {
  ['^(%d+)%s*$'] = function(id) if id=="0" then GID=nil else GID=id end end,
  ['^turn[oO]n%s*(%d*)%s*$'] = function(id) return fibaro:call(getID(id),"turnOn") end,
  ['^turn[oO]ff%s*(%d*)%s*$'] = function(id) return fibaro:call(getID(id),"turnOff") end,
  ['^set[vV]alue%s*(%d*)%s%+(%w+)%s+(%w+)%s*$'] = function(id) return fibaro:setValue(getID(id),prop,val) end,
  ['^get[vV]alue%s*(%d*)%s%+(%w+)%s*$'] = function(id,prop) return fibaro:getValue(getID(id),prop) end,
  ['^set[gG]lobal%s+(%w+)%s+(%w+)%s*$'] = function(name,val) return fibaro:setGlobal(name,val) end,
  ['^get[gG]lobal%s+(%w+)%s*$'] = function(name) return fibaro:getGlobal(name) end,

  ['^get[dD]evice%s+(%d+)%s*$'] = function(id) return __fibaro_get_device(tonumber(id)) end,

  ['^copy%s+db%s+(%w+)%s*$'] = function(name) return __system:copydb(name) end,
  ['^save%s+db%s+(%w+)%s*$'] = function(name) return __system:savedb(name) end,
  ['^list%s+db%s*$'] = function() return table.concat(__system:listdb() or {},"\n") end,
  ['^load%s+db%s+(%w+)%s*$'] = function(name) return __system:loaddb(name) end,
  ['^remove%s+db%s+(%w+)%s*$'] = function(name) return __system:removedb(name) end,

  ['^help'] = function() printf(DOC) end,
  ['^echo%s+(.*)$'] = function(echo) return echo end,

  ['^start%s+(%w)'] = function(name) fibaro:startScene(name) end,
  ['^stop%s+(%w)'] = function(name) fibaro:killScene(name) end,

  ['^exit'] = function() os.exit(0) end,
}

printf(INTRO,VERSION)

while true do
  printf("%s%s>",PROMPT,GID and ":"..GID or "")
  local s = io.read()
  local stat,res = pcall(function()
      local handled = false
      for p,c in pairs(COMMANDS) do
        local m = {s:match(p)}
        if #m>0 then 
          local res = c(unpack(m))
          if res then printf("%s\n",type(res)=='string' and res or tojson(res)) end
          handled = true
          break
        end
      end
      if not handled then
        printf("Unknown command: %s\n",s)
      end
    end)
  if not stat then printf("Error: %s\n",res) end
end