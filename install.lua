-- Installation script
local GITHUB_URL = "https://raw.githubusercontent.com/hirokyserega-web/cc-autocraft/main/"

local files = {
    "lib/util.lua",
    "lib/net.lua",
    "lib/itemmatch.lua",
    "lib/lang.lua",
    "core/storage.lua",
    "core/recipes.lua",
    "core/planner.lua",
    "core/dispatcher.lua",
    "core/server.lua",
    "worker/worker.lua",
    "ui/monitor.lua",
    "config.lua"
}

print("Installing cc-autocraft...")

for _, file in ipairs(files) do
    print("Downloading " .. file .. "...")
    local resp = http.get(GITHUB_URL .. file)
    if resp then
        local f = fs.open(file, "w")
        f.write(resp.readAll())
        f.close()
        resp.close()
    else
        print("Failed to download " .. file)
    end
end

print("Installation complete!")
