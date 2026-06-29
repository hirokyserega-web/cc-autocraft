-- Task dispatcher and worker manager
local dispatcher = {}
local util = require("lib.util")
local storage = require("core.storage")

dispatcher.queue = {}    -- [ {id, name, count, recipe, batches, status, plan_id, order, error} ]
dispatcher.workers = {}  -- { [id] = { status, task_id, buffers={input, output} } }
dispatcher.idle_count = 0
dispatcher.PATH = "data/dispatcher.dat"

-- Find (or auto-assign buffers for) the first IDLE worker in deterministic
-- (numeric, ascending) order. Returns workerId, worker, or nil + reason.
-- Worker selection must be deterministic: with two IDLE workers and one task,
-- the lower ID always wins, so the user knows which turtle will run.
function dispatcher.getReadyWorker()
    local ids = {}
    for id in pairs(dispatcher.workers) do table.insert(ids, id) end
    table.sort(ids, function(a, b) return a < b end)
    for _, id in ipairs(ids) do
        local w = dispatcher.workers[id]
        if w.status == "IDLE" then
            -- Auto-assign buffers if missing or invalid
            if not w.buffers or not util.isInventory(w.buffers.input) or not util.isInventory(w.buffers.output) then
                local ok, reason = dispatcher.autoAssignBuffers(id)
                if not ok then
                    util.log("Worker #" .. id .. " can't get buffers: " .. tostring(reason), "WARN")
                else
                    w = dispatcher.workers[id]
                end
            end
            if w.buffers and util.isInventory(w.buffers.input) and util.isInventory(w.buffers.output) then
                return id, w
            end
        end
    end
    return nil, "No IDLE worker with valid buffers"
end

function dispatcher.save()
    util.save(dispatcher.PATH, {
        queue = dispatcher.queue,
        workers = dispatcher.workers,
        reserved = storage.reserved
    })
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
        if data.reserved then
            for n, q in pairs(data.reserved) do
                storage.reserved[n] = (storage.reserved[n] or 0) + q
            end
        end
    end
    dispatcher.validateBuffers()
    dispatcher.updateStorageBuffers()
end

-- Drop any worker whose previously-assigned buffers are no longer reachable
-- (peripheral removed / renamed / computer rebooted with different device id).
function dispatcher.validateBuffers()
    for id, w in pairs(dispatcher.workers) do
        if w.buffers then
            local ok = util.isInventory(w.buffers.input) and util.isInventory(w.buffers.output)
            if not ok then
                w.buffers = nil
                if w.status == "CRAFTING" or w.status == "TESTING" then
                    w.status = "IDLE"
                    w.task_id = nil
                end
            end
        end
        os.sleep(0) -- Yield to prevent watchdog crash during worker buffer verification
    end
end

-- Assign specific input/output chests as this worker's buffers.
function dispatcher.assignWorkerBuffers(workerId, in_chest, out_chest)
    if not dispatcher.workers[workerId] then
        dispatcher.workers[workerId] = { status = "IDLE" }
    end
    if in_chest and out_chest then
        dispatcher.workers[workerId].buffers = {
            input = in_chest,
            output = out_chest
        }
        util.log("Assigned buffers to worker " .. workerId .. " via worker reporting: IN=" .. in_chest .. " OUT=" .. out_chest)
        dispatcher.updateStorageBuffers()
        dispatcher.save()
        return true
    end
    return false
end

-- Auto-assign two free inventory chests as this worker's input/output buffers.
function dispatcher.autoAssignBuffers(workerId)
    if not dispatcher.workers[workerId] then
        dispatcher.workers[workerId] = { status = "IDLE" }
    end

    if dispatcher.workers[workerId].buffers then
        -- Make sure those chests still exist.
        local b = dispatcher.workers[workerId].buffers
        if util.isInventory(b.input) and util.isInventory(b.output) then
            dispatcher.updateStorageBuffers()
            return true
        end
        dispatcher.workers[workerId].buffers = nil
    end

    local available = {}
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if util.isInventory(name) and name ~= _G.GRID_NAME then
            local isAssigned = false
            for _, w in pairs(dispatcher.workers) do
                if w.buffers and (w.buffers.input == name or w.buffers.output == name) then
                    isAssigned = true
                    break
                end
            end
            if not isAssigned then table.insert(available, name) end
        end
        os.sleep(0) -- Yield to prevent watchdog crash when scanning many peripherals
    end

    if #available >= 2 then
        dispatcher.workers[workerId].buffers = {
            input = available[1],
            output = available[2]
        }
        util.log("Assigned buffers to worker " .. workerId .. ": IN=" .. available[1] .. " OUT=" .. available[2])
        dispatcher.updateStorageBuffers()
        dispatcher.save()
        return true
    end
    return false, "Not enough free chests for buffers (need 2)"
