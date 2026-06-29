-- Recipe storage, grid scanning and arrangement
local util = require("lib.util")
local recipes = { data = {} }
recipes.PATH = "data/recipes.dat"

-- Central 3x3 grid for a standard 9x3 (27 slot) chest.
-- Columns 4,5,6 are the center of a 9-wide chest.
--   [ 4, 5, 6 ]
--   [13,14,15 ]
--   [22,23,24 ]
recipes.GRID_SLOTS = { 4, 5, 6, 13, 14, 15, 22, 23, 24 }
recipes.OUTPUT_SLOT = 16

-- Map a workbench-style layout placed in the LEFT 3 columns of the chest
-- (cols 1,2,3) onto the central grid (cols 4,5,6). Relative position is
-- preserved, so an item placed "top-left" (slot 1) moves to the grid's
-- "top-left" (slot 4), exactly like a crafting table.
local WORKBENCH_TO_GRID = {
    [1]  = 4,  [2]  = 5,  [3]  = 6,
    [10] = 13, [11] = 14, [12] = 15,
    [19] = 22, [20] = 23, [21] = 24
}

function recipes.load()
    recipes.data = util.load(recipes.PATH) or {}
end

function recipes.save()
    if not fs.exists("data") then fs.makeDir("data") end
    util.save(recipes.PATH, recipes.data)
end

-- Read the central grid of the scanner chest and return the laid-out recipe.
-- Each occupied grid cell becomes one ingredient (count = 1, like a workbench).
-- The output slot (16) is read if present (used when saving a known result).
function recipes.get_from_grid(pName)
    local p = peripheral.wrap(pName)
    if not p then return nil, "Peripheral " .. tostring(pName) .. " not found" end

    local size = p.size() or 27
    if size < 27 then
        return nil, "Scanner chest must be standard (27 slots). Current: " .. size
    end

    local items = p.list()
    local ingredients = {}

    for _, slot in ipairs(recipes.GRID_SLOTS) do
        local detail = p.getItemDetail(slot)
        if detail then
            table.insert(ingredients, {
                name = detail.name,
                count = 1,
                slot = slot
            })
        end
    end

    if #ingredients == 0 then
        return nil, "Grid is empty! Place craft in center slots 4,5,6 / 13,14,15 / 22,23,24"
    end

    local outDetail = p.getItemDetail(recipes.OUTPUT_SLOT)
    local output = nil
    if outDetail then
        output = { name = outDetail.name, count = outDetail.count }
    end

    return {
        output = output,
        ingredients = ingredients
    }
end

-- Return the recipe(s) for an item as a list of {ingredients, output_count}.
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

-- Return true if a recipe exists for itemName.
function recipes.has(itemName)
    return recipes.data[itemName] ~= nil
end

-- Sorted list of all known recipes: {name, output_count, ingredients}.
function recipes.list()
    local list = {}
    for name, data in pairs(recipes.data) do
        table.insert(list, {
            name = name,
            output_count = data.output_count or 1,
            ingredients = data.ingredients
        })
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function recipes.add(output_name, ingredients, count)
    recipes.data[output_name] = {
        ingredients = ingredients,
        output_count = count or 1
    }
    recipes.save()
end

function recipes.remove(output_name)
    recipes.data[output_name] = nil
    recipes.save()
end

-- Auto-arrange items placed in the left 3 columns (workbench position) into
-- the central grid. Preserves relative position. No-op during an active test
-- craft so we never fight the in-progress craft.
function recipes.arrange_grid(grid_name)
    if not grid_name then return end
    if _G.active_test then return end

    local p = peripheral.wrap(grid_name)
    if not p then return end

    local list = p.list() or {}
    local op = 0

    for from_slot, to_slot in pairs(WORKBENCH_TO_GRID) do
        op = op + 1
        local item = list[from_slot]
        if item and not list[to_slot] then
            -- Only move into an empty destination to avoid merging different
            -- items; pushItems already refuses to mix, this just skips the call.
            p.pushItems(grid_name, from_slot, item.count, to_slot)
            os.sleep(0)
        elseif item and list[to_slot] and list[to_slot].name == item.name then
            -- Same item already in the grid cell -> stack it there.
            p.pushItems(grid_name, from_slot, item.count, to_slot)
            os.sleep(0)
        end
        util.maybeYield(op, 3)
    end
end

return recipes
