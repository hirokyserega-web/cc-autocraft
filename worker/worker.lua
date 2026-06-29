-- Turtle Worker (FSM)
local net = require("lib.net")
local util = require("lib.util")

local worker = {
    id = os.getComputerID(),
    status = "IDLE",
    current_task = nil,
    core_id = nil
}

local GRID = {1, 2, 3, 5, 6, 7, 9, 10, 11}

function worker.craft_logic(recipe, batches)
    -- Очистка слотов
    for i = 1, 16 do
        turtle.select(i)
        if turtle.getItemCount() > 0 then
            turtle.drop() -- Выкидываем все (предполагается в сундук спереди)
        end
    end

    -- Загрузка ингредиентов
    -- Мы предполагаем, что ингредиенты в сундуке спереди разложены по слотам,
    -- соответствующим сетке 3х3 или просто подаются пачками.
    -- Правильнее: Core кладет ингредиенты в конкретные слоты буфера.
    
    -- Для базовой версии: Core кладет все в сундук, черепаха забирает и раскладывает.
    -- НО: CC:T позволяет забирать из конкретных слотов сундука.
    
    -- Алгоритм крафта:
    for batch = 1, batches do
        -- Перемещаем из слотов черепахи в сетку согласно рецепту
        -- (Это сложная часть без внешних инструментов)
        -- Допустим, Core уже подготовил 9 слотов во входном сундуке.
        
        for slot = 1, 16 do
            turtle.select(slot)
            turtle.suck() -- Берем из сундука
        end
        
        if turtle.craft() then
            turtle.dropUp() -- Скидываем результат вверх (выходной буфер)
        else
            return false
        end
    end
    return true
end

function worker.loop()
    util.log("Worker started. ID: " .. worker.id)
    rednet.open("right") -- По умолчанию справа модем
    net.broadcast("DISCOVER", {id = worker.id})
    
    while true do
        local id, type, data = net.receive(2)
        
        if type == "DISCOVER_ACK" then
            worker.core_id = id
            util.log("Connected to Core: " .. id)
        
        elseif type == "CRAFT_REQUEST" and worker.status == "IDLE" then
            worker.current_task = data
            worker.status = "LOADING"
            net.send(id, "CRAFT_ACK", {task_id = data.id})
            
            local success = worker.craft_logic(data.recipe, data.batches)
            
            worker.status = "UNLOADING"
            net.send(worker.core_id, "RESULT", {
                task_id = data.id,
                success = success
            })
            
            worker.status = "IDLE"
            worker.current_task = nil
        end
        
        -- Heartbeat
        if worker.core_id then
            net.send(worker.core_id, "HEARTBEAT", {
                status = worker.status,
                task_id = worker.current_task and worker.current_task.id
            })
        end
    end
end

-- Entry point
if ... == "run" then
    worker.loop()
end

return worker
