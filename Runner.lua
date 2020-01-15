socket = require("socket")
cfg = require("dist.config")
lfs = require("lfs")
mobdebug = require("mobdebug")

mobdebug.on()
mobdebug.coro()

require("HC2_api")

_debugFlags = {
  triggers = true 
}

_EMULATED = _EMULATED or true

osTime = os.time
osDate = os.date

format = string.format
function _assert(test,msg,...) 
  if not test then 
    msg = format(msg,...) error(msg,3) 
  end 
end
function _assertf(test,msg,fun) if not test then msg = format(msg,fun and fun() or "") error(msg,3) end end

function isEvent(e) return type(e) == 'table' and e.type end
function copy(obj) return transform(obj, function(o) return o end) end
function equal(e1,e2)
  local t1,t2 = type(e1),type(e2)
  if t1 ~= t2 then return false end
  if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end
  for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
  for k2,v2 in pairs(e2) do if e1[k2] == nil or not equal(e1[k2],v2) then return false end end
  return true
end
function transform(obj,tf)
  if type(obj) == 'table' then
    local res = {} for l,v in pairs(obj) do res[l] = transform(v,tf) end 
    return res
  else return tf(obj) end
end

LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
-- ZBS colors, works best with dark color scheme http://bitstopixels.blogspot.com/2016/09/changing-color-theme-in-zerobrane-studio.html
if _COLOR=='Dark' then
  _LOGMAP = {orange="\027[33m",white="\027[37m",Cyan="\027[1;43m",green="\027[32m",Tomato="\027[39m"} -- ANSI escape code, supported by ZBS
else
  _LOGMAP = {orange="\027[33m",white="\027[34m",Cyan="\027[35m",green="\027[32m",Tomato="\027[31m"} -- ANSI escape code, supported by ZBS
end
_LOGEND = "\027[0m"
--[[Available colors in Zerobrane
for i = 0,8 do print(("%s \027[%dmXYZ\027[0m normal"):format(30+i, 30+i)) end
for i = 0,8 do print(("%s \027[1;%dmXYZ\027[0m bright"):format(38+i, 30+i)) end
--]]

local function prconvert(o)
  if type(o)=='table' then
    if o.__tostring then return o.__tostring(o)
    else return tojson(o) end
  else return o end
