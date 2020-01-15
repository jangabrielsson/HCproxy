require("lua/json")

HomeCenter =  { 
  PopupService =  { 
    publish =  function ( request ) 
      local response = api.post( '/popups' , request ) 
      return response
    end 
  } , 
  SystemService =  { 
    reboot =  function ( ) 
      local client = net.HTTPClient() 
      client: request ("http://localhost/reboot.php") 
    end , 
    shutdown =  function ( ) 
      local client = net.HTTPClient() 
      client:request ( "http://localhost/shutdown.php" ) 
    end 
  } 
}

fibaro =  { }

function fibaro:debug(text) print (text) end

function fibaro:sleep(time) 
  __fibaroSleep (time) 
end

function __convertToString(value) 
  if type( value )  ==  'boolean'  then 
    return value and '1' or '0' 
  elseif type(value)  ==  'number'  then return  tostring(value) 
  elseif type(value)  ==  'table'  then return json.encode(value) end
  return value
end

function __assert_type(value,typeOfValue ) if  (type(value) ~= typeOfValue) then error("Assertion failed: Expected"..typeOfValue,3) end end
function __fibaro_get_device(deviceID) __assert_type(deviceID,"number" ) return api.get("/devices/"..deviceID ) end
function __fibaro_get_room (roomID) __assert_type (roomID,"number") return api.get("/rooms/"..roomID) end
function __fibaro_get_scene(sceneID) __assert_type (sceneID,"number") return api.get("/scenes/"..sceneID) end
function __fibaro_get_global_variable(varName) __assert_type (varName ,"string") return api.get("/globalVariables/"..varName) end
function __fibaro_get_device_property(deviceId ,propertyName) return api.get( "/devices/"..deviceId.."/properties/"..propertyName) end

-- getting device properties 

function fibaro:get(deviceID,propertyName) 
  local property = __fibaro_get_device_property(deviceID ,propertyName)
  if  (property ==  nil)  then return  nil end
  return __convertToString(property.value ),property.modified
end

function fibaro:getValue(deviceID , propertyName ) 
  local value = fibaro:get( deviceID , propertyName ) 
  return value
end

function fibaro:getModificationTime(deviceID , propertyName) 
  local _ , modified = fibaro:get(deviceID , propertyName) 
  return modified
end

-- global variables 

function fibaro:getGlobal(varName) 
  local globalVar = __fibaro_get_global_variable(varName) 
  if  globalVar ==  nil then return  nil end
  return globalVar.value , globalVar.modified
end

function fibaro:getGlobalValue(varName) 
  local globalVar = __fibaro_get_global_variable(varName) 
  if  globalVar ==  nil then return  nil end
  return globalVar.value
end

function fibaro:getGlobalModificationTime(varName ) 
  local globalVar = __fibaro_get_global_variable ( varName ) 
  if  ( globalVar ==  nil )  then return  nil end
  return globalVar . modified
end

function fibaro:setGlobal(varName , value) 
  __assert_type (varName ,  "string") 
  local data =  {["value"] = tostring(value) , ["invokeScenes"] = true} 
  api.put("/globalVariables/"..varName , data) 
end

-- scenes 

function fibaro:countScenes(sceneID) 
  sceneID = sceneID or __fibaroSceneId
  local scene = __fibaro_get_scene(sceneID) 
  if scene ==  nil  then return  0 end
  return scene.runningInstances
end

function fibaro:isSceneEnabled(sceneID ) 
  local scene = __fibaro_get_scene ( sceneID ) 
  if  ( scene ==  nil )  then 
    return  nil 
  end

  local enabled
  if  ( scene . runConfig ==  "TRIGGER_AND_MANUAL"  or scene . runConfig ==  "MANUAL_ONLY" )  then 
    enabled =  true 
  else 
    enabled =  false 
  end

  return enabled
end

function fibaro:startScene(sceneID ) api.post("/scenes/"..sceneID.."/action/start") end
function fibaro:killScenes(sceneID) api.post ( "/scenes/"..sceneID.."/action/stop") end

function fibaro:setSceneEnabled(sceneID , enabled) 
  __assert_type ( sceneID ,  "number" ) 
  __assert_type ( enabled ,  "boolean" )
  local runConfig
  if enabled ==  true then runConfig =  "TRIGGER_AND_MANUAL" else runConfig =  "DISABLED" end
  local data =  { id = sceneID ,runConfig = runConfig} 
  api.put("/scenes/"..sceneID , data) 
