-- Crafting planner
local planner = {}
local recipes = require("core.recipes")
local storage = require("core.storage")

function planner.plan(itemName, count, tasks)
    tasks = tasks or {}
    
    local available = storage.getAvailable(itemName)
    local needed = count - available
    
    if needed <= 0 then
        -- Все есть на складе, резервируем
        if not storage.reserve(itemName, count) then
            return nil, "Failed to reserve " .. itemName
        end
        return tasks
    end
    
    -- Пытаемся зарезервировать то, что есть
    if available > 0 then
        storage.reserve(itemName, available)
    end
    
    -- Ищем рецепт для 'needed'
    local options = recipes.get(itemName)
    if not options or #options == 0 then
        return nil, "No recipe for " .. itemName
    end
    
    -- Берем первый доступный рецепт (упрощение)
    local recipe = options[1]
    local batches = math.ceil(needed / recipe.output_count)
    
    for _, ing in ipairs(recipe.ingredients) do
        local ok, err = planner.plan(ing.name, ing.count * batches, tasks)
        if not ok then return nil, err end
    end
    
    table.insert(tasks, {
        name = itemName,
        count = batches * recipe.output_count,
        recipe = recipe,
        batches = batches
    })
    
    return tasks
end

return planner
