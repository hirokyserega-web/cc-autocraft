local net = require("lib.net")
local util = require("lib.util")
local storage = require("core.storage")
local recipes = require("core.recipes")
local dispatcher = require("core.dispatcher")
local ui = require("ui.monitor")

_G.GRID_NAME = nil

local function handle_packet(id, type, data)
    if type == "DISCOVER" then
        net.send(id, "DISCOVER_ACK", {id = os.getComputerID()})
        dispatcher.autoAssignBuffers(id)
    elseif type == "RESULT" then
        for _, t in ipairs(dispatcher.queue) do
            if t.id == data.task_id then 
                t.status = data.success and "COMPLETED" or "FAILED" 
                break 
            end
        end
        dispatcher.save()
    elseif type == "HEARTBEAT" then
        if not dispatcher.workers[id] then dispatcher.workers[id] = {} end
        dispatcher.workers[id].status = data.status
        dispatcher.workers[id].last_seen = os.epoch("utc")
    end
end

local function main_loop()
    print("Core Server Running (Interactive Mode)")
    for _, side in ipairs(redstone.getSides()) do
        if peripheral.getType(side) == "modem" then rednet.open(side) end
    end

    recipes.load()
    dispatcher.load()
    
    local monitor = peripheral.find("monitor")
    local monName = monitor and peripheral.getName(monitor)

    while true do
        storage.refresh()
        
        -- Non-blocking event loop
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local id, msg = p1, p2
            if type(msg) == "table" and msg.protocol == net.PROTOCOL then
                handle_packet(id, msg.type, msg.data)
            end
        elseif event == "monitor_touch" then
            local act = ui.handleTouch(p2, p3)
            if act == "DASH" then ui.current_tab = "DASHBOARD"
            elseif act == "RECIPE" then ui.current_tab = "RECIPES"
            elseif act == "SET" then ui.current_tab = "SETTINGS"
            elseif act == "SCAN" then
                local res, err = recipes.get_from_grid(_G.GRID_NAME)
                if res then
                    ui.modal = { title = "Save " .. res.output.name .. "?", data = res }
                else
                    util.log("Grid Error: " .. (err or "no grid"), "ERROR")
                end
            elseif act == "CONFIRM" and ui.modal then
                local d = ui.modal.data
                recipes.add(d.output.name, d.ingredients, d.output.count)
                ui.modal = nil
                util.log("Recipe saved: " .. d.output.name)
            elseif act == "CANCEL" then
                ui.modal = nil
            elseif act and act:find("SET_GRID:") then
                _G.GRID_NAME = act:gsub("SET_GRID:", "")
                print("Recipe grid set to: " .. _G.GRID_NAME)
            end
        end

        -- Background task: Dispatcher
        for _, task in ipairs(dispatcher.queue) do
            if task.status == "PENDING" then
                for wId, wInfo in pairs(dispatcher.workers) do
                    if wInfo.status == "IDLE" and wInfo.buffers then
                        net.send(wId, "CRAFT_REQUEST", task)
                        task.status = "CRAFTING"
                        wInfo.status = "CRAFTING"
                        break
                    end
                end
            end
        end

        if monName then ui.draw(monName) end
    end
end

return { main = main_loop }
