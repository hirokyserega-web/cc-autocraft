-- Task dispatcher and worker manager
local dispatcher = {}
local util = require("lib.util")
local storage = require("core.storage")

dispatcher.queue = {} -- [ {id, name, count, recipe, status} ]
dispatcher.workers = {} -- { [id] = { status, task_id, buffers={input, output} } }
dispatcher.PATH = "data/dispatcher.dat"

function dispatcher.save()
    local snapshot = {
        queue = dispatcher.queue,
        workers = dispatcher.workers
    }
    util.save(dispatcher.PATH, snapshot)
end

function dispatcher.updateStorageBuffers()
    storage.buffers = {}
    for _, w in pairs(dispatcher.workers) do
        if w.buffers then
            storage.buffers[w.buffers.input] = true
            storage.buffers[w.buffers.output] = true
        end
    end
end

function dispatcher.load()
    local data = util.load(dispatcher.PATH)
    if data then
        dispatcher.queue = data.queue or {}
        dispatcher.workers = data.workers or {}
    end
    dispatcher.updateStorageBuffers()
end

-- Автоматическое назначение буферов
function dispatcher.autoAssignBuffers(workerId)
    if not dispatcher.workers[workerId] then
        dispatcher.workers[workerId] = { status = "IDLE" }
    end
    
    if not dispatcher.workers[workerId].buffers then
        -- Ищем свободные сундуки
        storage.refresh()
        local available = {}
        
        -- Get names of all inventory peripherals
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
                -- Check if it is already assigned as a buffer to ANY worker
                local isAssigned = false
                for _, w in pairs(dispatcher.workers) do
                    if w.buffers and (w.buffers.input == name or w.buffers.output == name) then
                        isAssigned = true
                        break
                    end
                end
                -- Also skip active recipe grid chest
                if name == _G.GRID_NAME then
                    isAssigned = true
                end
                
                if not isAssigned then 
                    table.insert(available, name) 
                end
            end
        end
        
        if #available >= 2 then
            dispatcher.workers[workerId].buffers = {
                input = available[1],
                output = available[2]
            }
            util.log("Assigned buffers to worker " .. workerId .. ": IN=" .. available[1] .. " OUT=" .. available[2])
            dispatcher.updateStorageBuffers()
            dispatcher.save()
        else
            return false, "Not enough free chests for buffers"
        end
    end
    return true
end

function dispatcher.addTask(task)
    task.id = "task_" .. os.epoch("utc") .. "_" .. math.random(1000, 9999)
    task.status = "PENDING"
    table.insert(dispatcher.queue, task)
    dispatcher.save()
end

-- Prepare ingredients in the worker's input chest
local function prepare_ingredients(task, worker)
    local recipe = task.recipe
    local batches = task.batches or 1
    
    -- First clear the input chest to be completely safe
    local in_p = peripheral.wrap(worker.buffers.input)
    if in_p then
        for slot = 1, in_p.size() or 27 do
            local item = in_p.getItemDetail(slot)
            if item then
                storage.deposit(worker.buffers.input, slot, item.count)
            end
        end
    end
    
    -- Extract and place ingredients into correct slots
    for _, ing in ipairs(recipe.ingredients) do
        local needed = (ing.count or 1) * batches
        local extracted = storage.extract(ing.name, needed, worker.buffers.input, ing.slot)
        if extracted < needed then
            util.log("Error: could only extract " .. extracted .. "/" .. needed .. " of " .. ing.name)
        end
    end
end

-- Process the pending queue and dispatch tasks to IDLE workers
function dispatcher.processQueue()
    dispatcher.updateStorageBuffers()
    storage.refresh()
    
    local net = require("lib.net")
    
    for workerId, worker in pairs(dispatcher.workers) do
        if worker.status == "IDLE" and worker.buffers then
            -- Find the first pending task
            local pending_task = nil
            for _, t in ipairs(dispatcher.queue) do
                if t.status == "PENDING" then
                    pending_task = t
                    break
                end
            end
            
            if pending_task then
                util.log("Dispatching task " .. pending_task.name .. " to worker " .. workerId)
                
                -- Prepare the ingredients inside the worker's input chest
                prepare_ingredients(pending_task, worker)
                
                -- Set statuses
                pending_task.status = "ACTIVE"
                worker.status = "CRAFTING"
                worker.task_id = pending_task.id
                
                dispatcher.save()
                
                -- Send craft request
                net.send(workerId, "CRAFT_REQUEST", {
                    id = pending_task.id,
                    name = pending_task.name,
                    recipe = pending_task.recipe,
                    count = pending_task.count,
                    batches = pending_task.batches
                })
            end
        end
    end
end

-- Handle the result of a craft task
function dispatcher.handleResult(workerId, task_id, success, error_msg)
    local worker = dispatcher.workers[workerId]
    if not worker then return end
    
    -- Find the task
    local found_task = nil
    for _, t in ipairs(dispatcher.queue) do
        if t.id == task_id then
            found_task = t
            break
        end
    end
    
    if found_task then
        found_task.status = success and "COMPLETED" or "FAILED"
        found_task.error = error_msg
        
        -- Deposit all items from buffers.output back into general storage
        if worker.buffers and worker.buffers.output then
            local out_p = peripheral.wrap(worker.buffers.output)
            if out_p then
                local size = out_p.size() or 27
                for slot = 1, size do
                    local item = out_p.getItemDetail(slot)
                    if item then
                        storage.deposit(worker.buffers.output, slot, item.count)
                    end
                end
            end
        end
        
        -- Release reservations
        local recipe = found_task.recipe
        local batches = found_task.batches or 1
        for _, ing in ipairs(recipe.ingredients) do
            local needed = (ing.count or 1) * batches
            storage.release(ing.name, needed)
        end
    end
    
    -- Set worker back to idle
    worker.status = "IDLE"
    worker.task_id = nil
    
    -- Keep last 15 tasks in queue
    while #dispatcher.queue > 15 do
        table.remove(dispatcher.queue, 1)
    end
    
    dispatcher.save()
end

return dispatcher
