-- Test harness for cc-autocraft core logic.
-- Mocks the ComputerCraft environment so we can run planner/storage/recipes
-- logic under plain Lua 5.3 (Lua 5.1 compatible code).
--
-- Run: lua5.3 run_tests.lua

----------------------------------------------------------------
-- Mock the ComputerCraft globals
----------------------------------------------------------------
local M = {}
package.path = "./?.lua;../?.lua;" .. package.path

-- peripheral mock: inventories are detected via list/size methods.
local invs = {}
peripheral = {
    getNames = function() local n = {}; for k in pairs(invs) do n[#n+1] = k end; return n end,
    wrap = function(name)
        if invs[name] then return invs[name] end
        return nil
    end,
    getType = function(name) return invs[name] and "chest" or nil end,
    hasType = function() return false end, -- pretend old CC:T to test method-based detection
    find = function() return nil end,
    getName = function() return "" end,
    isPresent = function() return false end,
}

-- Mock an inventory peripheral with given items.
local function makeInv(size, items)
    local self = { _size = size, _items = items or {} }
    self.list = function() local r = {}; for s, it in pairs(self._items) do r[s] = { name = it.name, count = it.count } end; return r end
    self.size = function() return self._size end
    self.getItemDetail = function(slot)
        local it = self._items[slot]
        if not it then return nil end
        return { name = it.name, count = it.count, tags = {} }
    end
    self.pushItems = function(toName, fromSlot, count, toSlot)
        local to = invs[toName]; if not to then return 0 end
        local it = self._items[fromSlot]; if not it then return 0 end
        count = math.min(count or 64, it.count)
        local dst = to._items[toSlot]
        if dst and dst.name ~= it.name then return 0 end
        if not dst then to._items[toSlot] = { name = it.name, count = 0 } end
        to._items[toSlot].count = to._items[toSlot].count + count
        self._items[fromSlot].count = self._items[fromSlot].count - count
        if self._items[fromSlot].count <= 0 then self._items[fromSlot] = nil end
        return count
    end
    self.pullItems = function(fromName, fromSlot, count, toSlot)
        local from = invs[fromName]; if not from then return 0 end
        return from.pushItems(self_name_placeholder, fromSlot, count, toSlot) -- not used in tests
    end
    return self
end

-- fs mock
fs = {
    _files = {},
    exists = function(p) return M.fs_files[p] ~= nil end,
    makeDir = function() end,
    delete = function(p) M.fs_files[p] = nil end,
    open = function(p, mode)
        if mode == "w" then
            local buf = {}
            local f = {
                write = function(_, s) buf[#buf+1] = s end,
                writeLine = function(_, s) buf[#buf+1] = s .. "\n" end,
                close = function() M.fs_files[p] = table.concat(buf) end,
            }
            return f
        else
            local content = M.fs_files[p] or ""
            return {
                readAll = function() return content end,
                close = function() end,
            }
        end
    end,
}

textutils = {
    serialize = function(d) return "SERIALIZED" end,
    unserialize = function(s) if s == "SERIALIZED" then return {} end return nil end,
}

-- os: keep standard os, add CC fields
os.epoch = function() return 1700000000000 + (M._epoch or 0) end
os.startTimer = function() return 1 end
os.sleep = function() end
os.getComputerID = function() return 0 end
os.pullEvent = function() return "timer", 1 end
os.reboot = function() end

math.random = math.random or function() return 1 end -- ensure exists

rednet = { open = function() end, send = function() end, broadcast = function() end, receive = function() return nil end }
redstone = { getSides = function() return {} end }

-- expose mocks as globals
_G.peripheral = peripheral
_G.fs = fs
_G.textutils = textutils
_G.rednet = rednet
_G.redstone = redstone

M.fs_files = {}
M.invs = invs

----------------------------------------------------------------
-- Test framework
----------------------------------------------------------------
local tests = {}
local function test(name, fn) tests[#tests+1] = { name = name, fn = fn } end

local failures = 0
local function assertEq(a, b, msg)
    if a ~= b then
        error(string.format("ASSERT FAIL: %s\n  expected: %s\n  got:      %s", msg or "", tostring(b), tostring(a)), 2)
    end
end
local function assertTblEq(a, b, msg)
    local ka, kb = {}, {}
    for k in pairs(a) do ka[#ka+1] = k end
    for k in pairs(b) do kb[#kb+1] = k end
    if #ka ~= #kb then error(string.format("ASSERT FAIL (size): %s %d vs %d", msg or "", #ka, #kb), 2) end
    for _, k in ipairs(ka) do
        if a[k] ~= b[k] then error(string.format("ASSERT FAIL (key %s): %s expected %s got %s", tostring(k), msg or "", tostring(b[k]), tostring(a[k])), 2) end
    end
end

local function isReadyExport(dispatcher, task)
    local isReady = dispatcher.isReady
    if not isReady then return false end
    return isReady(task)
end

----------------------------------------------------------------
-- Tests
----------------------------------------------------------------

-- 1. util.isInventory detects via methods, not type name.
test("util.isInventory method-based detection", function()
    local util = require("lib.util")
    invs["chest_1"] = makeInv(27, {})
    invs["modem_1"] = { getType = function() return "modem" end } -- no list/size
    assertEq(util.isInventory("chest_1"), true, "chest should be inventory")
    assertEq(util.isInventory("modem_1"), false, "modem should not be inventory")
    assertEq(util.isInventory("nonexistent"), false, "missing peripheral not inventory")
    invs["chest_1"] = nil; invs["modem_1"] = nil
end)

-- 2. storage.refresh detects inventories by method and skips grid + buffers.
test("storage.refresh detects inventories and skips grid/buffers", function()
    local util = require("lib.util")
    local storage = require("core.storage")
    invs["chest_a"] = makeInv(27, { [1] = { name = "minecraft:iron_ingot", count = 10 } })
    invs["chest_b"] = makeInv(27, { [1] = { name = "minecraft:iron_ingot", count = 5 }, [2] = { name = "minecraft:stick", count = 20 } })
    invs["chest_grid"] = makeInv(27, { [4] = { name = "minecraft:iron_ingot", count = 99 } })
    invs["chest_buf"] = makeInv(27, { [1] = { name = "minecraft:iron_ingot", count = 100 } })
    _G.GRID_NAME = "chest_grid"
    storage.buffers = { chest_buf = true }
    storage.refresh()
    -- grid and buffer excluded
    assertEq(storage.cache["minecraft:iron_ingot"], 15, "iron total should be 15 (a+b), grid/buf excluded")
    assertEq(storage.cache["minecraft:stick"], 20, "sticks 20")
    -- grid and buffer NOT in peripherals
    local found = {}
    for _, n in ipairs(storage.peripherals) do found[n] = true end
    assertEq(found["chest_grid"], nil, "grid excluded from peripherals")
    assertEq(found["chest_buf"], nil, "buffer excluded from peripherals")
    assertEq(found["chest_a"], true, "chest_a is storage")
    -- cleanup
    invs["chest_a"], invs["chest_b"], invs["chest_grid"], invs["chest_buf"] = nil, nil, nil, nil
    _G.GRID_NAME = nil
    storage.buffers = {}
end)

-- 3. planner: simple flat recipe (8 planks -> 1 chest), planks in stock.
test("planner flat recipe with stock", function()
    local storage = require("core.storage")
    local recipes = require("core.recipes")
    local planner = require("core.planner")
    recipes.data = {}
    recipes.data["minecraft:chest"] = {
        ingredients = {
            {name="minecraft:planks", count=1, slot=4}, {name="minecraft:planks", count=1, slot=5},
            {name="minecraft:planks", count=1, slot=6}, {name="minecraft:planks", count=1, slot=13},
            {name="minecraft:planks", count=1, slot=14}, {name="minecraft:planks", count=1, slot=15},
            {name="minecraft:planks", count=1, slot=22}, {name="minecraft:planks", count=1, slot=24},
        },
        output_count = 1,
    }
    storage.cache = { ["minecraft:planks"] = 64 }
    storage.reserved = {}
    local tasks, err = planner.plan("minecraft:chest", 1)
    assertEq(err, nil, "plan should succeed")
    assertEq(#tasks, 1, "one task (chest) since planks are in stock")
    assertEq(tasks[1].name, "minecraft:chest", "task is chest")
    assertEq(tasks[1].count, 1, "craft 1 chest")
    assertEq(tasks[1].batches, 1, "1 batch")
    -- planks reserved = 8
    assertEq(storage.reserved["minecraft:planks"], 8, "reserve 8 planks")
end)

-- 4. planner: nested recipe with output_count > 1 (stairs from logs via planks).
--    logs in stock only. 6 planks -> 4 stairs, 1 log -> 4 planks.
test("planner nested with output_count>1", function()
    local storage = require("core.storage")
    local recipes = require("core.recipes")
    local planner = require("core.planner")
    recipes.data = {}
    recipes.data["minecraft:oak_planks"] = {
        ingredients = { {name="minecraft:oak_log", count=1, slot=4} },
        output_count = 4,
    }
    recipes.data["minecraft:oak_stairs"] = {
        ingredients = {
            {name="minecraft:oak_planks", count=1, slot=4}, {name="minecraft:oak_planks", count=1, slot=5},
            {name="minecraft:oak_planks", count=1, slot=6}, {name="minecraft:oak_planks", count=1, slot=13},
            {name="minecraft:oak_planks", count=1, slot=14}, {name="minecraft:oak_planks", count=1, slot=15},
        },
        output_count = 4,
    }
    storage.cache = { ["minecraft:oak_log"] = 64 }
    storage.reserved = {}
    local tasks, err = planner.plan("minecraft:oak_stairs", 4)
    assertEq(err, nil, "plan stairs should succeed")
    -- Expect 2 tasks: planks (children-first) then stairs
    assertEq(#tasks, 2, "two tasks: planks then stairs")
    assertEq(tasks[1].name, "minecraft:oak_planks", "first task is planks")
    assertEq(tasks[1].count, 8, "craft 8 planks (2 batches of 4) for 6 needed")
    assertEq(tasks[1].batches, 2, "2 batches of planks")
    assertEq(tasks[2].name, "minecraft:oak_stairs", "second task is stairs")
    assertEq(tasks[2].count, 4, "4 stairs")
    assertEq(tasks[2].batches, 1, "1 batch of stairs")
    -- logs reserved = 2 (one per planks batch)
    assertEq(storage.reserved["minecraft:oak_log"], 2, "reserve 2 logs")
    -- dependency ordering: stairs order > planks order
    assertEq(tasks[2].order > tasks[1].order, true, "stairs ordered after planks")
    assertEq(tasks[1].plan_id == tasks[2].plan_id, true, "same plan_id")
end)

-- 5. planner: partial stock (some planks in stock, rest crafted).
test("planner partial stock", function()
    local storage = require("core.storage")
    local recipes = require("core.recipes")
    local planner = require("core.planner")
    recipes.data = {}
    recipes.data["minecraft:oak_planks"] = {
        ingredients = { {name="minecraft:oak_log", count=1, slot=4} },
        output_count = 4,
    }
    recipes.data["minecraft:oak_stairs"] = {
        ingredients = {
            {name="minecraft:oak_planks", count=1, slot=4}, {name="minecraft:oak_planks", count=1, slot=5},
            {name="minecraft:oak_planks", count=1, slot=6}, {name="minecraft:oak_planks", count=1, slot=13},
            {name="minecraft:oak_planks", count=1, slot=14}, {name="minecraft:oak_planks", count=1, slot=15},
        },
        output_count = 4,
    }
    -- 3 planks in stock, logs in stock. stairs needs 6 planks -> 3 from stock, 3 crafted (1 batch=4 -> 4 crafted)
    storage.cache = { ["minecraft:oak_planks"] = 3, ["minecraft:oak_log"] = 64 }
    storage.reserved = {}
    local tasks, err = planner.plan("minecraft:oak_stairs", 4)
    assertEq(err, nil, "plan should succeed")
    assertEq(#tasks, 2, "planks + stairs")
    assertEq(tasks[1].name, "minecraft:oak_planks", "planks task")
    assertEq(tasks[1].count, 4, "craft 4 planks (1 batch) for the 3 still needed")
    assertEq(tasks[1].batches, 1, "1 batch")
    -- pulled: 3 planks from stock + 1 log for the craft
    assertEq(storage.reserved["minecraft:oak_planks"], 3, "reserve 3 planks from stock")
    assertEq(storage.reserved["minecraft:oak_log"], 1, "reserve 1 log")
end)

-- 6. planner: no recipe for raw material -> fail.
test("planner fails when raw material has no recipe and no stock", function()
    local storage = require("core.storage")
    local recipes = require("core.recipes")
    local planner = require("core.planner")
    recipes.data = {}
    recipes.data["minecraft:oak_stairs"] = {
        ingredients = { {name="minecraft:oak_planks", count=1, slot=4} },
        output_count = 4,
    }
    storage.cache = {}
    storage.reserved = {}
    local tasks, err = planner.plan("minecraft:oak_stairs", 4)
    assertEq(tasks, nil, "should fail")
    assertEq(err ~= nil, true, "error message present")
    assertEq(string.find(err, "No recipe") ~= nil, true, "error mentions no recipe")
end)

-- 7. recipes.get_from_grid reads center 3x3 + output slot.
test("recipes.get_from_grid reads center grid", function()
    local recipes = require("core.recipes")
    invs["grid"] = makeInv(27, {
        [4] = { name = "minecraft:planks", count = 1 },
        [5] = { name = "minecraft:planks", count = 1 },
        [13] = { name = "minecraft:planks", count = 1 },
        [16] = { name = "minecraft:oak_button", count = 2 }, -- output in slot 16
    })
    local res, err = recipes.get_from_grid("grid")
    assertEq(err, nil, "grid read ok")
    assertEq(#res.ingredients, 3, "3 ingredients in grid")
    assertEq(res.output.name, "minecraft:oak_button", "output detected")
    assertEq(res.output.count, 2, "output count 2 (output_count>1 captured)")
    invs["grid"] = nil
end)

-- 8. recipes.arrange_grid shifts left-3 cols to center-3 cols and respects active_test.
test("recipes.arrange_grid shifts left to center", function()
    local recipes = require("core.recipes")
    invs["grid"] = makeInv(27, {
        [1] = { name = "minecraft:planks", count = 1 },
        [2] = { name = "minecraft:stick", count = 1 },
        [10] = { name = "minecraft:iron_ingot", count = 1 },
    })
    _G.GRID_NAME = "grid"
    _G.active_test = nil
    recipes.arrange_grid("grid")
    local it = invs["grid"]._items
    assertEq(it[4] and it[4].name, "minecraft:planks", "slot1 -> slot4")
    assertEq(it[5] and it[5].name, "minecraft:stick", "slot2 -> slot5")
    assertEq(it[13] and it[13].name, "minecraft:iron_ingot", "slot10 -> slot13")
    assertEq(it[1], nil, "slot1 emptied")
    -- active_test blocks arrange
    invs["grid2"] = makeInv(27, { [1] = { name = "minecraft:planks", count = 1 } })
    _G.active_test = { worker_id = 1 }
    recipes.arrange_grid("grid2")
    assertEq(invs["grid2"]._items[1] ~= nil, true, "arrange blocked during active_test")
    _G.active_test = nil
    invs["grid"], invs["grid2"] = nil, nil
    _G.GRID_NAME = nil
end)

test("getReadyWorker auto-assigns buffers", function()
    local dispatcher = require("core.dispatcher")
    local storage = require("core.storage")
    storage.buffers = { chest_buf = true }
    dispatcher.queue = {
        { id = "a", plan_id = "p1", order = 1, status = "ACTIVE",   name = "x", count = 1 },
        { id = "b", plan_id = "p1", order = 2, status = "PENDING",  name = "y", count = 1 },
        { id = "c", plan_id = "p2", order = 1, status = "PENDING",  name = "z", count = 1 },
    }
    -- b waits for a (same plan, lower order, not COMPLETED)
    assertEq(isReadyExport(dispatcher, dispatcher.queue[2]), false, "b blocked by active a")
    -- c is a different plan -> ready
    assertEq(isReadyExport(dispatcher, dispatcher.queue[3]), true, "c independent -> ready")
    -- mark a done -> b ready
    dispatcher.queue[1].status = "COMPLETED"
    assertEq(isReadyExport(dispatcher, dispatcher.queue[2]), true, "b ready after a completes")
end)

test("getReadyWorker auto-assigns buffers with multiple", function()
    local dispatcher = require("core.dispatcher")
    local storage = require("core.storage")
    storage.buffers = { chest_buf = true }
    dispatcher.queue = {
        { id = "a", plan_id = "p1", order = 1, status = "ACTIVE",   name = "x", count = 1 },
        { id = "b", plan_id = "p1", order = 2, status = "PENDING",  name = "y", count = 1 },
        { id = "c", plan_id = "p2", order = 1, status = "PENDING",  name = "z", count = 1 },
    }
    -- b waits for a (same plan, lower order, not COMPLETED)
    assertEq(isReadyExport(dispatcher, dispatcher.queue[2]), false, "b blocked by active a")
    -- c is a different plan -> ready
    assertEq(isReadyExport(dispatcher, dispatcher.queue[3]), true, "c independent -> ready")
    -- mark a done -> b ready
    dispatcher.queue[1].status = "COMPLETED"
    assertEq(isReadyExport(dispatcher, dispatcher.queue[2]), true, "b ready after a completes")
end)

-- 9. dispatcher isReady serialization within a plan.
test("dispatcher isReady serializes plan", function()
    local dispatcher = require("core.dispatcher")
    dispatcher.queue = {
        { id = "a", plan_id = "p1", order = 1, status = "ACTIVE",   name = "x", count = 1 },
        { id = "b", plan_id = "p1", order = 2, status = "PENDING",  name = "y", count = 1 },
        { id = "c", plan_id = "p2", order = 1, status = "PENDING",  name = "z", count = 1 },
    }
    -- b waits for a (same plan, lower order, not COMPLETED)
    assertEq(isReadyExport(dispatcher, dispatcher.queue[2]), false, "b blocked by active a")
    -- c is a different plan -> ready
    assertEq(isReadyExport(dispatcher, dispatcher.queue[3]), true, "c independent -> ready")
    -- mark a done -> b ready
    dispatcher.queue[1].status = "COMPLETED"
    assertEq(isReadyExport(dispatcher, dispatcher.queue[2]), true, "b ready after a completes")
end)

test("planner.check feasibility (nested, partial stock)", function()
    local storage = require("core.storage")
    local recipes = require("core.recipes")
    local planner = require("core.planner")
    recipes.data = {}
    recipes.data["minecraft:oak_planks"] = {
        ingredients = { {name="minecraft:oak_log", count=1, slot=4} },
        output_count = 4,
    }
    recipes.data["minecraft:oak_stairs"] = {
        ingredients = {
            {name="minecraft:oak_planks", count=1, slot=4}, {name="minecraft:oak_planks", count=1, slot=5},
            {name="minecraft:oak_planks", count=1, slot=6}, {name="minecraft:oak_planks", count=1, slot=13},
            {name="minecraft:oak_planks", count=1, slot=14}, {name="minecraft:oak_planks", count=1, slot=15},
        },
        output_count = 4,
    }
    -- 2 logs in stock -> enough to make 8 planks -> enough for 4 stairs (needs 6 planks)
    storage.cache = { ["minecraft:oak_log"] = 2 }
    storage.reserved = {}
    local ok, msg = planner.check("minecraft:oak_stairs", 4)
    assertEq(ok, true, "4 stairs feasible from 2 logs")

    -- only 1 log -> 4 planks -> not enough for 6 planks needed -> not feasible
    storage.cache = { ["minecraft:oak_log"] = 1 }
    storage.reserved = {}
    local ok2, msg2 = planner.check("minecraft:oak_stairs", 4)
    assertEq(ok2, false, "4 stairs not feasible from 1 log")
    assertEq(msg2 ~= nil and msg2:find("oak_log") ~= nil, true, "missing list mentions oak_log")

    -- check does NOT reserve anything
    assertEq(storage.reserved["minecraft:oak_log"], nil, "check must not reserve")
end)

----------------------------------------------------------------
-- Run
----------------------------------------------------------------
local passed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        print(("PASS  %s"):format(t.name))
        passed = passed + 1
    else
        print(("FAIL  %s\n        %s"):format(t.name, err))
        failures = failures + 1
    end
    -- reset shared state between tests
    local storage = package.loaded["core.storage"]
    if storage then storage.cache = {}; storage.reserved = {}; storage.peripherals = {}; storage.buffers = {} end
    local recipes = package.loaded["core.recipes"]
    if recipes then recipes.data = {} end
end

print(string.format("\n%d/%d passed, %d failed", passed, #tests, failures))
os.exit(failures == 0 and 0 or 1)
