local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")

local ui = {
    current_tab = "DASHBOARD",
    modal = nil,
    buttons = {}
}

local function btn(mon, x, y, text, active)
    local x2 = x + #text + 1
    mon.setBackgroundColor(active and colors.blue or colors.gray)
    mon.setTextColor(colors.white)
    mon.setCursorPos(x, y)
    mon.write(" " .. text .. " ")
    table.insert(ui.buttons, {x1=x, y1=y, x2=x2, y2=y, action=text})
    return x2 + 1
end

function ui.draw(monName)
    local mon = peripheral.wrap(monName)
    if not mon then return end
    ui.buttons = {}
    mon.setBackgroundColor(colors.black)
    mon.clear()
    local w, h = mon.getSize()
    
    -- Header / Tabs
    local nx = 1
    nx = btn(mon, nx, 1, "DASH", ui.current_tab == "DASHBOARD")
    nx = btn(mon, nx, 1, "RECIPE", ui.current_tab == "RECIPES")
    nx = btn(mon, nx, 1, "SET", ui.current_tab == "SETTINGS")
    
    mon.setCursorPos(1, 2)
    mon.setTextColor(colors.gray)
    mon.write(string.rep("-", w))

    if ui.modal then
        ui.drawModal(mon, w, h)
    elseif ui.current_tab == "DASHBOARD" then
        mon.setCursorPos(1, 4)
        mon.setTextColor(colors.white)
        mon.write(" Workers online: " .. (table.maxn(dispatcher.workers) or 0))
    elseif ui.current_tab == "RECIPES" then
        mon.setCursorPos(1, 4)
        mon.setTextColor(colors.yellow)
        mon.write(" [SCAN GRID]")
        table.insert(ui.buttons, {x1=1, y1=4, x2=12, y2=4, action="SCAN"})
        
        mon.setCursorPos(1, 6)
        mon.setTextColor(colors.blue)
        mon.write(" List:")
        local row = 7
        for name, _ in pairs(recipes.data) do
            mon.setCursorPos(2, row)
            mon.setTextColor(colors.white)
            mon.write("- " .. (name:match(":(.+)") or name))
            row = row + 1
            if row > h then break end
        end
    elseif ui.current_tab == "SETTINGS" then
        mon.setCursorPos(1, 4)
        mon.write(" Select Grid Chest:")
        local row = 5
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "inventory" then
                mon.setCursorPos(2, row)
                local isGrid = (name == _G.GRID_NAME)
                mon.setTextColor(isGrid and colors.green or colors.white)
                mon.write((isGrid and "[X] " or "[ ] ") .. name)
                table.insert(ui.buttons, {x1=2, y1=row, x2=20, y2=row, action="SET_GRID:"..name})
                row = row + 1
            end
        end
    end
end

function ui.drawModal(mon, w, h)
    mon.setBackgroundColor(colors.gray)
    local x, y = 3, 5
    for i=0, 4 do
        mon.setCursorPos(x, y+i)
        mon.write(string.rep(" ", w-4))
    end
    mon.setCursorPos(x+1, y+1)
    mon.setTextColor(colors.white)
    mon.write(ui.modal.title)
    btn(mon, x+2, y+3, "CONFIRM", false)
    btn(mon, x+12, y+3, "CANCEL", false)
end

function ui.handleTouch(x, y)
    for _, b in ipairs(ui.buttons) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.action end
    end
end

return ui
