-- Crafting planner
local planner = {}
local recipes = require("core.recipes")
local storage = require("core.storage")

function planner.plan_recursive(itemName, count, tasks, reserves, planned)
    tasks = tasks or {}
    reserves = reserves or {}
    planned = planned or {}
    
    -- Helper to calculate available quantity taking into account current temporary reserves and planned additions
    local function get_temp_available(name)
        local total_cached = storage.cache[name] or 0
        local global_reserved = storage.reserved[name] or 0
        local temp_reserved = reserves[name] or 0
        local temp_planned = planned[name] or 0
        return math.max(0, total_cached - (global_reserved + temp_reserved) + temp_planned)
    end
    
    local avail = get_temp_available(itemName)
    local needed = count - avail
    
    if needed <= 0 then
        -- We have enough available (either in stock or planned)
        reserves[itemName] = (reserves[itemName] or 0) + count
        return true, tasks
    end
    
    -- Reserve what is currently available
    if avail > 0 then
        reserves[itemName] = (reserves[itemName] or 0) + avail
    end
    
    -- Find recipe for the remaining needed count
    local options = recipes.get(itemName)
    if not options or #options == 0 then
        return false, "No recipe for " .. itemName
    end
    
    local recipe = options[1]
    local recipe_out_count = recipe.output_count or 1
    local batches = math.ceil(needed / recipe_out_count)
    
    -- Plan all ingredients
    for _, ing in ipairs(recipe.ingredients) do
        -- For each ingredient, we need ing.count * batches
        -- Default to count = 1 if not specified (since our grid has 1 item per slot)
        local ing_count = ing.count or 1
        local ok, err = planner.plan_recursive(ing.name, ing_count * batches, tasks, reserves, planned)
        if not ok then
            return false, err
        end
    end
    
    -- Mark the crafted items as planned additions
    local total_crafted = batches * recipe_out_count
    planned[itemName] = (planned[itemName] or 0) + total_crafted
    
    -- Reserve the needed amount from the newly planned items
    reserves[itemName] = (reserves[itemName] or 0) + needed
    
    -- Add the crafting task
    table.insert(tasks, {
        id = "task_" .. os.epoch("utc") .. "_" .. math.random(1000, 9999),
        name = itemName,
        count = total_crafted,
        recipe = recipe,
        batches = batches,
        status = "PENDING"
    })
    
    return true, tasks
end

-- Public planning interface
function planner.plan(itemName, count)
    local tasks = {}
    local reserves = {}
    local planned = {}
    
    local ok, err = planner.plan_recursive(itemName, count, tasks, reserves, planned)
    if not ok then
        return nil, err
    end
    
    -- Apply global reservations
    local reserved_so_far = {}
    for name, qty in pairs(reserves) do
        local success = storage.reserve(name, qty)
        if not success then
            -- Rollback
            for r_name, r_qty in pairs(reserved_so_far) do
                storage.release(r_name, r_qty)
            end
            return nil, "Failed to reserve ingredient: " .. name
        end
        reserved_so_far[name] = qty
    end
    
    return tasks
end

return planner
