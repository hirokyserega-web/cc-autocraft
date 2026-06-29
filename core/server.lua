local net = require("lib.net")
local util = require("lib.util")
local storage = require("core.storage")
local recipes = require("core.recipes")
local dispatcher = require("core.dispatcher")
local ui = require("ui.monitor")

local server = {}

function server.main()
    print("Core Server Initializing...")
    
    -- Open all modems
    local modemFound = false
    for _, side in ipairs(redstone.getSides()) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            modemFound = true
            print("Rednet Active on " .. side)
        end
    end
    if not modemFound then print("WARNING: No Wireless Modem!") end

    recipes.load()
    dispatcher.load()
    
    local mon = peripheral.find("monitor")
    local monName = mon and peripheral.getName(mon)
    if monName then print("UI Monitor Active: " .. monName) end

    print("Server running. Logs below:")

    while true do
        storage.refresh()
        local id, type, data = net.receive(0.5)
        
        if id then
            print(string.format("[%s] %s from ID %d", os.date("%H:%M:%S"), type, id))
            if type == "DISCOVER" then
                net.send(id, "DISCOVER_ACK", {id = os.getComputerID()})
                dispatcher.autoAssignBuffers(id)
            elseif type == "RESULT" then
                print("Task " .. (data.task_id or "??") .. " finished: " .. (data.success and "OK" or "FAIL"))
            end
        end
        
        -- Simple dispatch logic
        for _, task in ipairs(dispatcher.queue) do
            if task.status == "PENDING" then
                for wId, wInfo in pairs(dispatcher.workers) do
                    if wInfo.status == "IDLE" and wInfo.buffers then
                        print("-> Task " .. task.name .. " to Worker " .. wId)
                        net.send(wId, "CRAFT_REQUEST", task)
                        task.status = "CRAFTING"
                        wInfo.status = "CRAFTING"
                        break
                    end
                end
            end
        end

        if monName then ui.draw(monName) end
        os.sleep(0.1)
    end
end

return server
