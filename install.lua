local GITHUB_BASE = "https://raw.githubusercontent.com/hirokyserega-web/cc-autocraft/main/"
local files = {
    "lib/util.lua", "lib/net.lua", "lib/itemmatch.lua", "lib/lang.lua",
    "core/storage.lua", "core/recipes.lua", "core/planner.lua", "core/dispatcher.lua",
    "core/server.lua", "worker/worker.lua", "ui/monitor.lua", "config.lua", "main.lua"
}

print("CC-AUTOCRAFT 2.0 - CLEAN INSTALL")

local function download(path)
    local url = GITHUB_BASE .. path .. "?t=" .. os.epoch("utc")
    local res = http.get(url)
    if not res then return false end
    local content = res.readAll()
    res.close()
    
    if path:find("/") then
        local dir = path:match("(.+)/")
        if not fs.exists(dir) then fs.makeDir(dir) end
    end
    
    if fs.exists(path) then fs.delete(path) end
    local f = fs.open(path, "w")
    f.write(content)
    f.close()
    return true
end

-- CLEANING EVERYTHING
print("Cleaning old files...")
local old = {"lib", "core", "worker", "ui", "data", "main.lua", "startup.lua"}
for _, d in ipairs(old) do if fs.exists(d) then fs.delete(d) end end

for _, file in ipairs(files) do
    print("Downloading: " .. file)
    if not download(file) then print("FAILED: " .. file) end
end

local f = fs.open("startup.lua", "w")
f.writeLine("shell.run('main.lua run')")
f.close()

print("\nDONE! REBOOTING SYSTEM...")
os.reboot()
