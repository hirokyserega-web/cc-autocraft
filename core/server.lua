local net = require("lib.net")
local storage = require("core.storage")
local recipes = require("core.recipes")
local dispatcher = require("core.dispatcher")
local ui = require("ui.monitor")
local planner = require("core.planner")

_G.GRID_NAME = nil
_G.active_test = nil

local function select_default_scanner()
    if _G.GRID_NAME then return end
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
            _G.GRID_NAME = name
            break
        end
    end
end

local function handle_test_result(workerId, success, err)
    if not _G.active_test or _G.active_test.worker_id ~= workerId then return end
    
    local worker = dispatcher.workers[workerId]
    if not worker or not worker.buffers then return end
    
    local out_p = peripheral.wrap(worker.buffers.output)
    local scanner = peripheral.wrap(_G.GRID_NAME)
    
    if not out_p or not scanner then
        ui.modal = {
            type = "RECIPE_FAILED",
            error = "Missing output chest or scanner chest!"
        }
        worker.status = "IDLE"
        _G.active_test = nil
        return
    end
    
    if success then
        -- Find the crafted item in output chest
        local items = out_p.list()
        local out_item = nil
        local out_slot = nil
        
        for slot, item in pairs(items) do
            if not out_item then
                out_item = item
                out_slot = slot
            else
                -- Prefer item that is not in ingredients
                local is_ing = false
                for _, ing in ipairs(_G.active_test.ingredients) do
                    if ing.name == item.name then
                        is_ing = true
                        break
                    end
                end
                if not is_ing then
                    out_item = item
                    out_slot = slot
                end
            end
        end
        
        if out_item then
            -- Push the crafted output to slot 16 of the scanner chest
            out_p.pushItems(_G.GRID_NAME, out_slot, out_item.count, 16)
            
            -- Push leftovers back to their original slots
            for slot, item in pairs(out_p.list()) do
                for _, ing in ipairs(_G.active_test.ingredients) do
                    if ing.name == item.name then
                        out_p.pushItems(_G.GRID_NAME, slot, item.count, ing.slot)
                        break
                    end
                end
            end
            
            ui.modal = {
                type = "RECIPE_SUCCESS",
                data = {
                    output = { name = out_item.name, count = out_item.count },
                    ingredients = _G.active_test.ingredients
                }
            }
        else
            ui.modal = {
                type = "RECIPE_FAILED",
                error = "Output chest is empty! Craft failed."
            }
        end
    else
        -- Move all items back to their original slots
        for slot, item in pairs(out_p.list()) do
            for _, ing in ipairs(_G.active_test.ingredients) do
                if ing.name == item.name then
                    out_p.pushItems(_G.GRID_NAME, slot, item.count, ing.slot)
                    break
                end
            end
        end
        
        ui.modal = {
            type = "RECIPE_FAILED",
            error = err or "Unknown error"
        }
    end
    
    -- Now, restore ALL ingredients to their original slots from storage!
    -- This ensures that whether success or failure, the chest's crafting grid remains 100% intact!
    local current_list = scanner.list() or {}
    for _, ing in ipairs(_G.active_test.ingredients) do
        local cur = current_list[ing.slot]
        local cur_count = cur and cur.count or 0
        local needed = (ing.count or 1) - cur_count
        if needed > 0 then
            storage.extract(ing.name, needed, _G.GRID_NAME, ing.slot)
        end
    end
    
    worker.status = "IDLE"
    _G.active_test = nil
end

