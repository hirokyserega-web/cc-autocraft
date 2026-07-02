-- Core server: main event loop, networking, scanner selection, test-craft flow.
local net = require("lib.net")
local storage = require("core.storage")
local recipes = require("core.recipes")
local dispatcher = require("core.dispatcher")
local ui = require("ui.monitor")
local planner = require("core.planner")
local util = require("lib.util")

_G.GRID_NAME = nil       -- name of the scanner chest
_G.active_test = nil     -- current test craft state
local SCANNER_PATH = "data/scanner.dat"

local function loadConfig()
    recipes.load()
    local data = util.load(SCANNER_PATH)
    if data and data.grid_name then _G.GRID_NAME = data.grid_name end
end

local function saveConfig()
    util.save(SCANNER_PATH, { grid_name = _G.GRID_NAME })
end

local function handleButton(bid)
    if bid:sub(1,4) == "TAB:" then
        ui.tab = bid:sub(5)
        ui.scroll = 0
    elseif bid == "SUP" then
        ui.scroll = math.max(0, ui.scroll - 5)
    elseif bid == "SDN" then
        ui.scroll = ui.scroll + 5
    elseif bid == "RSUP" then
        ui.recipe_scroll = math.max(0, ui.recipe_scroll - 5)
    elseif bid == "RSDN" then
        ui.recipe_scroll = ui.recipe_scroll + 5
    elseif bid == "CSUP" then
        ui.conf_scroll = math.max(0, ui.conf_scroll - 5)
    elseif bid == "CSDN" then
        ui.conf_scroll = ui.conf_scroll + 5
    elseif bid:sub(1,11) == "CRAFT_INIT:" then
        local name = bid:sub(12)
        ui.modal = { type = "CRAFT", name = name, count = 1 }
    elseif bid:sub(1,10) == "REC_CRAFT:" then
        local name = bid:sub(11)
        ui.modal = { type = "CRAFT", name = name, count = 1 }
    elseif bid:sub(1,8) == "REC_DEL:" then
        recipes.remove(bid:sub(9))
    elseif bid == "DEC:1" then
        if ui.modal then ui.modal.count = math.max(1, ui.modal.count - 1) end
    elseif bid == "INC:1" then
        if ui.modal then ui.modal.count = ui.modal.count + 1 end
    elseif bid == "INC:64" then
        if ui.modal then ui.modal.count = ui.modal.count + 64 end
    elseif bid == "CRAFT_OK" then
        if ui.modal then
            dispatcher.add_task(ui.modal.name, ui.modal.count)
            ui.modal = nil
        end
    elseif bid == "CRAFT_CANCEL" or bid == "SAVE_CANCEL" or bid == "ERR_CLOSE" or bid == "MODAL_CANCEL" then
        ui.modal = nil
    elseif bid == "SAVE_OK" then
        if ui.modal and ui.modal.data then
            recipes.add(ui.modal.data.output.name, ui.modal.data.ingredients, ui.modal.data.output.count)
            ui.modal = nil
        end
    elseif bid == "CLR_QUEUE" then
        dispatcher.queue = {}
    elseif bid == "TEST_CRAFT" then
        local res, err = recipes.get_from_grid(_G.GRID_NAME)
        if not res then
            ui.modal = { type = "RECIPE_FAILED", error = err }
        else
            _G.active_test = { status = "WAITING", data = res }
            print("[SERVER] Starting test craft for " .. (res.output and res.output.name or "unknown"))
            local ok, terr = planner.plan_test_craft(res)
            if not ok then
                ui.modal = { type = "RECIPE_FAILED", error = terr }
                _G.active_test = nil
            end
        end
    elseif bid:sub(1,9) == "SET_GRID:" then
        _G.GRID_NAME = bid:sub(10)
        saveConfig()
    elseif bid:sub(1,12) == "SET_STORAGE:" then
        local name = bid:sub(13)
        ui.modal = { type = "SELECT_WORKER", chest = name, mode = "IN" }
    elseif bid:sub(1,15) == "SET_WORKER_BUF:" then
        local parts = {}
        for p in bid:sub(16):gmatch("([^|]+)") do table.insert(parts, p) end
        local mode, chest, w_id = parts[1], parts[2], parts[3]
        net.send(tonumber(w_id), "SET_BUFFER", { mode = mode, chest = chest })
        if mode == "IN" then
            ui.modal = { type = "SELECT_WORKER", chest = chest, mode = "OUT" }
        else
            ui.modal = nil
        end
    end
end

local function main()
    loadConfig()
    net.open()
    
    local mon = peripheral.find("monitor")
    local monName = peripheral.getName(mon)
    
    if mon then
        mon.setTextScale(0.5)
        ui.draw(monName)
    end

    local timer = os.startTimer(0.5)
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            storage.refresh()
            recipes.arrange_grid(_G.GRID_NAME)
            dispatcher.tick()
            
            if _G.active_test and _G.active_test.status == "DONE" then
                ui.modal = { type = "RECIPE_SUCCESS", data = _G.active_test.data }
                _G.active_test = nil
            end
            
            if monName then ui.draw(monName) end
            timer = os.startTimer(0.5)
            
        elseif event == "rednet_message" then
            local sender, msg, protocol = p1, p2, p3
            if protocol == "autocraft" then
                if msg.type == "WORKER_ANN" then
                    dispatcher.workers[sender] = { status = msg.status or "IDLE", last_seen = os.clock() }
                elseif msg.type == "WORKER_STATUS" then
                    if dispatcher.workers[sender] then
                        dispatcher.workers[sender].status = msg.status
                    end
                elseif msg.type == "TEST_CRAFT_DONE" then
                    if _G.active_test then
                        _G.active_test.status = "DONE"
                        _G.active_test.data.output = msg.output
                    end
                end
            end
            
        elseif event == "monitor_touch" then
            local _, x, y = p1, p2, p3
            local bid = ui.touch(x, y)
            if bid then
                ui.pressed = bid
                ui.draw(monName)
                os.sleep(0.05)
                ui.pressed = nil
                handleButton(bid)
                if monName then ui.draw(monName) end
            end
        end
        os.sleep(0)
    end
end

return { main = main }
