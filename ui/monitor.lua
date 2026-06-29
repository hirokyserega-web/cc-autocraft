local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")

local ui = {
    current_tab = "DASH",
    modal = nil,
    buttons = {}
}

local function rect(mon, x, y, w, h, color)
    mon.setBackgroundColor(color)
    for i=0, h-1 do
        mon.setCursorPos(x, y+i)
        mon.write(string.rep(" ", w))
    end
end

local function btn(mon, x, y, w, text, action, active)
    mon.setBackgroundColor(active and colors.blue or colors.gray)
    mon.setTextColor(colors.white)
    mon.setCursorPos(x, y)
    local pad = math.floor((w - #text) / 2)
    mon.write(string.rep(" ", pad) .. text .. string.rep(" ", w - #text - pad))
    table.insert(ui.buttons, {x1=x, y1=y, x2=x+w-1, y2=y, action=action})
end

function ui.draw(monName)
    local mon = peripheral.wrap(monName)
    if not mon then return end
    ui.buttons = {}
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    
    rect(mon, 1, 1, w, h, colors.black)
    
    -- Header
    rect(mon, 1, 1, w, 3, colors.gray)
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(2, 2)
    mon.write("CC-AUTOCRAFT 2.0")
    
    local tw = 7
    btn(mon, w-tw*3-2, 2, tw, "DASH", "TAB:DASH", ui.current_tab == "DASH")
    btn(mon, w-tw*2-1, 2, tw, "RECIPE", "TAB:RECIPE", ui.current_tab == "RECIPE")
    btn(mon, w-tw, 2, tw, "CONF", "TAB:CONF", ui.current_tab == "CONF")

    if ui.modal then
        ui.drawModal(mon, w, h)
        return
    end

    if ui.current_tab == "DASH" then
        mon.setCursorPos(2, 5)
        mon.setTextColor(colors.cyan)
        mon.write("ACTIVE WORKERS:")
        local row = 6
        for id, info in pairs(dispatcher.workers) do
            mon.setCursorPos(3, row)
            mon.setTextColor(info.status == "IDLE" and colors.green or colors.orange)
            mon.write(string.format("[%d] %s", id, info.status))
            row = row + 1
        end
        
        mon.setCursorPos(20, 5)
        mon.setTextColor(colors.cyan)
        mon.write("QUEUE:")
        row = 6
        for i = #dispatcher.queue, math.max(1, #dispatcher.queue-8), -1 do
            local t = dispatcher.queue[i]
            mon.setCursorPos(21, row)
            mon.setTextColor(t.status == "COMPLETED" and colors.green or colors.white)
            mon.write(string.format("%s x%d", t.name:match(":(.+)") or t.name, t.count))
            row = row + 1
        end
    elseif ui.current_tab == "RECIPE" then
        btn(mon, 2, 5, 12, "SCAN GRID", "SCAN", false)
        mon.setCursorPos(2, 7)
        mon.setTextColor(colors.blue)
        mon.write("SAVED:")
        local row = 8
        for name, _ in pairs(recipes.data) do
            mon.setCursorPos(3, row)
            mon.setTextColor(colors.white)
            mon.write("- " .. (name:match(":(.+)") or name))
            row = row + 1
        end
    elseif ui.current_tab == "CONF" then
        mon.setCursorPos(2, 5)
        mon.setTextColor(colors.blue)
        mon.write("SELECT GRID CHEST:")
        local row = 6
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
                local active = (_G.GRID_NAME == name)
                mon.setCursorPos(2, row)
                mon.setTextColor(active and colors.green or colors.white)
                mon.write((active and "[X] " or "[ ] ") .. name)
                table.insert(ui.buttons, {x1=2, y1=row, x2=20, y2=row, action="SET_GRID:"..name})
                row = row + 1
                if row > h then break end
            end
        end
    end
end

function ui.drawModal(mon, w, h)
    local mw, mh = 26, 6
    local mx, my = math.floor((w-mw)/2), math.floor((h-mh)/2)
    rect(mon, mx, my, mw, mh, colors.lightGray)
    mon.setTextColor(colors.black)
    mon.setCursorPos(mx+1, my+1)
    mon.write("SAVE RECIPE?")
    btn(mon, mx+2, my+4, 10, "YES", "MODAL_OK", false)
    btn(mon, mx+14, my+4, 10, "NO", "MODAL_CANCEL", false)
end

function ui.handleTouch(x, y)
    for _, b in ipairs(ui.buttons) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.action end
    end
end

return ui