local function trigger_test_craft()
    if not _G.GRID_NAME then
        ui.modal = { type = "RECIPE_FAILED", error = "Выберите сундук в настройках!" }
        return
    end
    
    local res, err = recipes.get_from_grid(_G.GRID_NAME)
    if not res then
        ui.modal = { type = "RECIPE_FAILED", error = err or "Ошибка сетки крафта!" }
        return
    end
    
    -- Find idle worker
    local worker_id = nil
    for wid, w in pairs(dispatcher.workers) do
        if w.status == "IDLE" and w.buffers then
            worker_id = wid
            break
        end
    end
    
    if not worker_id then
        ui.modal = { type = "RECIPE_FAILED", error = "Нет свободных черепах-воркеров!" }
        return
    end
    
    local worker = dispatcher.workers[worker_id]
    
    -- Clear worker's input and output chests
    local in_p = peripheral.wrap(worker.buffers.input)
    if in_p then
        for slot = 1, in_p.size() or 27 do
            local item = in_p.getItemDetail(slot)
            if item then storage.deposit(worker.buffers.input, slot, item.count) end
        end
    end
    
    local out_p = peripheral.wrap(worker.buffers.output)
    if out_p then
        for slot = 1, out_p.size() or 27 do
            local item = out_p.getItemDetail(slot)
            if item then storage.deposit(worker.buffers.output, slot, item.count) end
        end
    end
    
    -- Move items from scanner grid to worker input buffer
    local scanner = peripheral.wrap(_G.GRID_NAME)
    if not scanner then
        ui.modal = { type = "RECIPE_FAILED", error = "Сундук-сканер не найден!" }
        return
    end
    
    for _, ing in ipairs(res.ingredients) do
        scanner.pushItems(worker.buffers.input, ing.slot, 1, ing.slot)
    end
    
    -- Record active test
    _G.active_test = {
        worker_id = worker_id,
        ingredients = res.ingredients,
        scanner_chest = _G.GRID_NAME,
        status = "RUNNING"
    }
    
    worker.status = "TESTING"
    
    -- Send message
    net.send(worker_id, "TEST_CRAFT", {
        id = "test_" .. os.epoch("utc"),
        ingredients = res.ingredients,
        batches = 1
    })
    
    print("Started test craft on worker #" .. worker_id)
end

