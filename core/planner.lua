-- Crafting planner: build a dependency-ordered task tree for an item and
-- reserve the raw materials that must be pulled from storage.
local planner = {}
local recipes = require("core.recipes")
local storage = require("core.storage")

-- Plan `count` of `itemName`.
-- Returns: tasks (list, children-first), or nil, error_string
-- Each task: { id, name, count, recipe, batches, status, plan_id, order }
function planner.plan(itemName, count)
    local tasks = {}
    local pulled = {}          -- raw materials pulled from storage during planning
    local plan_id = "plan_" .. os.epoch("utc") .. "_" .. math.random(1000, 9999)

    -- Available stock minus what we've already virtually pulled this plan.
    local function localAvail(name)
        return math.max(0, storage.getAvailable(name) - (pulled[name] or 0))
    end

    -- Returns true, or false, error
    local function recurse(name, need)
        if need <= 0 then return true end

        -- Pull as much as we can from existing stock.
        local avail = localAvail(name)
        local take = math.min(avail, need)
        if take > 0 then
            pulled[name] = (pulled[name] or 0) + take
            need = need - take
        end
        if need <= 0 then return true end

        -- The rest must be crafted.
        local options = recipes.get(name)
        if not options or #options == 0 then
            return false, "No recipe for: " .. name
        end

        local recipe = options[1]
        local out_count = recipe.output_count or 1
        local batches = math.ceil(need / out_count)
        local crafted = batches * out_count

        -- Plan every ingredient (recursively). Group identical ingredients
        -- first so e.g. "8 planks" becomes one craft request, not eight.
        local grouped = {}
        for _, ing in ipairs(recipe.ingredients) do
            local n = ing.name
            grouped[n] = (grouped[n] or 0) + (ing.count or 1)
        end
        for n, c in pairs(grouped) do
            local ok, err = recurse(n, c * batches)
            if not ok then return false, err end
        end

        table.insert(tasks, {
            id = "task_" .. os.epoch("utc") .. "_" .. math.random(1000, 9999),
            name = name,
            count = crafted,
            recipe = recipe,
            batches = batches,
            status = "PENDING",
            plan_id = plan_id,
            order = #tasks + 1
        })
        return true
    end

    local ok, err = recurse(itemName, count)
    if not ok then return nil, err end

    -- Commit the raw-material reservations to global storage.
    local committed = {}
    for name, qty in pairs(pulled) do
        if not storage.reserve(name, qty) then
            -- Rollback everything we reserved for this plan.
            for rname, rqty in pairs(committed) do storage.release(rname, rqty) end
            return nil, "Failed to reserve resource: " .. name
        end
        committed[name] = qty
    end

    return tasks
end

-- Non-reserving feasibility check: can `count` of `itemName` be produced from
-- current stock + known recipes? Returns true, or false, "missing ..." string.
-- Does NOT reserve anything; safe to call for UI previews.
function planner.check(itemName, count)
    local pulled = {}
    local missing = {}
    local function localAvail(name)
        return math.max(0, storage.getAvailable(name) - (pulled[name] or 0))
    end
    local function recurse(name, need)
        if need <= 0 then return end
        local take = math.min(localAvail(name), need)
        if take > 0 then pulled[name] = (pulled[name] or 0) + take; need = need - take end
        if need <= 0 then return end
        local options = recipes.get(name)
        if not options or #options == 0 then
            missing[name] = (missing[name] or 0) + need
            return
        end
        local recipe = options[1]
        local out_count = recipe.output_count or 1
        local batches = math.ceil(need / out_count)
        local grouped = {}
        for _, ing in ipairs(recipe.ingredients) do
            grouped[ing.name] = (grouped[ing.name] or 0) + (ing.count or 1)
        end
        for n, c in pairs(grouped) do recurse(n, c * batches) end
    end
    recurse(itemName, count)
    if next(missing) then
        local list = {}
        for n, q in pairs(missing) do
            local short = n:match(":(.+)") or n
            table.insert(list, short .. " x" .. q)
        end
        table.sort(list)
        return false, "Missing: " .. table.concat(list, ", ")
    end
    return true
end

return planner
