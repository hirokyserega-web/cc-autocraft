-- Utility functions for cc-autocraft
local util = {}

function util.deepCopy(obj)
    if type(obj) ~= "table" then return obj end
    local res = {}
    for k, v in pairs(obj) do res[util.deepCopy(k)] = util.deepCopy(v) end
    return res
end

function util.save(path, data)
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
    print(("[%s] %s"):format(level, msg))
    local f = fs.open("latest.log", "a")
    if f then
        f.writeLine(("[%s] %s"):format(level, msg))
        f.close()
    end
end

-- Безопасная сериализация без циклов
function util.safeSerialize(data)
    local ok, res = pcall(textutils.serialize, data, { allow_repetitions = true })
    if ok then return res end
    -- Fallback: упрощенная копия без вложенности если упало
    util.log("Serialization failed, attempting fallback", "WARN")
    return textutils.serialize(tostring(data))
end

return util
