-- Item matching logic (tags, NBT, name)
local itemmatch = {}

function itemmatch.matches(item, spec)
    -- spec: { name = "...", tag = "...", nbt = "..." }
    if not item then return false end
    
    if spec.name and item.name ~= spec.name then
        return false
    end
    
    if spec.tag then
        -- В CC:T теги обычно приходят в детальном описании предмета
        -- Здесь мы предполагаем, что item содержит поле tags
        local hasTag = false
        if item.tags then
            for tag, _ in pairs(item.tags) do
                if tag == spec.tag then hasTag = true break end
            end
        end
        if not hasTag then return false end
    end
    
    if spec.nbt and item.nbt ~= spec.nbt then
        return false
    end

    return true
end

return itemmatch
