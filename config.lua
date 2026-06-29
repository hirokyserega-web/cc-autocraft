-- Base configuration
local config = {}

config.transfer_mode = "buffer" -- "buffer" | "wired"
config.storage_name = "top"    -- default for testing
config.core_id = nil           -- will be auto-discovered

function config.load()
    if fs.exists("config.local.lua") then
        local local_cfg = dofile("config.local.lua")
        for k, v in pairs(local_cfg) do config[k] = v end
    end
end

return config
