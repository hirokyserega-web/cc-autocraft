local util = require("lib.util")
local recipes = { data = {} }
recipes.PATH = "data/recipes.dat"

function recipes.load()
    recipes.data = util.load(recipes.PATH) or {}
end

function recipes.save()
    if not fs.exists("data") then fs.makeDir("data") end
    util.save(recipes.PATH, recipes.data)
end

function recipes.get_from_grid(pName)
    local p = peripheral.wrap(pName)
    if not p then return nil, "Peripheral " .. tostring(pName) .. " not found" end
    
    local items = p.list()
    local ingredients = {}
    
    -- We assume slots 1-9 are the 3x3 grid, slot 16 is the output
    for i = 1, 9 do
        local detail = p.getItemDetail(i)
        if detail then
            table.insert(ingredients, {name = detail.name, count = 1, slot = i})
        end
    end
    
    local outDetail = p.getItemDetail(16)
    if not outDetail then return nil, "Put the result item in slot 16" end
    if #ingredients == 0 then return nil, "Grid is empty" end
    
    return {
        output = {name = outDetail.name, count = outDetail.count},
        ingredients = ingredients
    }
end

function recipes.add(output_name, ingredients, count)
    recipes.data[output_name] = {
        ingredients = ingredients,
        output_count = count
    }
    recipes.save()
end

return recipes
