-- Storage management and resource reservation
local storage = {}
local util = require("lib.util")

storage.cache = {}       -- { [name] = count }
storage.reserved = {}    -- { [name] = count }
storage.peripherals = {} -- names of inventory peripherals used as general storage
storage.buffers = {}     -- { [bufferName] = true } (populated by dispatcher)

-- Rebuild the cache of all items across every inventory that is NOT the
-- active scanner grid and NOT a worker buffer. Those are treated specially.
function storage.refresh()
    storage.cache = {}
    local _op = 0  -- yields
    storage.peripherals = {}
    local names = peripheral.getNames()
    local _op = 0
    for _, name in ipairs(names) do
        _op = _op + 1; util.maybeYield(_op, 8)
        if util.isInventory(name) then
            -- Skip the active recipe grid and worker buffer chests
            if name ~= _G.GRID_NAME and not storage.buffers[name] then
                table.insert(storage.peripherals, name)
                local p = peripheral.wrap(name)
                if p then
                    local items = p.list()
                    local size = p.size() or 27
                    for slot = 1, size do
                        local item = items[slot]
                        if item then
                            storage.cache[item.name] = (storage.cache[item.name] or 0) + item.count
                        end
                    end
                end
            end
        end
    end
end

function storage.getAvailable(name)
    local total = storage.cache[name] or 0
    local res = storage.reserved[name] or 0
    return math.max(0, total - res)
end

function storage.reserve(name, count)
    local avail = storage.getAvailable(name)
    if avail >= count then
        storage.reserved[name] = (storage.reserved[name] or 0) + count
        return true
    end
    return false
end

function storage.release(name, count)
    if storage.reserved[name] then
        storage.reserved[name] = math.max(0, storage.reserved[name] - count)
    end
end

-- Extract `count` of `itemName` from general storage into a target
-- peripheral/slot. Returns the number actually moved.
function storage.extract(itemName, count, toPeripheral, toSlot)
    if count <= 0 then return 0 end
    local remaining = count
    local _op = 0  -- yields
    for _, pName in ipairs(storage.peripherals) do
        if pName ~= toPeripheral and pName ~= _G.GRID_NAME and not storage.buffers[pName] then
            local p = peripheral.wrap(pName)
            if p then
                local items = p.list()
                local size = p.size() or 27
                for slot = 1, size do
                    _op = _op + 1; util.maybeYield(_op, 16)
                    local item = items[slot]
                    if item and item.name == itemName then
                        local moveCount = math.min(remaining, item.count)
                        local moved = p.pushItems(toPeripheral, slot, moveCount, toSlot)
                        remaining = remaining - (moved or 0)
                        if remaining <= 0 then break end
                    end
                end
            end
        end
        if remaining <= 0 then break end
    end
    return count - remaining
end

-- Pull items from a peripheral slot back into general storage.
-- Returns the number actually moved.
function storage.deposit(fromPeripheral, fromSlot, count)
    if count <= 0 then return 0 end
    local _op = 0  -- yields
    -- Read the source item so we can target matching/empty slots efficiently.
    local srcP = peripheral.wrap(fromPeripheral)
    local srcName = nil
    if srcP then
        local d = srcP.getItemDetail(fromSlot)
        if d then srcName = d.name end
    end
    local remaining = count
    for _, pName in ipairs(storage.peripherals) do
        if pName ~= fromPeripheral and pName ~= _G.GRID_NAME and not storage.buffers[pName] then
            local p = peripheral.wrap(pName)
            if p then
                local size = p.size() or 27
                local items = p.list()
                for slot = 1, size do
                    _op = _op + 1; util.maybeYield(_op, 16)
                    local existing = items[slot]
                    -- pullItems stacks same items and moves into empty slots;
                    -- it returns 0 for slots holding a different item, so we
                    -- skip those to avoid wasting calls.
                    if not existing or existing.name == srcName then
                        local moved = p.pullItems(fromPeripheral, fromSlot, remaining, slot)
                        remaining = remaining - (moved or 0)
                        if remaining <= 0 then break end
                    end
                end
            end
        end
        if remaining <= 0 then break end
    end
    return count - remaining
end

return storage
