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

local function isLocalSide(name)
    if not name then return false end
    local sides = { down = true, up = true, front = true, back = true, left = true, right = true }
    return sides[name] == true
end

local function scannerSignature(name)
    if not name then return nil end
    local p = peripheral.wrap(name)
    if not p or type(p.list) ~= "function" then return nil end
    -- Prefer inventory content as the identity. When the chest is empty,
    -- use the peripheral type label so two empty chests don't hash to the same value.
    local list = p.list() or {}
    local total = 0
    local first
    for _, item in pairs(list) do
        total = total + item.count
        if not first then first = item.name end
    end
    if total == 0 then
        return "empty:" .. (peripheral.getType(name) or "?") .. ":" .. (p.size() or 27)
    end
    return string.format("s%d:%s", total, first or "?")
end

local function loadScanner()
    local saved = util.load(SCANNER_PATH)
    if type(saved) ~= "table" then
        -- Backward compat: older installs stored a bare string.
        if type(saved) == "string" and saved ~= "" and peripheral.wrap(saved) then
            _G.GRID_NAME = saved
        end
        return
    end
    local name, sig = saved.name, saved.signature
    if name and peripheral.wrap(name) and scannerSignature(name) == sig then
        _G.GRID_NAME = name; return
    end
    if sig then
        local candidates = util.getInventories()
        for _, n in ipairs(candidates) do
            if scannerSignature(n) == sig then
                _G.GRID_NAME = n
                util.log("Scanner rebound to " .. n .. " (name changed but signature matched).")
                return
            end
            os.sleep(0) -- Yield to prevent watchdog crash during scanner fingerprint matching
        end
    end
    -- Fallback: exact name still exists but signature differs (chest content
    -- changed - probably an entirely different chest now); keep the user choice.
    if name and peripheral.wrap(name) then
        _G.GRID_NAME = name
    end
end

local function saveScanner()
    local sig = _G.GRID_NAME and scannerSignature(_G.GRID_NAME)
    util.save(SCANNER_PATH, { name = _G.GRID_NAME, signature = sig })
end

local function refreshScannerCache()
    if _G.GRID_NAME then
        local p = peripheral.wrap(_G.GRID_NAME)
        if p then
            _G.GRID_ITEMS = p.list() or {}
            local od = p.getItemDetail(recipes.OUTPUT_SLOT)
            _G.GRID_OUTPUT = od and od.name or nil
        else
            _G.GRID_ITEMS = {}
            _G.GRID_OUTPUT = nil
        end
    else
        _G.GRID_ITEMS = {}
        _G.GRID_OUTPUT = nil
    end
end

----------------------------------------------------------------
-- TEST CRAFT: lay out a recipe in the scanner grid, craft it once
-- on a worker, return the result + leftovers, offer to save.
----------------------------------------------------------------

-- Called when a worker finishes a TEST_CRAFT request.
local function handle_test_result(workerId, success, err)
    if not _G.active_test or _G.active_test.worker_id ~= workerId then return end

    local test = _G.active_test
    local worker = dispatcher.workers[workerId]
    if not worker or not worker.buffers then
        ui.modal = { type = "RECIPE_FAILED", error = "Worker has no buffers." }
        _G.active_test = nil
        return
    end

    storage.refresh()
    local out_p = peripheral.wrap(worker.buffers.output)
    local scanner = _G.GRID_NAME and peripheral.wrap(_G.GRID_NAME)
    if not out_p or not scanner then
        ui.modal = { type = "RECIPE_FAILED", error = "Missing output chest or scanner." }
        worker.status = "IDLE"
        _G.active_test = nil
        return
    end

    local ingNames = {}
    for _, ing in ipairs(test.ingredients) do ingNames[ing.name] = true end

    if success then
        -- Find the crafted output (an item that is NOT one of the ingredients).
        local out_item, out_slot
        for slot, item in pairs(out_p.list()) do
            if not ingNames[item.name] then
                out_item, out_slot = item, slot
                break
            end
        end

        if out_item then
            -- Put the result into the scanner's output slot (16).
            out_p.pushItems(_G.GRID_NAME, out_slot, out_item.count, recipes.OUTPUT_SLOT)
            -- Return any leftover ingredients to their original grid slots.
            for slot, item in pairs(out_p.list()) do
                for _, ing in ipairs(test.ingredients) do
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
                    ingredients = test.ingredients
                }
            }
        else
            ui.modal = { type = "RECIPE_FAILED", error = "Output chest empty - craft failed." }
        end
    else
        -- Craft failed: return everything to its original grid slot.
        for slot, item in pairs(out_p.list()) do
            for _, ing in ipairs(test.ingredients) do
                if ing.name == item.name then
                    out_p.pushItems(_G.GRID_NAME, slot, item.count, ing.slot)
                    break
                end
            end
        end
        ui.modal = { type = "RECIPE_FAILED", error = err or "Unknown error" }
    end

    -- Refill any consumed grid cells from general storage so the layout stays
    -- visible for confirmation. (Storage has spare stock only.)
    local cur = scanner.list() or {}
    for _, ing in ipairs(test.ingredients) do
        local have = cur[ing.slot] and cur[ing.slot].count or 0
        local need = (ing.count or 1) - have
        if need > 0 then
            storage.extract(ing.name, need, _G.GRID_NAME, ing.slot)
        end
    end

    _G.GRID_ITEMS = scanner.list() or {}
    local od = scanner.getItemDetail(recipes.OUTPUT_SLOT)
    _G.GRID_OUTPUT = od and od.name or nil

    worker.status = "IDLE"
    _G.active_test = nil