end
local function tprconvert(args) local r={}; for _,o in ipairs(args) do r[#r+1]=prconvert(o) end return r end

function Log(color,message,...)
  color = _COLOR and _LOGMAP[color] or ""
  local args = type(... or 42) == 'function' and {(...)()} or {...}
  --message = #args>0 and _format(message,table.unpack(args)) or message
  message = #args>0 and format(message,table.unpack(tprconvert(args))) or prconvert(message)
  print(format("%s%s %s%s",color,os.date("%a/%b/%d,%H:%M:%S:",os.time()),message,color~="" and _LOGEND or "")) 
  return message
end

if not _VERSION:match("5%.1") then
  loadstring = load
  function setfenv(fn, env)
    local i = 1
    while true do
      local name = debug.getupvalue(fn, i)
      if name == "_ENV" then debug.upvaluejoin(fn, i, (function() return env end), 1) break
      elseif not name then break end
      i = i + 1
    end
    return fn
  end

  function getfenv(fn)
    local i = 1
    while true do
      local name, val = debug.getupvalue(fn, i)
      if name == "_ENV" then return val
      elseif not name then break end
      i = i + 1
    end
  end
end

function setupContext(id)  -- Table of functions and variables available for scenes
  return
  {
    __fibaroSceneId=id,    -- Scene ID
    __threads=0,           -- Currently number of running threads
    _EMULATED=true,        -- Check if we run in emulated mode
    fibaro=copy(fibaro),  -- scenes may patch fibaro:*...
    __fibaro_get_device = __fibaro_get_device,
    --_System=_System,       -- Available for debugging tasks in emulated mode
    --dofile=Runtime.dofile, -- Allow dofile for including code for testing, but use our version that sets context
    --loadfile=Runtime.loadfile,
    os={clock=os.clock,date=osDate,time=osTime,difftime=os.difftime},
    json=json,
    print=print,
    net = net,
    api = api,
    setTimeout=System.setTimeout,
    --clearTimeout=Runtime.clearTimeout,
    --setInterval=Runtime.setIntervalContext,
    --clearInterval=Runtime.clearInterval,
    urlencode=urlencode,
    select=select,
    split=split,
    tostring=tostring,
    tonumber=tonumber,
    table=table,
    string=string,
    math=math,
    pairs=pairs,
    ipairs=ipairs,
    pcall=pcall,
    xpcall=xpcall,
    error=error,
    io=io,
    collectgarbage=collectgarbage,
    type=type,
    next=next,
    bit32=bit32,
    debug=debug
  }
end

function createSceneFuns()
  local self,scenes = {},{}

  function self.checkValidCharsInFile(src,fileName)
    local lines = split(src,'\r')
    local function ptr(p) local r={}; for i=1,p+9 do r[#r+1]=' ' end return table.concat(r).."^" end
    for n,s in ipairs(lines) do
      s=s:match("^%c*(.*)")
      local p = s:find("\xEF\xBB\xBF")
      if p then error("Illegal UTF-8 sequence in file:%s\rLine:%3d, %s\r%s",fileName,n,s,ptr(p)) end
    end
  end

  function self.parseHeaders(fileName)
    local headers,autostart = {},false
    local f = io.open(fileName)
    if not f then error("No such file:"..fileName) end
    local src = f:read("*all") f:close()
    self.checkValidCharsInFile(src,fileName)
    local c = src:match("--%[%[.-%-%-%]%]")
    local curr = ""
    if c==nil or c=="" then c = "--%[%[\n%%%% autostart\n%]%]--" end
    if c and c~="" then
      c=c:gsub("([\r\n]+)","\n")
      c = split(c,'\n')
      for i=2,#c-1 do
        if c[i]:match("^%%%%") then curr=c[i]:match("%a+")
        else headers[#headers+1]=curr..":"..c[i] end 
        autostart = curr=="autostart"
      end
    end

    local events={}
    local id,name,t
    for _,h in ipairs(headers) do
      id,name=h:match("properties:(%d+)%s+([%a]+)")
      if id then 
        events[#events+1]={type='property',deviceID=tonumber(id), propertyName=name}
      else
        name = h:match("globals:([%w]+)")
        if name then events[#events+1]={type='global',name=name}
        else
          id,t = h:match("(%d+)%s+(CentralSceneEvent)")
          if id then events[#events+1]={type='event',event={type='CentralSceneEvent',data={deviceId=tonumber(id)}}}
          else
            id,t = h:match("(%d+)%s+(AccessControlEvent)")
            if id then
              events[#events+1]={type='event',event={type='AccessControlEvent',data={id=tonumber(id)}}} 
            end
          end
        end
      end
    end
    return events,src,autostart
  end

  function self.load(file,id,name)
    local scene,msg = {}
    scene.name = name
    scene.fullname=fullname
    scene.id = id
    scene.fromFile=true
    scene.runningInstances = 0
    scene.runConfig = "TRIGGER_AND_MANUAL"
    scene.triggers,scene.lua,scene.autostart = self.parseHeaders(file)
    scene.isLua = true
    scene.code,msg=loadfile(file)
    _assert(scene.code~=nil,"Error in scene file %s: %s",file,msg)
    Log(LOG.SYSTEM,"Loaded scene:%s, id:%s, file:'%s'",name,id,file)
    return scene
  end

  function self.loadEmbedded()
    local short_src,org_src = "",""
    for i=1,1000 do
      local di = debug.getinfo(i)
      if not di then break else short_src = di.short_src end
    end
    org_src = short_src or org_src
    if _EMULATED then
      --short_src=short_src:match("[\\/]?([%.%w_%-]+)$")
      local name,id
      if type(_EMULATED)=='table' then
        name,id = _EMULATED.name,_EMULATED.id
      else 
        name,id = short_src:match("(%d+)_(%w+)%.[lL][uU][aA]$")
        if name then id=tonumber(id)
        else name,id="Test",99 end
      end
      local HC2file = debug.getinfo(1).short_src:match("[\\/]?([%.%w_%-]+)$")
      local attr1, err1 = lfs.attributes(HC2file)
      local attr2, err2 = lfs.attributes(short_src)
      if err1 or err2 then
        Log(LOG.LOG,"HC2 file name:%s",debug.getinfo(1).short_src)
        Log(LOG.LOG,"Embedded file name:%s",org_src)
        error("File load error: "..(err1 or err2).." in "..lfs.currentdir())
      end
      local wd = lfs.currentdir()
      if wd then wd = wd..(cfg.arch == "Windows" and "\\" or "/")..short_src end
      return self.register(short_src,id)
    end
  end

  function self.register(file,id,name)
    if scenes[id] then Log(LOG.ERROR,"Scene:%s already registered",id) end
    local scene = self.load(file,id,name or "Scene:"..id) 
    scenes[id]=scene

    if scene.autostart then 
      Log(LOG.SYSTEM,"Scene:%s [ Trigger:%s ]",id,{type='autostart'})
      Event.event({type='autostart'},function(env) Scene.start(scene,env.event) end)
    end
    for _,t in ipairs(scene.triggers) do
      Log(LOG.SYSTEM,"Scene:%s [ Trigger:%s ]",id,t)
      Event.event(t,function(env) Scene.start(scene,env.event) end)
    end

    Event.event({type='other',_id=id}, -- startup event
      function(env) 
        local event = env.event
        local args = event._args
        event._args=nil
        event._id=nil
        Scene.start(scene,event,args)
      end)
    return scene
  end

  _SceneContext = {}

  function self.start(scene,event,args)
    local env = setupContext(scene.id)
    env._ENV=env
    env.__fibaroSceneSourceTrigger = event
    env.__fibaroSceneArgs = args
    env.__sceneCode = scene.code 
    env.__sceneCleanup = function(co)
      if (not scene._terminateMsg) or (scene._terminateMsg and not scene._terminateMsg(scene.id,env.__orgInstanceNumber,env)) then
        Log(LOG.LOG,"Scene %s terminated (%s)",env.__debugName,co)
      end
      scene.runningInstances=scene.runningInstances-1 
    end
    local co = coroutine.create(
      function()
        mobdebug.on()
        _SceneContext[coroutine.running()]=env
        local stat,res = pcall(scene.code)
        mobdebug.off()
        _SceneContext[coroutine.running()]=nil
        if stat then return res  
        else 
          Log(LOG.ERROR,"Error in scene:%s - %s",scene.id,res)
          Log(LOG.ERROR,debug.traceback())
        end
      end)
    local sceneFun = nil
    sceneFun = function()
      setfenv(scene.code,env) 
      local stat,thread,time = coroutine.resume(co)
      if thread and time~='%%EXIT%%' then 
        Runtime.startTimer(sceneFun,time or 0)
      else 
        Log(LOG.SYSTEM,"Scene:%s terminated",scene.id)
      end
    end
    local tr = Runtime.startTimer(sceneFun,0)
  end

  return self
end

function createRuntime()
  local self = {}
  local timers = nil
  local function milliTime() return os.time() end

  function self.insertTimer(t) -- {fun,time,next}
    if timers == nil then timers=t
    elseif t.time < timers.time then
      timers,t.next=t,timers
    else
      local tp = timers
      while tp.next and tp.next.time <= t.time do tp=tp.next end
      t.next,tp.next=tp.next,t
    end
    return t.fun
  end

  function self.runTimers()
    while timers ~= nil do
      ::REDO::
      local t,now = timers,milliTime()
      if t.time > now then 
        socket.sleep(0.01)
        if idle then idle() end
        goto REDO 
      end
      local ct = os.clock()
      timers=timers.next
      t.fun()
    end
  end

  function self.startTimer(fun,ms)
    local t = {time=(ms/1000+milliTime()),fun=fun}
    self.insertTimer(t)
  end

  return self
end

----------------- Event Engine --------------
function createEventEngine()
  local self,handlers = { RULE='%%RULE%%' },{}

  function self.match(pattern, expr)
    local matches = {}
    local function unify(pattern,expr)
      if pattern == expr then return true
      elseif type(pattern) == 'table' then
        if type(expr) ~= "table" then return false end
        for k,v in pairs(pattern) do if not unify(v,expr[k]) then return false end end
        return true
      else return false end
    end
    return unify(pattern,expr) and matches or false
  end

  local toHash,fromHash={},{}
  fromHash['property'] = function(e) return {e.type..e.deviceID,e.type} end
  fromHash['global'] = function(e) return {e.type..e.name,e.type} end
  toHash['property'] = function(e) return e.deviceID and 'property'..e.deviceID or 'property' end
  toHash['global'] = function(e) return e.name and 'global'..e.name or 'global' end

  function self.event(e,action) -- define rules - event template + action
    _assertf(isEvent(e) or type(e)=='function', "bad event format '%s'",tojson(e))
    local hashKey = toHash[e.type] and toHash[e.type](e) or e.type
    handlers[hashKey] = handlers[hashKey] or {}
    local rules = handlers[hashKey]
    local rule,fn = {[self.RULE]=e, action=action}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if equal(e,rs[1][self.RULE]) then rs[#rs+1] = rule fn = false break end
    end
    if fn then rules[#rules+1] = {rule} end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    return rule
  end

  function self.handleEvent(e) -- running a posted event
    local env, _match = {event = e, p={}}, self.match
    local hasKeys = fromHash[e.type] and fromHash[e.type](e) or {e.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(handlers[hashKey] or {}) do -- Check all rules of 'type'
        local match = _match(rules[1][self.RULE],e)
        if match then
          if next(match) then for k,v in pairs(match) do env.p[k]=v match[k]={v} end env.context = match end
          for _,rule in ipairs(rules) do 
            if not rule._disabled then env.rule = rule rule.action(env) end
          end
        end
      end
    end
  end

  local function midnight() local t = osDate("*t"); t.hour,t.min,t.sec = 0,0,0; return osTime(t) end

  local function hm2sec(hmstr)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
    end
    local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
    _assert(h and m,"Bad hm2sec string %s",hmstr)
    return (sg == '-' and -1 or 1)*(h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60)
  end

  local function toTime(time)
    if type(time) == 'number' then return time end
    local p = time:sub(1,2)
    if p == '+/' then return hm2sec(time:sub(3))+osTime()
    elseif p == 'n/' then
      local t1,t2 = midnight()+hm2sec(time:sub(3)),osTime()
      return t1 > t2 and t1 or t1+24*60*60
    elseif p == 't/' then return  hm2sec(time:sub(3))+midnight()
    else return hm2sec(time) end
  end

  function self.post(e,time) -- time in 'toTime' format, see below.
    _assertf(type(e) == "function" or isEvent(e), "Bad event format %s",function() tojson(e) end)
    time = toTime(time or osTime())
    if time < osTime() then return nil end
    if _debugFlags.triggers and not (type(e)=='function') then
      if e.type=='other' and e._id then
        Log(LOG.LOG,"System trigger:{\"type\":\"other\"} to scene:%s at %s",e._id,osDate("%a %b %d %X",time)) 
      else
        Log(LOG.LOG,"System trigger:%s at %s",tojson(e),osDate("%a %b %d %X",time)) 
      end
    end
    if type(e)=='function' then return Runtime.setTimeout(e,1000*(time-osTime()),"Timer")
    else return Runtime.startTimer(function() self.handleEvent(e) end,1000*(time-osTime()),"Main") end
  end

  function self.schedule(time,fun)
    local function loop()
      fun()
      Runtime.setTimeout(loop,1000*(toTime(time)-osTime()))
    end
    Runtime.setTimeout(loop,1000*(toTime(time)-osTime()))
  end

  self.str2time = toTime
  return self
end

LAST_EVENT = ""
LAST_TIME = os.time()
local function getEvents()
  local stat,es = pcall(function() return api.get("/proxy/event/"..LAST_EVENT) end)
  if stat and #es>0 then LAST_EVENT=es[#es]._uid return es else return {} end
end

function idle()
  if os.time()-LAST_TIME < 1 then return else LAST_TIME=os.time() end
  repeat
    local es = getEvents()
    for _,e in ipairs(es) do Event.post(e) end
  until #es == 0
end

getEvents() -- flush events queue

------------- Fibaro patches ----------
function __fibaroSleep(n) return coroutine.yield(coroutine.running(),n) end
function fibaro:abort(s) coroutine.yield(coroutine.running(),'%%EXIT%%') end
function fibaro:getSourceTrigger() 
  return _SceneContext[coroutine.running()].__fibaroSceneSourceTrigger 
end
function fibaro:getSourceTriggerType() 
  local st = fibaro:getSourceTrigger() 
  if st then return st.type else return nil end
end
function fibaro:args() return _SceneContext[coroutine.running()].__fibaroSceneArgs end

---------------- System ----------------
function createSystemFuns()
  local self = {}
  function self.setTimeout(fun,t) Runtime.start(fun,t) end
  return self
end
-------------- Main --------------------

Event   = createEventEngine()
Runtime = createRuntime()
Scene   = createSceneFuns()
System  = createSystemFuns()

local s = Scene.loadEmbedded()
local function keepAlive()
  Runtime.startTimer(keepAlive,5*1000)
end
keepAlive()
Event.post({type='autostart'})
Runtime.runTimers()
os.exit()
