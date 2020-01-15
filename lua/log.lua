require("HC2_api")
ltn12 = require("ltn12")
socket = require("socket")

if os.getenv("HC2DOCK")=="TRUE" then
  _HC2_IP = "HC2proxy:8888"
end

local fmt = string.format
function printf(...) io.write(fmt(...).."\n") io.flush() end

function makeTable()
  local self = {}
  local dirty,linesMap,linesARr = false,{},{}
  local eIndex = {
    property = function(e) return "1"..e.type..e.deviceID end,
    global = function(e) return "2"..e.type..e.name end,
  }
  local function getIndex(e) return eIndex[e.type] and eIndex[e.type](e) or "3"..json.encode(e) end 
  function self.add(e,line)
    local i = getIndex(e)
    if linesMap[i] then
      if linesMap[i].line ~= line then
        linesMap[i].line = line
        linesMap[i].dirty = true
      end
    else
      local l = {line = line, dirty=true, index=i}
      linesArr[#linesArr+1]=l
      table.sort(linesArr,function(a,b) return a.index <= b.index end)
      linesMap[i] = l
    end
  end
  function self.print()
    if #lines > 0 then
      io.write("\027[H")
    end
  end
  return self
end

logFuns={
  property = function(e) return fmt("ID:%-10s value:%s",e.deviceID,e.value) end,
  global = function(e)   return fmt("name:%-8s value:%s",e.name,e.value) end,
}

function logEvent(e)
  local res = fmt("%s type:%-15s",os.date("%m/%d %X",e._time),e.type)
  if logFuns[e.type] then res = res.. logFuns[e.type](e) end
  return fmt("%-80s",res)
end

function main()

  local last = ""
  interval = 1000
  local function pollEvent()
    local stat,res = pcall(function()
        es = api.get("/proxy/event/"..last)
        if #es>0 then last=es[#es]._uid end
        for i=1,#es do
          printf("%s",logEvent(es[i]))
        end
      end)
    if not stat then interval = math.min(interval+500,3000)
    else interval = 1000 end
    setTimeout(pollEvent,interval)
  end

  pollEvent()
end
--io.write("\027[2J")
--io.write("\027[H\027[2J")
--io.write("\027[H")
-- os.execute("cls")


-----------------

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

Runtime = createRuntime()
setTimeout = Runtime.startTimer

---------------------------
setTimeout(main,0)
Runtime.runTimers()