
local module = {}
local fs = require "fs"

local insert = table.insert
local concat = table.concat
local format = string.format

local concatPathFormat = "%s/%s"
---Concat to path or more
---@param base string base path
---@param child string secound path
---@param ... string other paths
---@return string concatedString concated path
function module.concatPath(base,child,...)
    if select("#",child) == 0 then
        return format(concatPathFormat,base,child)
    end
    return concat({base,child,...},"/")
end
local concatPath = module.concatPath

---get whole file list from path, this function will doing recursive to make file list
---@param path string
---@return string list The whole files list of path
local function recursiveGetFilesList(path,list,fullPath)
    fullPath = fullPath or path
    list = list or {}
    for name,typeof in fs.scandirSync(path) do
        if typeof == "file" then
            insert(list,concatPath(fullPath,name))
        elseif typeof == "directory" then
            recursiveGetFilesList(concatPath(fullPath,name),list)
        end
    end
    return list
end
function module.recursiveFilesList(path)
    return recursiveGetFilesList(path)
end

return module
