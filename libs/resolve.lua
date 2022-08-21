
-- TODO : ignore files (.buildignore)

local module = {}

local hash        = require "utils/hash"
local json        = require "json"
local fs          = require "fs"
local fsutil      = require "utils/fsutil"
local logger      = require "logger"
local promise     = require "promise"
local void        = require "utils/void"

local insert      = table.insert
local concatPath  = fsutil.concatPath

local maxSizeMB   = 10
local maxSizeByte = maxSizeMB * 1000000

local recursiveFilesListAsync = promise.async(fsutil.recursiveFilesList):catch(void)

--- check file was changed
---@return any fileWasChanged
---@return any lastFileBuildStatus
---@return any fileHash this is will nil if file not exist
local function resolveFileChanged(filename,shortName,lastFiles,cachedFileIO,cachedHash)
    local lastFile = lastFiles[shortName]
    local fileHash = cachedHash[shortName]
    if not fileHash then -- cached not found (read)
        local file,err = cachedFileIO:read(filename)
        if not file then
            -- if removed
            if err:match"ENOENT" then
                cachedHash[filename] = "REMOVED"
                return true,lastFile,nil
            end

            -- error on reading
            logger.errorf("Failed to load file %s. Ignored (%s)",filename,err)
            return false,nil,nil
        end
        fileHash = hash(file)
        cachedHash[shortName] = fileHash
    elseif fileHash == "REMOVED" then
        return true,lastFile,nil -- if removed (cached)
    end

    -- if hash changed
    if (not lastFile) or lastFile.hash ~= fileHash then
        return true,lastFile or false,fileHash
    end

    -- not changed
    return false,lastFile,fileHash
end
module.resolveFileChanged = resolveFileChanged

--- get last build status from OUT_PATH
local function resolveLastBuildStatus(OUT_PATH)
    local buildStatusPath = concatPath(OUT_PATH,"build_status.json")

    local buildStatus,buildStatusERR = fs.readFileSync(buildStatusPath)
    if not buildStatus then
        if buildStatusERR and buildStatusERR:match"ENOENT" then
            logger.info "Last build status file not found from OUT_PATH, just make one"
            buildStatus = {}
        else
            logger.errorf("Error occured while reading last build status\n%s",tostring(buildStatusERR))
            return nil,"UNABLE TO RESOLVE BUILD LIST"
        end
    else
        buildStatus = json.decode(buildStatus)
        if not buildStatus then
            logger.error "Unable to decode build_status.json, maybe file was corrupted?"
            return nil,"UNABLE TO RESOLVE BUILD LIST"
        end
    end
    return buildStatus
end
module.resolveLastBuildStatus = resolveLastBuildStatus

