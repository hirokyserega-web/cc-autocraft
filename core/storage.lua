-- Storage management and resource reservation
local storage = {}
local util = require("lib.util")

storage.cache = {} -- { [name] = count }
storage.reserved = {} -- { [name] = count }
storage.peripherals = {} -- names of inventory peripherals

function storage.refresh()
    storage.cache = {}
    storage.peripherals = {}
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
            table.insert(storage.peripherals, name)
            local p = peripheral.wrap(name)
            local items = p.list()
            for _, item in pairs(items) do
                storage.cache[item.name] = (storage.cache[item.name] or 0) + item.count
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

-- Push items to a specific destination
function storage.extract(itemName, count, toPeripheral, toSlot)
    local remaining = count
    for _, pName in ipairs(storage.peripherals) do
        if pName ~= toPeripheral then
            local p = peripheral.wrap(pName)
            local items = p.list()
            for slot, item in pairs(items) do
                if item.name == itemName then
                    local moveCount = math.min(remaining, item.count)
                    local moved = p.pushItems(toPeripheral, slot, moveCount, toSlot)
                    remaining = remaining - moved
                    if remaining <= 0 then break end
                end
            end
        end
        if remaining <= 0 then break end
    end
    return count - remaining
end

-- Pull items from a peripheral back to storage
function storage.deposit(fromPeripheral, fromSlot, count)
    local remaining = count
    for _, pName in ipairs(storage.peripherals) do
        if pName ~= fromPeripheral then
            local p = peripheral.wrap(pName)
            local moved = p.pullItems(fromPeripheral, fromSlot, remaining)
            remaining = remaining - moved
            if remaining <= 0 then break end
        end
    end
    return count - remaining
end

return storage