end

function dispatcher.addTask(task)
    task.id = task.id or ("task_" .. os.epoch("utc") .. "_" .. math.random(1000, 9999))
    task.status = task.status or "PENDING"
    table.insert(dispatcher.queue, task)
    dispatcher.save()
end

-- A task is ready to run only if every earlier task in the same plan is done.
-- This serializes a single plan (children before parents) while still letting
-- independent plans run in parallel across workers.
local function isReady(t)
    if not t.plan_id then return true end
    for _, other in ipairs(dispatcher.queue) do
        if other.plan_id == t.plan_id
            and other.order and t.order
            and other.order < t.order
            and other.status ~= "COMPLETED" then
            return false
        end
    end
    return true
end

-- Move the recipe's ingredients from storage into the worker's input chest,
-- each into the slot that matches the original grid layout (preserves shape).
local function prepare_ingredients(task, worker)
    local recipe = task.recipe
    local batches = task.batches or 1

    -- Clear the input chest first.
    local in_p = peripheral.wrap(worker.buffers.input)
    if in_p then
        local size = in_p.size() or 27
        for slot = 1, size do
            local item = in_p.getItemDetail(slot)
            if item then storage.deposit(worker.buffers.input, slot, item.count) end
            util.maybeYield(slot, 8)
        end
    end

    -- Group ingredients by (name, slot) so each grid cell is filled correctly.
    local op = 0
    for _, ing in ipairs(recipe.ingredients) do
        op = op + 1
        local needed = (ing.count or 1) * batches
        local target_slot = ing.slot or 4
        local extracted = storage.extract(ing.name, needed, worker.buffers.input, target_slot)
        if extracted < needed then
            util.log("WARN: extracted " .. extracted .. "/" .. needed .. " of " .. ing.name .. " for " .. task.name)
        end
        util.maybeYield(op, 2)
    end
end

-- Dispatch one task per available worker, in task-queue order,
function dispatcher.processQueue()
    dispatcher.updateStorageBuffers()

    local net = require("lib.net")
    local workerId, worker

    workerId, worker = dispatcher.getReadyWorker()
    while worker do
        local pending_task = nil
        for _, t in ipairs(dispatcher.queue) do
            if t.status == "PENDING" and isReady(t) then
                pending_task = t
                break
            end
        end

        if pending_task then
            util.log("Dispatching " .. pending_task.name .. " x" .. pending_task.count .. " to worker " .. workerId)
            prepare_ingredients(pending_task, worker)

            pending_task.status = "ACTIVE"
            worker.status = "CRAFTING"
            worker.task_id = pending_task.id
            dispatcher.save()

            net.send(workerId, "CRAFT_REQUEST", {
                id = pending_task.id,
                name = pending_task.name,
                recipe = pending_task.recipe,
                count = pending_task.count,
                batches = pending_task.batches
            })
        else
            break
        end

        workerId, worker = dispatcher.getReadyWorker()
    end
end

-- Handle a finished craft task: deposit the output back into storage and
-- release the raw-material reservations this task consumed.
function dispatcher.handleResult(workerId, task_id, success, error_msg)
    local worker = dispatcher.workers[workerId]
    if not worker then return end

    local found_task = nil
    for _, t in ipairs(dispatcher.queue) do
        if t.id == task_id then found_task = t break end
    end

    if found_task then
        found_task.status = success and "COMPLETED" or "FAILED"
        found_task.error = error_msg

        -- Deposit everything in the output buffer back into general storage.
        if worker.buffers and worker.buffers.output then
            local out_p = peripheral.wrap(worker.buffers.output)
            if out_p then
                local size = out_p.size() or 27
                for slot = 1, size do
                    local item = out_p.getItemDetail(slot)
                    if item then storage.deposit(worker.buffers.output, slot, item.count) end
                    util.maybeYield(slot, 8)
                end
            end
        end

        -- Release reservations for the raw ingredients this task used.
        local recipe = found_task.recipe
        local batches = found_task.batches or 1
        for _, ing in ipairs(recipe.ingredients) do
            local needed = (ing.count or 1) * batches
            storage.release(ing.name, needed)
        end
    end

    worker.status = "IDLE"
    worker.task_id = nil

    -- Keep only the most recent 20 tasks in the queue.
    while #dispatcher.queue > 20 do
        table.remove(dispatcher.queue, 1)
    end

    dispatcher.save()
end

-- Exported for testing / reuse.
dispatcher.isReady = isReady

return dispatcher
