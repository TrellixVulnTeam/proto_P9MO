local fsutil = require("utils/fsutil")
local insert = table.insert
local concatPath = fsutil.concatPath
local fs = require("fs")

local function unlinkSync(path)
    local passed,err = fs.unlinkSync(path)
    if not passed then
        if err:match("ENOENT:") then return end
        error(err)
    end
end

return {
    -- ["md"] = function (object,builder)
    --     local lastFrom = object.from;
    --     local tindex = builder.tmpIndex;
    --     local name = object.name:gsub("/","-");
    --     local newFrom = concat{concatPath(builder.tmp,tindex),"_",name};
    --     builder.tmpIndex = tindex + 1;
    --     local mdbuilder = builder.mdbuilder;
    --     if not mdbuilder then
    --         mdbuilder = buildMD.init();
    --         builder.mdbuilder = mdbuilder;
    --     end
    --     insert(builder.waitter,buildMD.buildAsync(mdbuilder,{
    --         from = lastFrom;
    --         to = newFrom;
    --     }));
    --     insert(builder.rebuild,{
    --         ext = "html";
    --         from = newFrom;
    --         name = object.name;
    --         to = object.to:sub(1,-4) .. ".html";
    --     });
    -- end;
    -- ["html"] = function (object,builder)
    --     local this = fs.readFileSync(object.from);
    --     if not this:match("<!--DO NOT BUILD-->") then
    --         -- call the html builder (custom html var)
    --         this = buildHTML.build(this,setmetatable(object,{__index = env}));
    --     end
    --     mkfile(object.to);
    --     fs.writeFileSync(object.to,this);
    -- end;
    ---@param object builditem
    ---@param builder builderStatus
    ["*"] = function (object,builder)
        local shortName = object.shortName
        local to = concatPath(builder.out,shortName)

        if object.removed then
            insert(builder.waitters,{
                description = "File removing (calling fs.unlinkSync)";
                shortName = shortName;
                item = promise.new(unlinkSync,to);
            })
            return
        end

        insert(builder.waitters,{
            description = "File copying (calling fsutil.copy)";
            shortName = shortName;
            item = promise.new(fsutil.copy,object.name,to)
        });
    end;
}