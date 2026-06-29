-- Core Server Main Loop
local net = require("lib.net")
local util = require("lib.util")
local storage = require("core.storage")
local recipes = require("core.recipes")
local dispatcher = require("core.dispatcher")
local planner = require("core.planner")

local server = {}

function server.handle_packet(id, type, data)
    if type == "DISCOVER" then
        net.send(id, "DISCOVER_ACK", {id = os.getComputerID()})
        dispatcher.autoAssignBuffers(id)
        
    elseif type == "RESULT" then
        for i, task in ipairs(dispatcher.queue) do
            if task.id == data.task_id then
                if data.success then
                    task.status = "COMPLETED"
                    util.log("Task completed: " .. task.name)
                else
                    task.status = "FAILED"
                    util.log("Task failed: " .. task.name, "ERROR")
                end
                break
            end
        end
        dispatcher.save()
        
    elseif type == "HEARTBEAT" then
        if dispatcher.workers[id] then
            dispatcher.workers[id].status = data.status
            dispatcher.workers[id].last_seen = os.epoch("utc")
        end
    end
end

function server.main()
    util.log("Core Server starting...")
    rednet.open("top") -- По умолчанию сверху модем
    recipes.load()
    dispatcher.load()
    storage.refresh()
    
    while true do
        -- 1. Слушаем сеть
        local id, type, data = net.receive(0.5)
        if id then server.handle_packet(id, type, data) end
        
        -- 2. Планируем и раздаем задачи
        for i, task in ipairs(dispatcher.queue) do
            if task.status == "PENDING" then
                -- Ищем свободного воркера
                for wId, wInfo in pairs(dispatcher.workers) do
                    if wInfo.status == "IDLE" and wInfo.buffers then
                        -- Подготовка ресурсов в буфер
                        local bufIn = wInfo.buffers.input
                        for _, ing in ipairs(task.recipe.ingredients) do
                            storage.extract(ing.name, ing.count * (task.batches or 1), bufIn)
                        end
                        
                        -- Отправка задачи
                        net.send(wId, "CRAFT_REQUEST", task)
                        task.status = "CRAFTING"
                        wInfo.status = "CRAFTING"
                        wInfo.task_id = task.id
                        break
                    end
                end
            end
        end
        
        -- 3. Сбор готовых предметов из выходных буферов
        for wId, wInfo in pairs(dispatcher.workers) do
            if wInfo.buffers then
                local bufOut = wInfo.buffers.output
                local p = peripheral.wrap(bufOut)
                local items = p.list()
                for slot, item in pairs(items) do
                    storage.deposit(bufOut, slot, item.count)
                end
            end
        end
        
        os.sleep(1)
    end
end

if ... == "run" then
    server.main()
end

return server
