local module = {}

local cachedFileIO = require "utils/cachedFileIO"

local cache = cachedFileIO.new()
require"resolve".resoleBuildlist("src","docs",cache)