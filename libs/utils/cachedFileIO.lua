local fs = require "fs"
local pathModule = require "path"
local module = {} ---@class cachedFileIO
module.__index = module

local resolve = pathModule.resolve
local readFileSync = fs.readFileSync
local writeFileSync = fs.writeFileSync

---Check is cached
---@param path string path of file (will be resolved automatically)
---@return boolean|string status file is cached
function module:checkCached(path)
    return self.storage[resolve(path)] or false
end

---Read file and save into cache storage
---@param path string path of file (will be resolved automatically)
---@return boolean|string fileContent content of file, if failed to load file, it will be false and error information will given on next return value
---@return string|nil fileContentOrErr if error occured, this value will describle what happened
function module:read(path)
    local file,err = readFileSync(path)
    if not file then return false,err end
    self.storage[resolve(path)] = file
    return file
end

---Write file and save into cache storage
---@param path string path of file (will be resolved automatically)
---@param str string content of file
---@return boolean isPassed status of work was successed well
---@return string|nil error if error occured, this value will describle what happened
function module:write(path,str)
    local pass,err = writeFileSync(path,str)
    if not pass then return false,err end
    self.storage[resolve(path)] = str
    return true
end

function module:clean()
    self.storage = {}
end

---@return cachedFileIO
function module.new()
    return setmetatable({storage = {}},module)
end

return module
