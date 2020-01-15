
local DATA_PATH = os.getenv("DATA_PATH") or "/var/local/hc2proxy/"
turbo = require("turbo")
lfs = require("lfs")

Utils = loadfile("lua/utils.lua")()
local getDefault = Utils.getDefault

local stat,CONFIG = Utils.loadJson(DATA_PATH.."config.json")
CONFIG = CONFIG or {}

CONFIG.HC2_USER = os.getenv("HC2_USER") or CONFIG.HC2_USER or "bob@acme.com"
CONFIG.HC2_PWD  = os.getenv("HC2_PWD") or CONFIG.HC2_PWD or "paswrd"      
CONFIG.HC2_IP   = os.getenv("HC2_IP") or CONFIG.HC2_IP or "192.168.1.84"
CONFIG.MOBDEBUG = os.getenv("MOBDEBUG") or getDefault(CONFIG.MOBDEBUG,false)
CONFIG.AUTOGLOBALS = getDefault(CONFIG.AUTOGLOBALS,true)
CONFIG.AUTODEVICES = getDefault(CONFIG.AUTODEVICES,true)
CONFIG.DATA_FILE = getDefault(CONFIG.DATA_FILE,"minimal")
CONFIG.DATA_PATH = DATA_PATH

if CONFIG.MOBDEBUG=="TRUE" then
  md = require('mobdebug')
  md.basedir("/develop")
  md.start("host.docker.internal")
  md.coro()
end

VERSION = 0.1

if arg[1]=="--log" then
  f = loadfile("lua/log.lua")
  f() 
  os.exit()
elseif arg[1]=="--cli" then
  f,res = loadfile("lua/cli.lua")
  f() 
  os.exit()
elseif arg[1]=="--test" then
  local exec = require('process').exec;
  local cmd = exec( 'echo', { 'hello world' } );
-- read from stdout
  print( cmd:stdout() ); -- 'hello world\n'
end

RESOURCES = {}
ENCODE = turbo.escape.json_encode
DECODE = turbo.escape.json_decode
local _events = {}

