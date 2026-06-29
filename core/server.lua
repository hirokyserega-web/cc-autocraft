local net = require("lib.net")
local util = require("lib.util")
local storage = require("core.storage")
local recipes = require("core.recipes")
local dispatcher = require("core.dispatcher")
local ui = require("ui.monitor")

_G.GRID_NAME = nil

function main_loop()
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
                end
            end
        elseif event == "monitor_touch" then
            local act = ui.handleTouch(p2, p3)
            if act == "TAB:DASH" then ui.current_tab = "DASH"
            elseif act == "TAB:RECIPE" then ui.current_tab = "RECIPE"
            elseif act == "TAB:CONF" then ui.current_tab = "CONF"
            elseif act == "SCAN" then
                local res, err = recipes.get_from_grid(_G.GRID_NAME)
                if res then ui.modal = { title = "Save?", data = res }
                else print("Error: " .. (err or "No grid")) end
            elseif act == "MODAL_OK" and ui.modal then
                recipes.add(ui.modal.data.output.name, ui.modal.data.ingredients, ui.modal.data.output.count)
                ui.modal = nil
            elseif act == "MODAL_CANCEL" then ui.modal = nil
            elseif act and act:find("SET_GRID:") then
                _G.GRID_NAME = act:gsub("SET_GRID:", "")
            end
        end

        if monName then ui.draw(monName) end
    end
end

return { main = main_loop }
