-- Utility functions for cc-autocraft
local util = {}

function util.deepCopy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do res[util.deepCopy(k)] = util.deepCopy(v) end
    return res
end

function util.save(path, data)
    if not fs.exists(path) then
        local dir = path:match("(.+)/")
        if dir and not fs.exists(dir) then fs.makeDir(dir) end
    end
    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serialize(data))
        f.close()
        return true
    end
    return false
end

function util.saveSafe(path, data)
    local dir = path:match("(.+)/")
    if dir and not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serialize(data))
        f.close()
        return true
    end
    return false
end

function util.load(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if f then
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data
    end
    return nil
end

function util.log(msg, level)
    level = level or "INFO"
    local line = ("[%s] %s"):format(level, msg)
    print(line)
    local f = fs.open("latest.log", "a")
    if f then
        f.writeLine(line)
        f.close()
    end
end

-- Robust inventory detection that works on every CC:T version.
-- Older versions do not have peripheral.hasType, and peripheral.getType
-- returns the concrete type ("chest") rather than "inventory", so checking
-- for the inventory API methods (list + size) is the only reliable way.
function util.isInventory(name)
    if not name then return false end
    local p = peripheral.wrap(name)
    if not p then return false end
    -- Detect by capability, not by type string: getType returns "chest" (not
    -- "inventory"), and peripheral.hasType is missing on older CC:T builds and
    -- would crash when called as nil. Every inventory exposes list() + size().
    return type(p.list) == "function" and type(p.size) == "function"
end

-- Return a sorted list of every inventory peripheral name on the network.
function util.getInventories()
    local list = {}
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if util.isInventory(name) then
            table.insert(list, name)
        end
    end
    table.sort(list)
    return list
end

-- Shorten "minecraft:iron_ingot" -> "iron_ingot"
function util.cleanName(name)
    if not name then return "" end
    return name:match(":(.+)") or name
end


-- Yield helper for long-running sync loops. CC:T raises "Too long without
-- yielding" after a few hundred peripheral calls in a row. Pass an integer
-- counter that you bump on each iteration; this function calls os.sleep(0)
-- (a cheap yield that lets the Lua VM breathe) after every Nth call.
function util.maybeYield(counter, every)
    every = every or 64
    if counter % every == 0 then os.sleep(0) end
end
return util