end

local function trigger_test_craft()
    if not _G.GRID_NAME then
        ui.modal = { type = "RECIPE_FAILED", error = "Select a scanner chest in SETTINGS first." }
        return
    end
    if _G.active_test then
        ui.modal = { type = "RECIPE_FAILED", error = "A test is already running, please wait." }
        return
    end

    local res, err = recipes.get_from_grid(_G.GRID_NAME)
    if not res then
        ui.modal = { type = "RECIPE_FAILED", error = err or "Grid is empty." }
        return
    end
    if #res.ingredients == 0 then
        ui.modal = { type = "RECIPE_FAILED", error = "Place ingredients in the central 3x3 grid." }
        return
    end

    storage.refresh()

    local worker_id, worker = dispatcher.getReadyWorker()
    if not worker_id then
        ui.modal = { type = "RECIPE_FAILED", error = "No IDLE workers with valid buffers available." }
        return
    end

    -- Clear the scanner's output slot (16) into storage so a new result can land there.
    local scanner = peripheral.wrap(_G.GRID_NAME)
    if scanner then
        local old = scanner.getItemDetail(recipes.OUTPUT_SLOT)
        if old then
            storage.deposit(_G.GRID_NAME, recipes.OUTPUT_SLOT, old.count)
        end
    end

    -- Clear the worker's input and output buffers back into storage.
    -- (Bug 3 Fix: drop leftover items if deposit is incomplete)
    local bc = 0
    for _, bname in ipairs({ worker.buffers.input, worker.buffers.output }) do
        local p = peripheral.wrap(bname)
        if p then
            for slot = 1, (p.size() or 27) do
                local item = p.getItemDetail(slot)
                if item then
                    local deposited = storage.deposit(bname, slot, item.count)
                    if deposited < item.count then
                        p.drop(slot)
                    end
                    bc = bc + 1
                end
                util.maybeYield(bc, 16)
            end
        end
    end

    -- Move one of each laid-out ingredient from the scanner grid into the
    -- worker's input chest, preserving slot positions (so the shape is kept).
    -- (scanner is already wrapped above)
    for _, ing in ipairs(res.ingredients) do
        scanner.pushItems(worker.buffers.input, ing.slot, ing.count or 1, ing.slot)
    end

    _G.active_test = {
        worker_id = worker_id,
        ingredients = res.ingredients,
        scanner_chest = _G.GRID_NAME
    }
    worker.status = "TESTING"

    net.send(worker_id, "TEST_CRAFT", {
        id = "test_" .. os.epoch("utc"),
        ingredients = res.ingredients,
        batches = 1
    })
    util.log("Test craft started on worker #" .. worker_id)
end

----------------------------------------------------------------
-- Button handling
----------------------------------------------------------------

