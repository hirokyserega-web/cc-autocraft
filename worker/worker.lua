-- Turtle Worker (FSM)
local net = require("lib.net")
local util = require("lib.util")

local worker = {
    id = os.getComputerID(),
    status = "IDLE",
    current_task = nil,
    core_id = nil
}

local GRID = {1,2,3,5,6,7,9,10,11}

function worker.loop()
    net.broadcast("DISCOVER", {id = worker.id})
    
    while true do
        local id, type, data = net.receive(2)
        
        if type == "HELLO" then
            worker.core_id = id
            util.log("Connected to Core: " .. id)
        
        elseif type == "CRAFT_REQUEST" and worker.status == "IDLE" then
            worker.current_task = data
            net.send(id, "CRAFT_ACK", {task_id = data.id})
            worker.status = "LOADING"
            worker.process()
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

function worker.process()
    util.log("Starting task: " .. worker.current_task.name)
    -- 1. Loading from input buffer
    -- (Черепаха предполагает, что Core уже положил ингредиенты в буфер)
    -- 2. Crafting
    -- 3. Unloading to output buffer
    
    -- Упрощенная логика для прототипа
    worker.status = "CRAFTING"
    -- ... turtle.craft() logic here ...
    
    worker.status = "UNLOADING"
    -- ... turtle.drop() logic here ...
    
    net.send(worker.core_id, "RESULT", {
        task_id = worker.current_task.id,
        success = true
    })
    
    worker.status = "IDLE"
    worker.current_task = nil
end

return worker
