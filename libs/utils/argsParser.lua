local module = {}
local insert = table.insert
local match = string.match
local sub = string.sub

local function getArgInfo(optionArgs,name)
    local this = optionArgs[name]
    if type(this) == "string" then
        return {name = this,takeData = true}
    end
    return this
end

function module.decode(splited,optionArgs)
	optionArgs = optionArgs or {}
	local option = {}
	local args = {}
	local unsupported = {}

	local lastOpt

	for i,this in ipairs(splited) do
		if i >= 1 then
			-- when --test=test format
			local name,value = match(this,"(%-%-?.-)=(.*)")
			if name then
			    local argInfo = getArgInfo(optionArgs,name)
				if argInfo then
				    option[argInfo.name] = value
				else
				    -- if arg info not found
				    insert(unsupported,this)
				end
			-- when --test
			elseif sub(this,1,1) == "-" then
				-- for allow option to receive data
				-- keep option name for next data
				lastOpt = nil
				local argInfo = getArgInfo(optionArgs,this)
				if argInfo then
				    option[this] = true
				    if argInfo.takeData then
				        lastOpt = argInfo.name    
				    end
				else
				    -- if arg info not found
				    insert(unsupported,this)
				end
			-- after --test, set data
			elseif lastOpt then
				option[lastOpt] = this
				lastOpt = nil
			-- if it is just args, keep in args table
			else
				insert(args,this)
			end
		end
	end

	return args,option,unsupported
end
return module
