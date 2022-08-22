local module = {}

local cachedFileIO = require "utils/cachedFileIO"
local resolve = require "resolve"
local logger = require "logger"
local json = require "json"
local fs = require "fs"
local fsutil = require "utils/fsutil"
local defaultFiles = require "defaultFiles"

local insert = table.insert
local remove = table.remove

-- local cachedFileIO = require "utils/cachedFileIO"
-- local resolve = require "resolve"

-- local cache = cachedFileIO.new()
-- local buildneed = resolve.resoleBuildlist("src","docs",cache)
-- logger.info(
--     buildneed
-- )

-- cache = cachedFileIO.new()
-- logger.info(
--     resolve.resolveBuildlistFromDependentTree("src","docs",cache,"src/eee.html")
-- )

local function waitter(item)
    local typeof = type(item)
    if typeof == "function" then
        return pcall(item)
    elseif typeof == "table" then
        if item.__name == "promise" then
            item:wait()
            return item:isSucceed()
        elseif item.__name == "promise.waitter" then
            local passed,err
            for _,promised in ipairs(item) do
                promised:wait()
                local lastPassed,lastError = promised:isSucceed()
                if not lastPassed then
                    logger.warnf("Error occurred on waitting promise.waitter %s\n%s",tostring(promised),tostring(lastError))
                end
                if passed then
                    passed,err = lastPassed,lastError
                end
            end
            return passed,err
        end
    end
    logger.warnf("Not supported waitter %s",tostring(item))
end

---@class builditem
---@field hash string Hash of file content
---@field name string the original name of file (src/...)
---@field shortName string short name, removed src/ from name
---@field removed boolean|nil status of this file was removed
---@field ext string extension of this file
---@field dependent table|nil after build, you can save dependents of file, this table should be array

---@class builderStatus
---@field out string output folder
---@field cache cachedFileIO cache file io
---@field rebuilds table list of object that should be rebuilded, such as markdown use this for call html builder
---@field buildedlist table list of object that builded well
---@field waitters table<number,function|promise> 