--- resolve dependent tree, select one file and check where that file used on
local function resolveDependentTree(filename,SRC_PATH,cachedFileIO,lastFiles,buildlist,checked)
    buildlist = buildlist or {}
    checked = checked or {}
    local shortName = filename:sub(#SRC_PATH+2,-1)

    -- if checked already, ignore
    if checked[shortName] then return end
    checked[shortName] = true

    local removed,add
    if not cachedFileIO:checkCached(filename) then
        local stat,err = fs.statSync(filename)
        if (not stat) and err and err:match"ENOENT" then
            
        end
        if stat.size >= maxSizeByte then return false,("File %s exceed maximum file size %dMB. Ignored"):format(filename,maxSizeMB) end
    end
    local file,err = cachedFileIO:read(filename)
    if file then
        insert(buildlist,{
            hash = hash(file);
            name = filename;
            shortName = shortName;
            ext = fsutil.getExt(shortName);
        })
    elseif err and err:match"ENOENT" then
        insert(buildlist,{
            name = shortName;
            shortName = shortName;
            removed = true;
            ext = fsutil.getExt(shortName);
        })
    else
        logger.error("Error")
    end

    for child,item in pairs(lastFiles) do
        local dependent = item.dependent
        if dependent then
            for _,depend in ipairs(dependent) do
                if depend == shortName then
                    resolveDependentTree(concatPath(SRC_PATH,child),SRC_PATH,cachedFileIO,lastFiles,buildlist,checked)
                    break
                end
            end
        end
    end

    return buildlist
end

--- make buildlist from one file (using dependent tree). this is reversed version of resoleBuildlist(trace one file to list <=> whole to list)
local function resolveBuildlistFromDependentTree(SRC_PATH,OUT_PATH,cachedFileIO,filename)
    local buildStatus,buildStatusERR = resolveLastBuildStatus(OUT_PATH)
    if not buildStatus then -- if errored while reading last build status
        return nil,buildStatusERR
    end

    local lastFiles = buildStatus.lastFiles or {}
    return resolveDependentTree(filename,SRC_PATH,cachedFileIO,lastFiles)
end
module.resolveBuildlistFromDependentTree = resolveBuildlistFromDependentTree

--- check dependent/file chaged status and return is build nedded
---@return boolean buildNeeded status of file that should be updated
---@return string|nil shortNameOrErr shorted name
---@return table|nil lastFileBuildStatus
---@return string|nil fileHash if file was removed, this value will nil
local function resolveBuildNeeded(filename,SRC_PATH,lastFiles,cachedFileIO,cachedHash)
    local shortName = filename:sub(#SRC_PATH+2,-1)

    -- check removed / size of file
    local stat,err = fs.statSync(filename)
    if (not stat) and err and err:match"ENOENT" then -- not found
        return true,shortName,lastFiles[shortName],nil
    elseif (not stat) then
        return false,("Unknown error occurred on reading file %s stat. Ignored"):format(tostring(err))
    end

    -- exceed size
    if stat.size >= maxSizeByte then return false,("File %s exceed maximum file size %dMB. Ignored"):format(filename,maxSizeMB) end

    -- check changed
    local changed,lastFile,fileHash
    = resolveFileChanged(filename,shortName,lastFiles,cachedFileIO,cachedHash)
    if changed then
        return true,shortName,lastFile,fileHash
    end

    -- check dependent
    local dependent = lastFile.dependent
    if not dependent then return false end
    local buildNeeded
    for _,depend in ipairs(dependent) do
        buildNeeded = resolveBuildNeeded(concatPath(SRC_PATH,depend),SRC_PATH,lastFiles,cachedFileIO,cachedHash)
        if buildNeeded then
            return true,shortName,lastFile,fileHash
        end
    end

    return false
end
module.resolveBuildNeeded = resolveBuildNeeded

--- make buildlist by check hash of each files
function module.resoleBuildlist(SRC_PATH,OUT_PATH,cachedFileIO)
    ---@type promise
    local srcFileListPromise = recursiveFilesListAsync(SRC_PATH)
    local buildStatus,buildStatusERR = resolveLastBuildStatus(OUT_PATH)
    if not buildStatus then -- if errored while reading last build status
        return nil,buildStatusERR
    end

    local lastFiles = buildStatus.lastFiles or {} -- last build data
    local buildlist = {} -- build list
    local cachedHash = {} -- make hash cache table

    -- wait for src scan
    local srcFileList = srcFileListPromise:await()
    if srcFileListPromise:isFailed() then
        logger.errorf("Error occured while reading src file list\n%s",srcFileList)
        return nil,"UNABLE TO READ SRC FOLDER"
    end

    -- check build needed in scaned src
    for _,filename in ipairs(srcFileList) do
        local buildNeeded,shortName,lastFile,fileHash
        = resolveBuildNeeded(filename,SRC_PATH,lastFiles,cachedFileIO,cachedHash)
        if buildNeeded then
            insert(buildlist,{
                hash = fileHash;
                name = filename;
                shortName = shortName;
                ext = fsutil.getExt(shortName);
            })
        elseif shortName then -- ignored reason e) file size too big
            logger.warn(shortName);
        end
    end

    -- check removed files
    for shortName,_ in pairs(lastFiles) do
        if not cachedFileIO:checkCached() then
            local pass,err = fs.statSync(concatPath(SRC_PATH,shortName));
            if (not pass) and err and err:match"ENOENT" then
                insert(buildlist,{
                    name = shortName;
                    shortName = shortName;
                    removed = true;
                    ext = fsutil.getExt(shortName);
                })
            end
        end
    end

    -- local function checkRemoved (shortName)
    --     if not cachedFileIO:checkCached() then
    --         local pass,err = fs.statSync(concatPath(SRC_PATH,shortName));
    --         if (not pass) and err and err:match"ENOENT" then
    --             insert(buildlist,{
    --                 name = shortName;
    --                 shortName = shortName;
    --                 removed = true;
    --             })
    --         end
    --     end
    -- end
    -- local checkRemoved_waitter = promise.waitter()
    -- for shortName,_ in pairs(lastFiles) do
    --     checkRemoved_waitter:add(
    --         promise.new(checkRemoved,shortName)
    --     )
    -- end

    return buildlist
end

return module
