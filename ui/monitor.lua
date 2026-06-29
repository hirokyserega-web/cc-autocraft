local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")

local ui = {
    tab = "DASH",
    modal = nil,
    btns = {},
    colors = {
        bg = colors.black,
        top = colors.gray,
        btn = colors.lightGray,
        active = colors.blue,
        text = colors.white,
        accent = colors.yellow
    }
}

local function box(mon, x, y, w, h, color)
    mon.setBackgroundColor(color)
    for i=0, h-1 do
        mon.setCursorPos(x, y+i)
        mon.write(string.rep(" ", w))
    end
end

local function draw_btn(mon, x, y, w, text, id, active)
    mon.setBackgroundColor(active and ui.colors.active or ui.colors.btn)
    mon.setTextColor(colors.white)
    mon.setCursorPos(x, y)
    local pad = math.floor((w - #text) / 2)
    mon.write(string.rep(" ", pad) .. text .. string.rep(" ", w - #text - pad))
    table.insert(ui.btns, {x1=x, y1=y, x2=x+w-1, y2=y, id=id})
end

function ui.draw(monName)
    local mon = peripheral.wrap(monName)
    if not mon then return end
    ui.btns = {}
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    
    -- Main BG
    box(mon, 1, 1, w, h, ui.colors.bg)
    
    -- TOP BAR
    box(mon, 1, 1, w, 3, ui.colors.top)
    mon.setCursorPos(2, 2)
    mon.setTextColor(ui.colors.accent)
    mon.write("AUTOCRAFT v2.0")
    
    local bw = 8
    draw_btn(mon, w-bw*3-2, 2, bw, "STATUS", "DASH", ui.tab == "DASH")
    draw_btn(mon, w-bw*2-1, 2, bw, "CRAFT", "RECIPE", ui.tab == "RECIPE")
    draw_btn(mon, w-bw, 2, bw, "CONFIG", "CONF", ui.tab == "CONF")

    if ui.modal then
        ui.draw_modal(mon, w, h)
        return
    end

    if ui.tab == "DASH" then
        -- LEFT: WORKERS
        box(mon, 2, 5, 22, 12, colors.gray)
        mon.setCursorPos(3, 5)
        mon.setTextColor(colors.yellow)
        mon.write(" WORKERS ONLINE ")
        local y = 7
        for id, info in pairs(dispatcher.workers) do
            mon.setCursorPos(3, y)
            mon.setTextColor(info.status == "IDLE" and colors.green or colors.orange)
            mon.write(string.format("[%d] %s", id, info.status))
            y = y + 1
            if y > 16 then break end
        end

        -- RIGHT: QUEUE
        box(mon, 26, 5, w-27, 12, colors.gray)
        mon.setCursorPos(27, 5)
        mon.setTextColor(colors.yellow)
        mon.write(" CRAFTING QUEUE ")
        local y = 7
        for i = #dispatcher.queue, math.max(1, #dispatcher.queue-8), -1 do
            local t = dispatcher.queue[i]
            mon.setCursorPos(27, y)
            mon.setTextColor(t.status == "COMPLETED" and colors.green or colors.white)
            mon.write(string.format("%s x%d", (t.name:match(":(.+)") or t.name):sub(1,10), t.count))
            y = y + 1
        end

    elseif ui.tab == "RECIPE" then
        draw_btn(mon, 2, 5, 15, "[ SCAN GRID ]", "SCAN", false)
        mon.setCursorPos(2, 7)
        mon.setTextColor(colors.blue)
        mon.write("LIBRARY:")
        local y = 8
        for name, _ in pairs(recipes.data) do
            mon.setCursorPos(3, y)
            mon.setTextColor(colors.white)
            mon.write("- " .. (name:match(":(.+)") or name))
            y = y + 1
            if y > h then break end
        end

    elseif ui.tab == "CONF" then
        mon.setCursorPos(2, 5)
        mon.setTextColor(colors.blue)
        mon.write("SELECT SCANNER CHEST:")
        local y = 6
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
                local isGrid = (_G.GRID_NAME == name)
                mon.setCursorPos(2, y)
                mon.setTextColor(isGrid and colors.green or colors.white)
                mon.write((isGrid and "[X] " or "[ ] ") .. name)
                table.insert(ui.btns, {x1=2, y1=y, x2=25, y2=y, id="SET_GRID:"..name})
                y = y + 1
                if y > h then break end
            end
        end
    end
end

function ui.draw_modal(mon, w, h)
    local mw, mh = 26, 8
    local mx, my = math.floor((w-mw)/2), math.floor((h-mh)/2)
    box(mon, mx, my, mw, mh, colors.lightGray)
    mon.setTextColor(colors.black)
    mon.setCursorPos(mx+2, my+2)
    mon.write("SAVE THIS RECIPE?")
    mon.setCursorPos(mx+2, my+3)
    mon.write(tostring(ui.modal.title):sub(1, mw-4))
    draw_btn(mon, mx+2, my+6, 10, "SAVE", "OK", false)
    draw_btn(mon, mx+14, my+6, 10, "CANCEL", "CANCEL", false)
end

function ui.touch(x, y)
    for _, b in ipairs(ui.btns) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.id end
    end
end

return ui
