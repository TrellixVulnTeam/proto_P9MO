local module = {}

local cachedFileIO = require "utils/cachedFileIO"
local resolve = require "resolve"
local logger = require "logger"

local cache = cachedFileIO.new()
logger.info(
    resolve.resoleBuildlist("src","docs",cache)
)

cache = cachedFileIO.new()
logger.info(
    resolve.resolveBuildlistFromDependentTree("src","docs",cache,"src/eee.html")
)