local util = require("lib.util")
local recipes = { data = {} }
recipes.PATH = "data/recipes.dat"

-- Central 3x3 Grid for 9x3 chest
-- [ 4, 5, 6 ]
-- [13,14,15 ]
-- [22,23,24 ]
local GRID_SLOTS = {4, 5, 6, 13, 14, 15, 22, 23, 24}
local OUTPUT_SLOT = 16

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
    
    -- Scan ONLY the central grid slots
    for _, slot in ipairs(GRID_SLOTS) do
        local detail = p.getItemDetail(slot)
        if detail then
            table.insert(ingredients, {name = detail.name, count = 1, slot = slot})
        end
    end
    
    if #ingredients == 0 then return nil, "Сетка пуста! Выложите крафт в слоты 4,5,6, 13,14,15, 22,23,24" end
    
    local outDetail = p.getItemDetail(OUTPUT_SLOT)
    local output = nil
    if outDetail then
        output = {name = outDetail.name, count = outDetail.count}
    end
    
    return {
        output = output,
        ingredients = ingredients
    }
end

function recipes.get(itemName)
    local r = recipes.data[itemName]
    if r then
        return {
            {
                ingredients = r.ingredients,
                output_count = r.output_count or 1
            }
        }
    end
    return nil
end

function recipes.add(output_name, ingredients, count)
    recipes.data[output_name] = {
        ingredients = ingredients,
        output_count = count
    }
    recipes.save()
end

function recipes.arrange_grid(grid_name)
    if not grid_name then return end
    if _G.active_test then return end -- Don't move items while active test is running!
    
    local p = peripheral.wrap(grid_name)
    if not p then return end
    
    local list = p.list() or {}
    local workbench_to_grid = {
        [1] = 4,   [2] = 5,   [3] = 6,
        [10] = 13, [11] = 14, [12] = 15,
        [19] = 22, [20] = 23, [21] = 24
    }
    
    for from_slot, to_slot in pairs(workbench_to_grid) do
        local item = list[from_slot]
        if item then
            -- Try to push item to the corresponding central grid slot
            p.pushItems(grid_name, from_slot, item.count, to_slot)
        end
    end
end

return recipes