function main()
    print("CC-AUTOCRAFT 2.0 - CORE ONLINE")
    
    -- Open all modems
    for _, side in ipairs(redstone.getSides()) do
        if peripheral.getType(side) == "modem" then rednet.open(side) end
    end
    
    recipes.load()
    dispatcher.load()
    select_default_scanner()
    
    local mon = peripheral.find("monitor")
    local monName = mon and peripheral.getName(mon)
    if not monName then
        print("Warning: Monitor not found!")
    end

    -- Fast 0.5s timer for smooth grid alignment and queue processing
    local tick_timer = os.startTimer(0.5)

    while true do
        storage.refresh()
        
        -- Auto-arrange chest grid if configured
        if _G.GRID_NAME then
            recipes.arrange_grid(_G.GRID_NAME)
        end
        
        local event, p1, p2, p3, p4 = os.pullEvent()
        
        if event == "timer" and p1 == tick_timer then
            dispatcher.processQueue()
            tick_timer = os.startTimer(0.5)
            
        elseif event == "rednet_message" then
            local id, msg = p1, p2
            if type(msg) == "table" and msg.protocol == net.PROTOCOL then
                if msg.type == "DISCOVER" then
                    net.send(id, "DISCOVER_ACK", {id = os.getComputerID()})
                    dispatcher.autoAssignBuffers(id)
                elseif msg.type == "RESULT" then
                    -- Check if it is a test craft task
                    if type(msg.data.task_id) == "string" and msg.data.task_id:sub(1, 5) == "test_" then
                        handle_test_result(id, msg.data.success, msg.data.error)
                    else
                        dispatcher.handleResult(id, msg.data.task_id, msg.data.success, msg.data.error)
                    end
                elseif msg.type == "HEARTBEAT" then
                    if not dispatcher.workers[id] then 
                        dispatcher.workers[id] = { status = "IDLE" } 
                    end
                    dispatcher.workers[id].status = msg.data.status
                    dispatcher.autoAssignBuffers(id)
                end
            end
            
        elseif event == "monitor_touch" then
            local name, x, y = p1, p2, p3
            local btn_id = ui.touch(x, y)
            
            if btn_id then
                print("Clicked button: " .. btn_id)
                
                -- Tab Switches
                if btn_id == "DASH" or btn_id == "STORAGE" or btn_id == "RECIPE" or btn_id == "CONF" then
                    ui.tab = btn_id
                    ui.scroll = 0
                    ui.recipe_scroll = 0
                    
                -- Scrolling lists (both Storage and Scanner selection)
                elseif btn_id == "SCROLL_UP" then
                    ui.scroll = math.max(0, ui.scroll - 3)
                elseif btn_id == "SCROLL_DOWN" then
                    if ui.tab == "STORAGE" then
                        local total_items = 0
                        for _ in pairs(storage.cache) do total_items = total_items + 1 end
                        ui.scroll = math.min(total_items - 1, ui.scroll + 3)
                    elseif ui.tab == "CONF" then
                        local inventories = {}
                        local names = peripheral.getNames()
                        for _, n in ipairs(names) do
                            if peripheral.getType(n) == "inventory" or peripheral.hasType(n, "inventory") then
                                if not storage.buffers[n] then
                                    table.insert(inventories, n)
                                end
                            end
                        end
                        ui.scroll = math.min(#inventories - 1, ui.scroll + 2)
                    end
                    if ui.scroll < 0 then ui.scroll = 0 end
                    
                -- Recipes list scrolling
                elseif btn_id == "RECIPE_SCROLL_UP" then
                    ui.recipe_scroll = math.max(0, ui.recipe_scroll - 3)
                elseif btn_id == "RECIPE_SCROLL_DOWN" then
                    local total_recipes = 0
                    for _ in pairs(recipes.data) do total_recipes = total_recipes + 1 end
                    ui.recipe_scroll = math.min(total_recipes - 1, ui.recipe_scroll + 3)
                    if ui.recipe_scroll < 0 then ui.recipe_scroll = 0 end
                    
                -- Delete Recipe
                elseif btn_id:sub(1, 14) == "DELETE_RECIPE:" then
                    local recName = btn_id:sub(15)
                    recipes.data[recName] = nil
                    recipes.save()
                    print("Deleted recipe for: " .. recName)
                    
                -- Clear Queue
                elseif btn_id == "CLEAR_QUEUE" then
                    dispatcher.queue = {}
                    for name, qty in pairs(storage.reserved) do
                        storage.reserved[name] = 0
                    end
                    dispatcher.save()
                    print("Crafting queue cleared!")
                    
                -- Conf: set active scanner
                elseif btn_id:sub(1, 9) == "SET_GRID:" then
                    local grid = btn_id:sub(10)
                    _G.GRID_NAME = grid
                    print("Scanner chest set to: " .. grid)
                    
                -- Craft popup adjustments
                elseif btn_id:sub(1, 4) == "DEC:" then
                    local amt = tonumber(btn_id:sub(5)) or 1
                    ui.modal.count = math.max(1, ui.modal.count - amt)
                elseif btn_id:sub(1, 4) == "INC:" then
                    local amt = tonumber(btn_id:sub(5)) or 1
                    ui.modal.count = ui.modal.count + amt
                    
                elseif btn_id == "CRAFT_CANCEL" then
                    ui.modal = nil
                    
                elseif btn_id == "REC_ERR_CLOSE" then
                    ui.modal = nil
                    
                -- Craft popup open
                elseif btn_id:sub(1, 11) == "CRAFT_INIT:" then
                    local itemName = btn_id:sub(12)
                    ui.modal = {
                        type = "CRAFT",
                        name = itemName,
                        count = 1,
                        error = nil
                    }
                    
                -- Start craft task
                elseif btn_id == "CRAFT_START_OK" then
                    print("Planning craft for " .. ui.modal.name .. " x" .. ui.modal.count)
                    local tasks, err = planner.plan(ui.modal.name, ui.modal.count)
                    if tasks then
                        for _, task in ipairs(tasks) do
                            dispatcher.addTask(task)
                        end
                        print("Planning success! Added " .. #tasks .. " tasks.")
                        ui.modal = nil
                        ui.tab = "DASH" -- switch to see active queue!
                    else
                        print("Planning failed: " .. tostring(err))
                        ui.modal.error = "Ошибка: " .. tostring(err)
                    end
                    
                -- Test craft initialization
                elseif btn_id == "TEST_CRAFT_INIT" then
                    trigger_test_craft()
                    
                -- Save Recipe Confirmation
                elseif btn_id == "SAVE_RECIPE_OK" then
                    if ui.modal and ui.modal.type == "RECIPE_SUCCESS" then
                        recipes.add(ui.modal.data.output.name, ui.modal.data.ingredients, ui.modal.data.output.count)
                        print("Recipe saved successfully: " .. ui.modal.data.output.name)
                        ui.modal = nil
                    end
                elseif btn_id == "SAVE_RECIPE_CANCEL" then
                    ui.modal = nil
                end
            end
        end
        
        -- Redraw the monitor after handling any event
        if monName then
            ui.draw(monName)
        end
    end
end

-- Export public functions
local server = {
    main = main
}
return server