end

function fibaro:getSceneRunConfig(sceneID) 
  local scene = __fibaro_get_scene(sceneID) 
  if  (scene ==  nil)  then return  nil end
  return scene.runConfig
end

function fibaro:setSceneRunConfig(sceneID , runConfig) 
  __assert_type (sceneID ,"number") 
  __assert_type (runConfig ,"string")
  local data =  {id = sceneID ,runConfig = runConfig} 
  api.put("/scenes/"..sceneID , data) 
end

-- other 

function fibaro:getRoomID( deviceID ) 
  local dev = __fibaro_get_device ( deviceID ) 
  if dev ==  nil then return  nil end
  return dev.roomID
end

function fibaro:getSectionID(deviceID ) 
  local dev = __fibaro_get_device(deviceID) 
  if dev ==  nil then return  nil end
  if dev.ROOMID ~=  0 then return __fibaro_get_room(dev.ROOMID).sectionID end 
  return  0 
end

function fibaro:getType(deviceID ) 
  local dev = __fibaro_get_device(deviceID) 
  if dev ==  nil then return  nil end
  return dev.type
end

function fibaro:abort() os.exit() end

function fibaro:getSourceTrigger() 
  return __fibaroSceneSourceTrigger 
end

function fibaro:getSourceTriggerType () 
  return __fibaroSceneSourceTrigger["type"] 
end

function fibaro:calculateDistance(position1 , position2) 
  __assert_type ( position1 ,"string") 
  __assert_type ( position2 ,"string") 
  return __fibaroCalculateDistance (position1 , position2) 
end

function fibaro:call(deviceID , actionName ,...) 
  deviceID =  tonumber ( deviceID ) 
  __assert_type ( actionName ,"string") 
  args = "" 
  for i , v in  ipairs ( { ... } )  do 
    args = args..'&arg'..tostring(i)..'='..urlencode(tostring(v)) 
  end 
  api.get("/callAction?deviceID="..deviceID.."&name="..actionName..args) 
end

function urlencode (str) 
  if str then 
    str =  string.gsub(str ,"([^% w])", 
      function  (c)  return  string.format( "%%% 02X" ,string.byte(c))  end) 
  end 
  return str
end 

function fibaro:getName(deviceID) 
  __assert_type (deviceID ,  'number') 
  local dev = __fibaro_get_device(deviceID) 
  if dev ==  nil then return  nil end
  return dev.name
end

function fibaro:getRoomName(roomID ) 
  __assert_type ( roomID ,  'number' ) 
  local room = __fibaro_get_room(roomID) 
  if room ==  nil then return  nil end
  return room.name
end

function fibaro:getRoomNameByDeviceID(deviceID ) 
  __assert_type (deviceID ,  'number') 
  local dev = __fibaro_get_device(deviceID) 
  if dev ==  nil then return  nil end
  local room = __fibaro_get_room (dev.ROOMID)
  if dev.ROOMID ==  0 then return  "unassigned" 
  else 
    if room ==  nil then 
      return  nil 
    end 
  end
  return room.name
end

function fibaro:wakeUpDeadDevice(deviceID ) 
  __assert_type(deviceID , 'number') 
  fibaro:call(1,'wakeUpDeadDevice',deviceID) 
end

--[[
Expected input:
{
  name: value, //:
  properties: {//:
    volume: "nil", //: require property volume to exist, any value
    ip: "127.0.0.1" //: require property ip to equal 127.0.0.1
  }
  interface: ifname //: require device to have interface ifname
 
}
--]]
function fibaro:getDevicesId(filter) 
  if  type ( filter )  ~=  'table'  or 
  ( type ( filter )  ==  'table'  and  next ( filter )  ==  nil ) 
  then 
    return fibaro:getIds ( fibaro : getAllDeviceIds ( ) ) 
  end

  local args =  '/?' 
  for c , d in  pairs ( filter )  do 
    if c ==  'properties'  and d ~=  nil  and  type ( d )  ==  'table'  then 
      for a , b in  pairs ( d )  do 
        if b ==  "nil"  then 
          args = args ..  'property='  .. tostring ( a )  ..  '&' 
        else 
          args = args ..  'property=['  ..  tostring ( a )  ..  ','  ..  tostring ( b )  ..  ']&' 
        end 
      end 
    elseif c ==  ' interfaces'  and d ~=  nil  and  type ( d )  ==  'table'  then 
      for a , b in  pairs (d )  do 
        args = args ..  'interface='  ..  tostring ( b )  ..  '&'
      end 
    else 
      args = args ..  tostring ( c )  ..  "="  ..  tostring ( d )  ..  '&' 
    end 
  end

  args =  String.sub ( args ,  1 ,  - 2 ) 
  return fibaro : GetIDs ( api . get ( '/devices'  .. args ) ) 
