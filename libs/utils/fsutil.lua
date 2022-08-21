
local module = {}
local fs = require "fs"
local spawn = require("coro-spawn")

local osname = jit.os
local insert = table.insert
local concat = table.concat
local format = string.format
local gmatch = string.gmatch
local match  = string.match
local gsub   = string.gsub

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

function module.mkpath(path)
    local dir
    for str in gmatch(path,"[^/]+") do
        if dir then
            dir = concatPath(dir,str)
        else dir = str
        end
        fs.mkdirSync(dir)
    end
end

function module.getExt(path)
    return match(path,"%.([^.]+)$")
end

function module.getParent(path)
    return match(path,"(.+)/[^/+]")
end

function module.copy(from,to)
    local proc,err
    if osname == "Windows" then
        proc,err = spawn("copy",{
            args = {
                from:gsub("/","\\");
                to:gsub("/","\\");
            };
            stdio = {nil,nil,true};
        })
    else
        proc,err = spawn("cp",{
            args = {from,to};
            stdio = {nil,nil,true};
        })
    end
    if not proc then
        error(err)
    end
    local exitcode = proc.waitExit()
    if exitcode ~= 0 then
        local stderr = {}
        for str in proc.stderr.read do
            insert(stderr,str)
        end
        error(gsub(concat(stderr),"\n+$",""))
    end
end

return module
