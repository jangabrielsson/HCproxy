require("lua/json")
local a = json.encode("ABC")

local function loadJson(file)
  local stat,res = pcall(function()
      local f = io.open(file)
      local rsrcs = turbo.escape.json_decode(f:read("*all"))
      f:close()
      return rsrcs
    end)
  return stat,res
end

local function saveJson(file,data)
  local stat,res = pcall(function()
      data = turbo.escape.json_encode(data)
      local f = io.open(file,"w")
      f:write(data)
      f:close()
      return true
    end)
  return stat,res
end

local function setPath(t,path,value)
  path = split(path,"/")
  for i=1,#path-1 do 
    local p = path[i]
    t[p] = t[p] == nil and {} or t[p]
    t = t[p] 
  end
  t[path[#path]] = value
end

local function base64(data)
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x) 
          local r,b='',x:byte()
          for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
          return r;
        end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
      end)..({ '', '==', '=' })[#data%3+1])
end

local function getDefault(value,default) if value ~= nil then return value else return default end end
return {
  loadJson = loadJson,
  saveJson = saveJson,
  getDefault = getDefault,
  base64 = base64,
  setPath = setPath,
}