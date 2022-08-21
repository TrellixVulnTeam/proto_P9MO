local module = {dir = (...):gsub("%.","/")};

local IPC = require("IPC");
local promise = require("promise");

function module.init()
    local server = IPC.new({"python","python3"},{"build/buildMD/main.py"},true," pydown");
    local this = {server = server};
    setmetatable(this,module);
    return this;
end

module.__index = module;
function module:build(content)
    return self.server:request(content);
end
module.buildAsync = promise.async(module.build);

function module:kill()
    self.server:kill();
end

return module;