local function handleButton(btn_id)
    -- Tab switching
    if btn_id:sub(1, 4) == "TAB:" then
        ui.tab = btn_id:sub(5)
        ui.scroll, ui.recipe_scroll, ui.conf_scroll = 0, 0, 0
        return
    end

    -- Scrolling
    if btn_id == "SUP" then ui.scroll = math.max(0, ui.scroll - 3) return end
    if btn_id == "SDN" then ui.scroll = ui.scroll + 3 return end
    if btn_id == "RSUP" then ui.recipe_scroll = math.max(0, ui.recipe_scroll - 3) return end
    if btn_id == "RSDN" then ui.recipe_scroll = ui.recipe_scroll + 3 return end
    if btn_id == "CSUP" then ui.conf_scroll = math.max(0, ui.conf_scroll - 2) return end
    if btn_id == "CSDN" then ui.conf_scroll = ui.conf_scroll + 2 return end

    -- Open craft modal (from storage or from a saved recipe)
    if btn_id:sub(1, 11) == "CRAFT_INIT:" then
        local name = btn_id:sub(12)
        if not recipes.get(name) then
            ui.modal = { type = "RECIPE_FAILED", error = "No recipe for " .. name .. ". Record it via TEST CRAFT." }
            return
        end
        storage.refresh()
        ui.modal = { type = "CRAFT", name = name, count = 1, error = nil }
        ui.modal.feasible_ok, ui.modal.feasible_msg = planner.check(name, 1)
        return
    end
    if btn_id:sub(1, 10) == "REC_CRAFT:" then
        local name = btn_id:sub(11)
        storage.refresh()
        ui.modal = { type = "CRAFT", name = name, count = 1, error = nil }
        ui.modal.feasible_ok, ui.modal.feasible_msg = planner.check(name, 1)
        return
    end

    -- Delete a saved recipe
    if btn_id:sub(1, 8) == "REC_DEL:" then
        local name = btn_id:sub(9)
        recipes.data[name] = nil
        recipes.save()
        util.log("Deleted recipe: " .. name)
        return
    end

    -- Craft modal controls
    if btn_id:sub(1, 4) == "DEC:" then
        local amt = tonumber(btn_id:sub(5)) or 1
        ui.modal.count = math.max(1, ui.modal.count - amt)
        ui.modal.feasible_ok, ui.modal.feasible_msg = planner.check(ui.modal.name, ui.modal.count)
        return
    end
    if btn_id:sub(1, 4) == "INC:" then
        local amt = tonumber(btn_id:sub(5)) or 1
        ui.modal.count = ui.modal.count + amt
        ui.modal.feasible_ok, ui.modal.feasible_msg = planner.check(ui.modal.name, ui.modal.count)
        return
    end
    if btn_id == "CRAFT_CANCEL" then ui.modal = nil return end
    if btn_id == "ERR_CLOSE" then ui.modal = nil return end

    if btn_id == "CRAFT_OK" then
        storage.refresh()
        local tasks, err = planner.plan(ui.modal.name, ui.modal.count)
        if tasks then
            for _, t in ipairs(tasks) do dispatcher.addTask(t) end
            util.log("Planned " .. ui.modal.name .. " x" .. ui.modal.count .. " -> " .. #tasks .. " task(s)")
            ui.modal = nil
            ui.tab = "DASH"
        else
            ui.modal.error = tostring(err)
        end
        return
    end

    -- Test craft
    if btn_id == "TEST_CRAFT" then trigger_test_craft() return end

    -- Save recipe confirmation
    if btn_id == "SAVE_OK" then
        if ui.modal and ui.modal.type == "RECIPE_SUCCESS" then
            local d = ui.modal.data
            recipes.add(d.output.name, d.ingredients, d.output.count)
            util.log("Saved recipe: " .. d.output.name .. " (x" .. d.output.count .. ")")
            ui.modal = nil
        end
        return
    end
    if btn_id == "SAVE_CANCEL" or btn_id == "MODAL_CANCEL" then ui.modal = nil return end

    -- Clear queue
    if btn_id == "CLR_QUEUE" then
        dispatcher.queue = {}
        for n in pairs(storage.reserved) do storage.reserved[n] = 0 end
        dispatcher.save()
        util.log("Queue cleared.")
        return
    end

    -- Manual worker buffer setting modal triggers
    if btn_id:sub(1, 17) == "SET_BUFIN_SELECT:" then
        local chest = btn_id:sub(18)
        ui.modal = { type = "SELECT_WORKER", mode = "IN", chest = chest }
        return
    end
    if btn_id:sub(1, 18) == "SET_BUFOUT_SELECT:" then
        local chest = btn_id:sub(19)
        ui.modal = { type = "SELECT_WORKER", mode = "OUT", chest = chest }
        return
    end

    -- Process manual worker buffer mapping
    if btn_id:sub(1, 15) == "SET_WORKER_BUF:" then
        local parts = {}
        for s in string.gmatch(btn_id:sub(16), "([^|]+)") do
            table.insert(parts, s)
        end
        local mode, chest, workerId = parts[1], parts[2], tonumber(parts[3])
        if mode and chest and workerId then
            local w = dispatcher.workers[workerId] or dispatcher.workers[tostring(workerId)]
            if w then
                if not w.buffers then w.buffers = {} end
                if mode == "IN" then
                    w.buffers.input = chest
                else
                    w.buffers.output = chest
                end
                dispatcher.updateStorageBuffers()
                dispatcher.save()
                util.log("Assigned worker #" .. workerId .. " " .. mode .. " buffer to " .. chest)
            end
        end
        ui.modal = nil
        return
    end

    -- Clear chest role to Storage
    if btn_id:sub(1, 12) == "SET_STORAGE:" then
        local name = btn_id:sub(13)
        if _G.GRID_NAME == name then
            _G.GRID_NAME = nil
            saveScanner()
        end
        for wid, w in pairs(dispatcher.workers) do
            if w.buffers then
                if w.buffers.input == name then w.buffers.input = nil end
                if w.buffers.output == name then w.buffers.output = nil end
            end
        end
        dispatcher.updateStorageBuffers()
        dispatcher.save()
        util.log("Reset role of " .. name .. " to storage.")
        return
    end

    -- Select scanner chest
    if btn_id:sub(1, 9) == "SET_GRID:" then
        local name = btn_id:sub(10)
        _G.GRID_NAME = name
        saveScanner()
        util.log("Scanner chest set to: " .. name)
        local p = peripheral.wrap(name)
        if p then
            _G.GRID_ITEMS = p.list() or {}
            local od = p.getItemDetail(recipes.OUTPUT_SLOT)
            _G.GRID_OUTPUT = od and od.name or nil
        else
            _G.GRID_ITEMS = {}
            _G.GRID_OUTPUT = nil
        end
        return
    end
end

----------------------------------------------------------------
-- Main loop
----------------------------------------------------------------

function main()
    print("CC-AUTOCRAFT 3.0 - CORE ONLINE")

    net.open()

    recipes.load()
    dispatcher.load()
    loadScanner()

    local mon = peripheral.find("monitor")
    if mon then
        mon.setTextScale(1) -- Bug 2 Fix: setTextScale(1) instead of 0.5
    end
    local monName = mon and peripheral.getName(mon)
    if not monName then print("Warning: monitor not found!") end

    storage.refresh()
    _G.NETWORK_INVENTORIES = util.getInventories()
    refreshScannerCache()

    if monName then ui.draw(monName) end -- Draw UI immediately at startup

    local dirty = false
    local feedback_timer = nil

    local function scanLoop()
        while true do
            storage.refresh()
            _G.NETWORK_INVENTORIES = util.getInventories()
            if _G.GRID_NAME then
                recipes.arrange_grid(_G.GRID_NAME)
            end
            refreshScannerCache()
            dispatcher.processQueue()

            dirty = true
            os.queueEvent("scan_complete")

            os.sleep(1.0)
        end
    end

    local function eventLoop()
        while true do
            local event, p1, p2, p3 = os.pullEvent()

            if event == "rednet_message" then
                local id, msg = p1, p2
                if type(msg) == "table" and msg.protocol == net.PROTOCOL then
                    local state_changed = false
                    if msg.type == "DISCOVER" then
                        net.send(id, "DISCOVER_ACK", { id = os.getComputerID() })
                        local in_chest = msg.data.input_chest
                        local out_chest = msg.data.output_chest
                        if isLocalSide(in_chest) then in_chest = nil end
                        if isLocalSide(out_chest) then out_chest = nil end
                        
                        if in_chest and out_chest then
                            dispatcher.assignWorkerBuffers(id, in_chest, out_chest)
                        else
                            dispatcher.autoAssignBuffers(id)
                        end
                        state_changed = true
                    elseif msg.type == "RESULT" then
                        local tid = msg.data and msg.data.task_id
                        if type(tid) == "string" and tid:sub(1, 5) == "test_" then
                            handle_test_result(id, msg.data.success, msg.data.error)
                        else
                            dispatcher.handleResult(id, tid, msg.data.success, msg.data.error)
                        end
                        state_changed = true
                    elseif msg.type == "HEARTBEAT" then
                        if not dispatcher.workers[id] then 
                            dispatcher.workers[id] = { status = "IDLE" } 
                            state_changed = true
                        end
                        if dispatcher.workers[id].status ~= msg.data.status then
                            dispatcher.workers[id].status = msg.data.status
                            state_changed = true
                        end
                        local in_chest = msg.data.input_chest
                        local out_chest = msg.data.output_chest
                        if isLocalSide(in_chest) then in_chest = nil end
                        if isLocalSide(out_chest) then out_chest = nil end
                        
                        if in_chest and out_chest then
                            local w = dispatcher.workers[id]
                            if not w.buffers or w.buffers.input ~= in_chest or w.buffers.output ~= out_chest then
                                dispatcher.assignWorkerBuffers(id, in_chest, out_chest)
                                state_changed = true
                            end
                        end
                    end
                    if state_changed then
                        dirty = true
                    end
                end

            elseif event == "monitor_touch" then
                local _, x, y = p1, p2, p3
                local bid = ui.touch(x, y)
                if bid then
                    ui.pressed = bid
                    dirty = true
                    feedback_timer = os.startTimer(0.1)

                    handleButton(bid)
                end

            elseif event == "timer" then
                if feedback_timer and p1 == feedback_timer then
                    ui.pressed = nil
                    dirty = true
                    feedback_timer = nil
                end
            end

            if dirty then
                if monName then ui.draw(monName) end
                dirty = false
            end
        end
    end

    parallel.waitForAny(eventLoop, scanLoop)
end

return { main = main }