function main()

  local function gensym(s) return s..tostring({1,2,3}):match("([abcdef%d]*)$") end

  local function addEvent(e) -- [<t1,e1>,<t2,e2>,...<tn,en>]
    e._uid = gensym("E")
    _events[#_events+1] = e
  end

  local function makeDevice(id,name,templ)
    if not RESOURCES.devices[id] then
      templ = templ or "fibaroGeneric"
      local stat,d = loadJson("dtemplates/"..templ..".json")
      if stat then 
        d.id = id
        d.name = name or "Device"..id
        RESOURCES.devices[id] = d
      end
    end
    return RESOURCES.devices[id]
  end

  local function makeGlobal(name,value)
    local g = {readOnly = false, isEnum = false, name=name, value=value}
    RESOURCES.globalVariables[name] = g
    return g
  end

  function __fibaro_get_device(id,create)
    id = tostring(id)
    return not RESOURCES.devices[id] and create and makeDevice(id) or RESOURCES.devices[id]
  end
  function __fibaro_get_device_property(id ,name, create) 
    return __fibaro_get_device(id,create).properties[name]
  end
  function __fibaro_get_scene(id) return RESOURCES.scenes[tostring(id)] end
  function __fibaro_get_global_variable(name,create) 
    return not RESOURCES.globalVariables[name] and create and makeGlobal(name) or RESOURCES.globalVariables[name]
  end
  function __fibaro_get_room(roomID) return RESOURCES.rooms[tostring(id)] end
  function __fibaro_set_global_variable(name,data,create)
    local g = __fibaro_get_global_variable(name,create)
    if g then
      if  g.value ~= data.value then 
        g.value, g.modified = data.value, os.time()
        addEvent({type='global', name=name, value=data.value}) 
      end
      return true
    else return false end
  end

  local function getEvents(lastUID)
    local n,res = 1,{}
    for i=#_events,1,-1 do if _events[i]._uid == lastUID then n=i+1; break end end
    for i=n,#_events do res[#res+1]=_events[i] end
    --Log("LastUID:%s, last:%s",lastUID,#res>0 and res[#res]._uid or "")
    return res
  end

  local GetEventHandler = class("GetEventHandler", turbo.web.RequestHandler)
  function GetEventHandler:get(uid) self:write(getEvents(uid)) end
  function GetEventHandler:put(event) local e = self:get_json(true) addEvent(e) end

-- Create a new requesthandler with a method get() for HTTP GET.
  local GetGlobalHandler = class("GetGlobalHandler", turbo.web.RequestHandler)
  function GetGlobalHandler:get(var)
    self:write(__fibaro_get_global_variable(var,CONFIG.AUTOGLOBALS)) 
  end

  function GetGlobalHandler:put(var) --set
    local vals = self:get_json(true)
    if not __fibaro_set_global_variable(var,CONFIG.AUTOGLOBALS) then
      self:set_status(404)
    else end
  end

  local GetDevicePropertyHandler = class("GetDevicePropertyHandler", turbo.web.RequestHandler)
  function GetDevicePropertyHandler:get(id,property)
    self:write(__fibera_get_device_property(id,property,true))
  end

  local GetSceneHandler = class("GetSceneHandler", turbo.web.RequestHandler)
  function GetSceneHandler:get(id)
    id = tonumber(id)
    forwardRequest(fmt("http://%s/api/scenes/%s",__HC2_IP,id),self)
  end

  local GetDeviceHandler = class("GetDeviceHandler", turbo.web.RequestHandler)
  function GetDeviceHandler:get(id)
    id = tonumber(id)
    forwardRequest(fmt("http://%s/api/devices/%s",__HC2_IP,id),self)
  end

  local GetRoomHandler = class("GetRoomHandler", turbo.web.RequestHandler)
  function GetRoomHandler:get(id)
    id = tonumber(id)
    forwardRequest(fmt("http://%s/api/rooms/%s",__HC2_IP,id),self)
  end

  local GetSystemHandler = class("GetSystemHandler", turbo.web.RequestHandler)
  function GetSystemHandler:get(cmd1,cmd2,arg)
    local cmd,cont = System[cmd1]
    if cmd2 == 'copy' then
      cont = function(e) self:write(ENCODE(e)) end
    end
    if cmd then
      local f = cmd[cmd2]
      self:add_header('Content-Type','application/json')
      local res = f(arg,cont)
      self:write(type(res)=='table' and res or ENCODE(res))
    end
    Log(LOG.LOG,"SYSTEM/%s/%s/%s",cmd1,cmd2,arg or "")
  end

  local function setAndPropagate(id,key,value)
    local dev = __fibaro_get_device(id,CONFIG.AUTODEVICES)
    local d = dev.properties
    if d[key] ~= value then
      d[key]=value
      dev.modified=os.time()
      addEvent({type='property', deviceID=id, propertyName=key, value=tostring(value)})
    end
  end

  local _specCalls={}
  function _specCalls.setProperty(id,prop,...) setAndPropagate(id,prop,({...})[1]) end 
  function _specCalls.setColor(id,R,G,B) setAndPropagate(id,"color","RGB") end
  function _specCalls.setArmed(id,value) setAndPropagate(id,"armed",value) end
  function _specCalls.sendPush(id,msg) end -- log to console?
  function _specCalls.pressButton(id,msg) end -- simulate VD?
  function _specCalls.setPower(id,value) setAndPropagate(id,"power",value) end
  function _specCalls.close(id,value) setAndPropagate(id,"value",0) end
  function _specCalls.open(id,value) setAndPropagate(id,"value",100) end
  function _specCalls.turnOn(id,value) setAndPropagate(id,"value",true) end
  function _specCalls.turnOff(id,value) setAndPropagate(id,"value",false) end
  function _specCalls.on(id,value) setAndPropagate(id,"value",true) end
  function _specCalls.off(id,value) setAndPropagate(id,"value",false) end
  function _specCalls.setValue(id,prop,value) setAndPropagate(id,prop,value) end

  local CallActionHandler = class("CallActionHandler", turbo.web.RequestHandler)
  function CallActionHandler:get()
    local id = tonumber(self:get_argument('deviceID',""))
    local actionName = self:get_argument('name',"")
    local arg1 = self:get_argument('arg1',"")
    local arg2 = self:get_argument('arg2',"")
    local arg3 = self:get_argument('arg3',"")
    if _specCalls[actionName] then _specCalls[actionName](id,arg1,arg2,arg3) return end 
    Log(LOG.LOG,"Error: fibaro:call(..,'%s',..) is not supported, fix it!",actionName)
  end

  local StaticActionHandler = class("StaticActionHandler", turbo.web.StaticFileHandler)
  local prep = StaticActionHandler.prepare
  function StaticActionHandler:prepare()
    Log(LOG.LOG,"PREPARE:%s/%s",self.options or "",self._url_args[1] or "")
    if self._url_args[1]  then
      local file = self._url_args[1]
      local id = file:match("x(%d+).png")
      Log(LOG.LOG,"ID:%s",id)
      if id and _devices[id] then
        Log(LOG.LOG,"VALUE:%s",_devices[id].properties.value)
        if _devices[id].properties.value > "0" then 
          self._url_args[1] = "o.png" 
        else 
          self._url_args[1] = "x.png"
        end
      end
    end
    prep(self)
  end
--[[
  function web.StaticFileHandler:prepare()
    if not self.options or type(self.options) ~= "string" then
        error("StaticFileHandler not initialized with correct parameters.")
    end
    self.path = self.options
    -- Check if this is a single file or directory.
    local last_char = self.path:sub(self.path:len())
    if last_char ~= "/" then
        self.file = true
    end
end
--]]

  local MustacheHandler = class("ExampleHandler", turbo.web.RequestHandler)
  function MustacheHandler:get()
    self:write(turbo.web.Mustache.render(turbo.web.Mustache.compile([[
            Login={{login}}
            {{#items}}
              Name: {{item}} login={{login}}
            {{/items}}
        ]]), {login="user", items={{item="one"}, {item="two"}}})
    )
  end

-- Create an Application object and bind our HelloWorldHandler to the route '/hello'.
  local app = turbo.web.Application:new({
      {"/api/globalVariables/(.*)$", GetGlobalHandler},
      {"/api/devices/(%d+)/properties/(.+)$",GetDevicePropertyHandler},
      {"/api/devices/?(%d*)$",GetDeviceHandler},
      {"/api/scenes/?(%d*)$",GetSceneHandler},
      {"/api/rooms/?(%d*)$",GetRoomHandler},
      {"/api/callAction",CallActionHandler},
      {"/api/proxy/event/(.*)$",GetEventHandler},
      {"/api/proxy/system/(.+)/(.+)/(.*)$",GetSystemHandler},
      {"/static/(.*)$", StaticActionHandler, "/develop/"},
      -- {"/static/(.*)$", turbo.web.StaticFileHandler, "/develop/"},
      {"/must", MustacheHandler},      

    })

-- Set the server to listen on port 8888 and start the ioloop.
  app:listen(8888)
  function foo()
    io.write("HELLO")
    io.flush()
  end

  loop = turbo.ioloop.instance()
--loop:set_interval(1000, foo)
  loop:start()
end

fmt = string.format
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
function Log(C,...) io.write(string.format(...).."\n") io.flush() end
function Log2(C,...) io.write(string.format(...)) io.flush() end

turbo.log.categories.success = false

setPath,base64,loadJson,saveJson = Utils.setPath,Utils.base64,Utils.loadJson,Utils.saveJson

function forwardRequest(url,handler)
  local kvarg = {on_headers=function(H) H:set("Authorization","Basic "..base64(CONFIG.HC2_USER..":"..CONFIG.HC2_PWD), false) end}
  local res = coroutine.yield(turbo.async.HTTPClient():fetch(url,kvarg))
  if res.error then handler:write(nil)
    Log(LOG.LOG,"Error:"..res.error)
  else handler:write(res.body) end
end

local function chainRequest(url,successHandler,erroHandler)
  local kvarg = {on_headers=function(H) H:set("Authorization","Basic "..base64(CONFIG.HC2_USER..":"..CONFIG.HC2_PWD), false) end}
  local res = coroutine.yield(turbo.async.HTTPClient():fetch(url,kvarg))
  if res.error and errorHandler then errorHandler(res)
  elseif successHandler then successHandler(res) end
end

function getHC2Data(cont,err)
  local data = { _time = os.time() }
  local rsrcs = {
    ["/devices"]=function(s) local r = {}; for _,d in ipairs(s) do r[tostring(d.id)]=d end return r end,
    ["/scenes"]=function(s) local r = {}; for _,d in ipairs(s) do r[tostring(d.id)]=d end return r end,
    ["/virtualDevices"]=function(s) local r = {}; for _,d in ipairs(s) do r[tostring(d.id)]=d end return r end,
    ["/globalVariables"]=function(s) local r = {}; for _,g in ipairs(s) do r[g.name]=g end return r end,
    ["/sections"]=function(s) local r = {}; for _,d in ipairs(s) do r[tostring(d.id)]=d end return r end,
    ["/rooms"]=function(s) local r = {}; for _,d in ipairs(s) do r[tostring(d.id)]=d end return r end,
    ["/iosDevices"]=function(s) local r = {}; for _,d in ipairs(s) do r[tostring(d.id)]=d end return r end,
    ["/settings/info"]=function(s) return s end,
    ["/settings/location"]=function(s) return s end,
    ["/settings/network"]=function(s) return s end,
    ["/weather"]=function(s) return s end,
  }
  local f = nil
  for i,_ in pairs(rsrcs) do
    local rsrc,c = i,cont
    f = function()
      Log2(LOG.SYSTEM,"Reading %s...",rsrc)
      chainRequest(fmt("http://%s/api%s",__HC2_IP,rsrc),
        function(res) 
          local path = split(rsrc,"/")
          if res.body then
            local result = rsrcs[rsrc](turbo.escape.json_decode(res.body))
            setPath(data,rsrc,result)
            Log(LOG.SYSTEM,"done.") 
          else 
            Log(LOG.ERROR,"Error reading %s",rsrc) 
          end
          c(data) 
        end,
        function(e) err(e) end)
    end
    cont = f
  end
  cont(data)
end

System = {
  db = {
    save = function(name) 
      local stat,res = Utils.saveJson(CONFIG.DATA_PATH..name..".db",ENCODE(RESOURCES))
      return stat and "OK" or res
    end,
    copy = function(name,cont) 
      getHC2Data(
        function(data)
          local stat,res = saveJson(CONFIG.DATA_PATH..name..".db",ENCODE(data))
          if cont then cont(stat and "OK" or res) end
        end,
        function(err) if cont then cont(err) end
        end)
    end,
    list = function(name) 
      local files = {}
      for file in lfs.dir(CONFIG.DATA_PATH) do
        if file ~= "." and file ~= ".." then
          local attr = lfs.attributes(CONFIG.DATA_PATH..file)
          if attr and attr.mode=="file" and file:match("%w.db") then
            files[#files+1] = string.format("%-20s %s",file,os.date("%c",attr.modification))
          end
        end
      end
      return files
    end, 
    load = function(name) 
      local stat,res = Utils.loadJson(CONFIG.DATA_PATH..name..".db")
      if stat then 
        RESOURCES = res 
        Log(LOG.SYSTEM,"Loaded db %s",name) 
      end
      return stat and "OK" or res
    end,
    remove = function(name) 
      local res = os.remove(CONFIG.DATA_PATH..name..".db"),"ERR"
      return res and "OK" or "File missing"
    end,
  }
}

Log(LOG.WELCOME,"HC2proxy server v%s",VERSION)
System.db.load(CONFIG.DATA_FILE)
main()