---build buildlist and save status
---@param buildneed table<number,builditem>
---@return table buildedlist list of builded objects
local function build(buildneed,out,cache,builder)
    ---@type builderStatus
    builder = builder or {
        out = out;
        cache = cache;
        buildedlist = {};
    }
    local rebuilds = {}
    builder.rebuilds = rebuilds
    local waitters = {}
    builder.waitters = waitters
    local buildedlist = builder.buildedlist

    -- build items
    for _,item in ipairs(buildneed) do
        local shortName = item.shortName
        logger.infof("   + Building %s",shortName)
        local passed,err = pcall(
            defaultFiles[item.ext] or defaultFiles["*"],
            item,builder
        )
        if passed then
            insert(buildedlist,item)
        else
            logger.warnf(
                "      * Error occurred on building %s\n        ignored and not added on builded list\n        %s",
                shortName,tostring(err):gsub("\n","\n        ")
            )
            local removed = 0
            for index,rebuildItem in ipairs(rebuilds) do
                if rebuildItem.shortName == shortName then
                    remove(rebuilds,index - removed)
                    removed = removed + 1
                end
            end
            if removed ~= 0 then
                logger.warn("      * removed from rebuild list")
            end
        end
    end

    -- wait for waitter
    for _,item in ipairs(waitters) do
        local usePcall = item.pcall
        local passed,err
        if type(item.pcall) == "boolean" and (not usePcall) then
            passed,err = item.item()
        else
            passed,err = waitter(item.item)
        end
        if not passed then
            local description = item.description
            local shortName = item.shortName
            logger.errorf(
                "Error occurred on running async tasks on file '%s'\nerr: %s%s",
                item.shortName,tostring(err),
                description and (
                    ("\ndescription: %s"):format(tostring(description))
                ) or ""
            )
            local removed = 0
            for index,rebuildItem in ipairs(rebuilds) do
                if rebuildItem.shortName == shortName then
                    remove(rebuilds,index - removed)
                    removed = removed + 1
                end
            end
            for index,buildedItem in ipairs(buildedlist) do
                remove(buildedlist,index)
                break
            end
        end
    end

    -- rebuild
    if next(rebuilds) then
        logger.infof("   * Rebuild %d items",#rebuilds)
        build(rebuilds,out,cache,builder)
    end

    return builder.buildedlist
end

---build buildlist and save status
---@param buildedlist table<number,builditem>
local function saveBuildstatus(buildedlist,out)
    local lastBuild,err = resolve.resolveLastBuildStatus(out)
    if not lastBuild then
        logger.errorf("Error occurred on saving last build status. try remove docs/build_status.json and rebuild to fix this error")
        return
    end

    local lastFiles = lastBuild.lastFiles
    if not lastFiles then
        lastFiles = {}
        lastBuild.lastFiles = lastFiles
    end

    for _,item in pairs(buildedlist) do
        if item.removed then
            lastFiles[item.shortName] = nil
        else
            lastFiles[item.shortName] = {
                hash = item.hash;
                dependent = item.dependent;
            }
        end
    end

    local passed
    passed,err = fs.writeFileSync(
        fsutil.concatPath(out,"build_status.json"),
        json.encode(lastBuild,{indent = true})
    )
    if not passed then
        logger.errorf("Error occurred on saving last build status. maybe file was locked by other process?\n%s",tostring(err))
    end
end

function module.cli(rawArgs)
    local remove = table.remove
    local argsParser = require "utils/argsParser"
    local command = remove(rawArgs,1)
    local unsupportedFormat = "Unsupported option '%s' got, please type 'proto help' to check all of options"

    if command == "help" then
        io.write([[Proto is lua based fast html, catscript builder

Command 'build'
    Check chagned file and build changed file now
    < Common options >
    --src|-s <directory>
        set source folder
        default is src
    --out|-o <directory>
        set output folder (include last builded data file)
        default is docs
    --watch|-w
        run watch mode with using file saved event
        all of files will builded as saved
    < Advanced options >
    --builder|-b <directory>
        import build scripts folder
        example: add name on txt file
        txt.lua
         | return function (filecontent,env)
         |     return "Qwreey made this!\n"..filecontent
         | end
    --hard|-h
        remove all of builded files and rebuild
        this is slower method. but should be fix many bugs

Command 'watch'
    Alias
]])
        return
    elseif command == "build" then
        local args,options,unsupported = argsParser.decode(rawArgs,{
            ["--src"] = "source";
            ["-s"] = "source";
            ["--out"] = "out";
            ["-o"] = "out";
            ["--watch"] = {name = "watch",takeData = false};
            ["-w"] = {name = "watch",takeData = false};
            ["--builder"] = {name = "watch",takeData = false};
            ["-b"] = {name = "watch",takeData = false};
        })
        if next(unsupported) then
            logger.errorf(unsupportedFormat,unsupported[1])
            return
        end

        local source = options["source"] or "src"
        local out = options["out"] or "docs"
        local watch = options["watch"]

        if watch then

        else -- just build
            local cache = cachedFileIO.new()
            local buildneed,err = resolve.resoleBuildlist(source,out,cache)
            if not buildneed then -- failed to make build list
                logger.info("Failed to make build list. error message was %s",err)
                return
            end

            if not next(buildneed) then -- have no changes
                logger.info("No files was changed. ignored")
                return
            end

            logger.infof("* All of changed file list (%d items)",#buildneed)
            for _,item in ipairs(buildneed) do
                logger.infof("   + %s",item.shortName)
            end
            logger.info("* Build started")
            local buildedlist = build(buildneed,out,cache)
            logger.info("* Build ended")
            saveBuildstatus(buildedlist,out)
            logger.info("* Saved build status")
        end
        return;
    end

    logger.errorf("Command '%s' was not found, please type 'proto help' to check all of commands",command)
end

return module