end

function fibaro:getAllDeviceIds() 
  return api.get('/devices/') 
end

function fibaro:getIds(devices) 
  local ids =  {} 
  for _,a in  pairs(devices)  do 
    if a ~=  nil  and  type (a)  ==  'table'  and a['id']  ~=  nil  and a['id']  >  3  then 
      table.insert (ids,a['id']) 
    end 
  end 
  return ids
end

http = require("socket.http")
local function Log(msg,...) local m=string.format(msg,...) print(m) return m end
net = {} -- An emulation of Fibaro's net.HTTPClient
local _HTTP = {}
-- It is synchronous, but synchronous is a speciell case of asynchronous.. :-)
function net.HTTPClient() return _HTTP end
-- Not sure I got all the options right..
function _HTTP:request(url,options)
  local resp = {}
  options = options or {}
  local req = options.options or {}
  req.url = url
  req.headers = req.headers or {}
  req.sink = ltn12.sink.table(resp)
  if req.data then
    req.headers["Content-Length"] = #req.data
    req.source = ltn12.source.string(req.data)
  end
  local response, status, headers, timeout
  http.TIMEOUT,timeout=req.timeout and math.floor(req.timeout/1000) or http.TIMEOUT, http.TIMEOUT
  if url:lower():match("^https") then
    response, status, headers = https.request(req)
  else 
    response, status, headers = http.request(req)
  end
  http.TIMEOUT = timeout
  local delay = math.random(1,3000)
  if response == 1 then 
    if options.success then options.success({status=status, headers=headers, data=table.concat(resp)}) end
  else
    if options.error then options.error(status) end
  end
end

_HC2_IP = _HC2_IP or "localhost:8888"
_HC2_USER = _HC2_USER  or "foo"
_HC2_PWD = _HC2_PWD or "bar"

__system = {}
function __system:savedb(name) return api.get('/proxy/system/db/save/'..name) end
function __system:copydb(name) return api.get('/proxy/system/db/copy/'..name) end
function __system:listdb() return api.get('/proxy/system/db/list/')  end
function __system:loaddb(name) return api.get('/proxy/system/db/load/'..name) end
function __system:removedb(name) return api.get('/proxy/system/db/remove/'..name) end

api={} -- Emulation of api.get/put/post
local function rawCall(dbg,method,call,data,cType)
  local resp = {}
  local req={ method=method, timeout=5000,
    url = "http://".._HC2_IP.."/api"..call,sink = ltn12.sink.table(resp),
    user=_HC2_USER,
    password=_HC2_PWD,
    headers={}
  }
  if data then
    req.headers["Content-Type"] = cType
    req.headers["Content-Length"] = #data
    req.source = ltn12.source.string(data)
  end
  local r, c = http.request(req)
  if not r then
    error("Error connnecting to HC2: '%s' - URL: '%s'.",c,req.url)
  end
  if c>=200 and c<300 then
    return resp[1] and json.decode(table.concat(resp)) or nil
  end
  error("HC2 returned error '%d %s' - URL: '%s'.",c,resp[1] or "",req.url)
end

function api.get(call) return rawCall(l,"GET",call) end
function api.put(call, data) return rawCall(l,"PUT",call,json.encode(data),"application/json") end
function api.post(call, data) return rawCall(l,"POST",call,json.encode(data),"application/json") end
function api.delete(call, data) return rawCall(l,"DELETE",call,json.encode(data),"application/json") end

function split(s, sep)
  local fields = {}
  sep = sep or " "
  local pattern = string.format("([^%s]+)", sep)
  string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
  return fields
end