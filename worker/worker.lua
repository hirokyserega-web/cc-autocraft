local net = require("lib.net")
local worker = { id = os.getComputerID(), status = "IDLE", core_id = nil }

function worker.loop()
    print("Worker booting...")
    for _, side in ipairs(redstone.getSides()) do
        if peripheral.getType(side) == "modem" then rednet.open(side) end
    end

    while true do
        if not worker.core_id then
            print("Seeking Core...")
            net.broadcast("DISCOVER", {id = worker.id})
        end
        
        local id, type, data = net.receive(3)
        if id and type == "DISCOVER_ACK" then
            worker.core_id = id
            print("Connected to Core: " .. id)
        elseif type == "CRAFT_REQUEST" then
            print("Crafting: " .. data.name)
            os.sleep(2) -- Simulation
            net.send(worker.core_id, "RESULT", {task_id = data.id, success = true})
            print("Done.")
        end
        
        if worker.core_id then
            net.send(worker.core_id, "HEARTBEAT", {status = worker.status})
        end
        os.sleep(0.5)
    end
end

return worker
