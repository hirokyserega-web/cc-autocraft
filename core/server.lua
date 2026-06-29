local net = require("lib.net")
local storage = require("core.storage")
local recipes = require("core.recipes")
local dispatcher = require("core.dispatcher")
local ui = require("ui.monitor")

_G.GRID_NAME = nil

function main_server()
    print("CC-AUTOCRAFT 2.0 - ONLINE")
    for _, side in ipairs(redstone.getSides()) do
        if peripheral.getType(side) == "modem" then rednet.open(side) end
    end
    recipes.load()
    dispatcher.load()
    
    local mon = peripheral.find("monitor")
    local monName = mon and peripheral.getName(mon)

    while true do
        storage.refresh()
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local id, msg = p1, p2
            if type(msg) == "table" and msg.protocol == net.PROTOCOL then
                if msg.type == "DISCOVER" then
                    net.send(id, "DISCOVER_ACK", {id = os.getComputerID()})
                    dispatcher.autoAssignBuffers(id)
                elseif msg.type == "RESULT" then
                    for _, t in ipairs(dispatcher.queue) do
                        if t.id == msg.data.task_id then t.status = msg.data.success and "COMPLETED" or "FAILED" break end
                    end
                    dispatcher.save()
                elseif msg.type == "HEARTBEAT" then
                    if not dispatcher.workers[id] then dispatcher.workers[id] = {} end
                    dispatcher.workers[id].status = msg.data.status
                end
            end
        elseif event == "monitor_touch" then
            local act = ui.touch(p2, p3)
            if act == "DASH" or act == "RECIPE" or act == "CONF" then
                ui.tab = act
            elseif act == "SCAN" then
                local res, err = recipes.get_from_grid(_G.GRID_NAME)
                if res then ui.modal = { title = res.output.name, data = res }
                else print("Scan Error: " .. (err or "No chest selected")) end
            elseif act == "OK" and ui.modal then
                recipes.add(ui.modal.data.output.name, ui.modal.data.ingredients, ui.modal.data.output.count)
                ui.modal = nil
            elseif act == "CANCEL" then
                ui.modal = nil
            elseif act and act:find("SET_GRID:") then
                _G.GRID_NAME = act:gsub("SET_GRID:", "")
                print("Scanner set to: " .. _G.GRID_NAME)
            end
        end

        if monName then ui.draw(monName) end
    end
end

return { main = main_server }
