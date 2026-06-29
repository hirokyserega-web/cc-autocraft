-- Task dispatcher and worker manager
local dispatcher = {}
local util = require("lib.util")
local storage = require("core.storage")

dispatcher.queue = {} -- [ {id, name, count, recipe, status} ]
dispatcher.workers = {} -- { [id] = { status, task_id, buffers={in, out} } }
dispatcher.PATH = "data/dispatcher.dat"

function dispatcher.save()
    local snapshot = {
        queue = dispatcher.queue,
        workers = dispatcher.workers
    }
    util.save(dispatcher.PATH, snapshot)
end

function dispatcher.load()
    local data = util.load(dispatcher.PATH)
    if data then
        dispatcher.queue = data.queue or {}
        dispatcher.workers = data.workers or {}
    end
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
        for _, p in ipairs(storage.peripherals) do
            local isAssigned = false
            for _, w in pairs(dispatcher.workers) do
                if w.buffers and (w.buffers.input == p or w.buffers.output == p) then
                    isAssigned = true; break
                end
            end
            if not isAssigned then table.insert(available, p) end
        end
        
        if #available >= 2 then
            dispatcher.workers[workerId].buffers = {
                input = available[1],
                output = available[2]
            }
            util.log("Assigned buffers to worker " .. workerId .. ": IN=" .. available[1] .. " OUT=" .. available[2])
        else
            return false, "Not enough free chests for buffers"
        end
    end
    return true
end

function dispatcher.addTask(task)
    task.id = os.epoch("utc")
    task.status = "PENDING"
    table.insert(dispatcher.queue, task)
    dispatcher.save()
end

return dispatcher
