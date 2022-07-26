
-- TODO : ignore files (.buildignore)

local module = {}

local hash       = require "hash"
local json       = require "json"
local fs         = require "fs"
local fsutil     = require "utils/fsutil"
local logger     = require "logger"
local promise    = require "promise"
local void       = require "utils/void"

local insert     = table.insert
local concatPath = fsutil.concatPath

local recursiveFilesListAsync = promise.async(fsutil.recursiveFilesList)
recursiveFilesListAsync:catch(void)

--- check file was changed
local function resolveFileChanged(filename,shortName,lastFiles,cachedFileIO,cachedHash)
    local lastFile = lastFiles[shortName]
    local fileHash = cachedHash[shortName]
    if not fileHash then
        local file,err = cachedFileIO:read(filename)
        if not file then -- if removed
            if err:match"ENOENT" then
                cachedHash[filename] = "REMOVED"
                return true,lastFile,fileHash
            end
            error(("error occured on load file %s. %s"):format(filename,err))
        end
        fileHash = hash(file)
        cachedHash[shortName] = fileHash
    elseif fileHash == "REMOVED" then
        return true,lastFile,fileHash
    end

    if (not lastFile) or lastFile.hash ~= fileHash then
        return true,lastFile or false,fileHash
    end
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

local function resolveDependentTree(filename,SRC_PATH,cachedFileIO,lastFiles,buildlist,checked)
    buildlist = buildlist or {}
    checked = checked or {}
    local shortName = filename:sub(#SRC_PATH+2,-1)

    -- if checked already, ignore
    if checked[shortName] then return end
    checked[shortName] = true

    local file,err = cachedFileIO:read(filename)
    if file then
        insert(buildlist,{
            hash = hash(file);
            name = filename;
            shortName = shortName;
        })
    else
        insert(buildlist,{
            name = shortName;
            shortName = shortName;
            removed = true;
        })
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
local function resolveBuildNeeded(filename,SRC_PATH,lastFiles,cachedFileIO,cachedHash)
    local shortName = filename:sub(#SRC_PATH+2,-1)
    local changed,lastFile,fileHash
    = resolveFileChanged(filename,shortName,lastFiles,cachedFileIO,cachedHash)

    if changed then
        return true,shortName,lastFile,fileHash
    end

    ---@diagnostic disable-next-line
    local dependent = lastFile.dependent
    if not dependent then return end

    local buildNeeded
    for _,depend in ipairs(dependent) do
        buildNeeded = resolveBuildNeeded(concatPath(SRC_PATH,depend),SRC_PATH,lastFiles,cachedFileIO,cachedHash)
        if buildNeeded then
            return true,shortName,lastFile,fileHash
        end
    end
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

    local lastFiles = buildStatus.lastFiles or {}
    local buildlist = {}

    -- wait for src scan
    local srcFileList = srcFileListPromise:await()
    if srcFileListPromise:isFailed() then
        logger.errorf("Error occured while reading src file list\n%s",srcFileList)
        return "UNABLE TO READ SRC FOLDER"
    end

    local cachedHash = {} -- make hash cache table

    -- check build needed
    for _,filename in ipairs(srcFileList) do
        local buildNeeded,shortName,lastFile,fileHash
        = resolveBuildNeeded(filename,SRC_PATH,lastFiles,cachedFileIO,cachedHash)
        if buildNeeded then
            insert(buildlist,{
                hash = fileHash;
                name = filename;
                shortName = shortName;
            })
        end
    end

    -- check removed files
    for shortName,_ in pairs(lastFiles) do
        local pass,err = cachedFileIO:read(concatPath(SRC_PATH,shortName))
        if (not pass) and err and err:match"ENOENT" then
            insert(buildlist,{
                name = shortName;
                shortName = shortName;
                removed = true;
            })
        end
    end

    return buildlist
end

return module
