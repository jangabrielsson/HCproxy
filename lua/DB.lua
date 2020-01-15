function makeDB(path)
  local DB_PATH = path
  local self = {}

  function self.getDBfiles()
    local files = {}
    for file in lfs.dir(DB_PATH) do
      if file ~= "." and file ~= ".." then
        local attr = lfs.attributes(DB_PATH..file)
        if attr and attr.mode=="file" and file:match("%w.db") then
          files[#files+1] = string.format("%-20s %s",file,os.date("%c",attr.modification))
        end
      end
    end
    return files
  end

  function self.save(name,rsrcs) return Utils.saveJson(DB_PATH..name..".db",turbo.escape.json_encode(rsrcs)) end

  function self.list()
    local stat,res = pcall(function()
        return self.getDBfiles()
      end)
    return stat,res
  end

  function self.load(name) return Utils.loadJson(CONFIG.DATAPATH..name..".db") end

  function self.remove(name) 
    return os.remove(DB_PATH..name..".db"),"ERR"
  end

  return self
end

return makeDB