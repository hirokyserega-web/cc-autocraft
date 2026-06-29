local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")

local ui = {
    tab = "DASH",
    modal = nil,
    btns = {},
    scroll = 0
}

local function rect(mon, x, y, w, h, bg, border)
    if bg then
        mon.setBackgroundColor(bg)
        for i=0, h-1 do
            mon.setCursorPos(x, y+i)
            mon.write(string.rep(" ", w))
        end
    end
    if border then
        mon.setBackgroundColor(border)
        mon.setCursorPos(x, y)
        mon.write(string.rep(" ", w))
        mon.setCursorPos(x, y+h-1)
        mon.write(string.rep(" ", w))
        for i=0, h-1 do
            mon.setCursorPos(x, y+i)
            mon.write(" ")
            mon.setCursorPos(x+w-1, y+i)
            mon.write(" ")
        end
    end
end

local function draw_btn(mon, x, y, w, text, id, active)
    local bg = active and colors.blue or colors.gray
    mon.setBackgroundColor(bg)
    mon.setTextColor(colors.white)
    mon.setCursorPos(x, y)
    local label = " " .. text .. " "
    if #label < w then
        local pad = math.floor((w - #label) / 2)
        label = string.rep(" ", pad) .. label .. string.rep(" ", w - #label - pad)
    end
    mon.write(label)
    table.insert(ui.btns, {x1=x, y1=y, x2=x+w-1, y2=y, id=id})
end

local function draw_grid_preview(mon, x, y)
    mon.setBackgroundColor(colors.gray)
    for row=0, 2 do
        for col=0, 2 do
            mon.setCursorPos(x + col*4, y + row*2)
            mon.write("[ ]")
        end
    end
    mon.setCursorPos(x + 13, y + 2)
    mon.write("=> [?]")
end

local function draw_header(mon, w, h)
    rect(mon, 1, 1, w, 3, colors.gray)
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 2)
    mon.write("AUTOCRAFT SYSTEM")
    
    local tabs = {"DASH", "RECIPE", "CONF"}
    local tw = 10
    for i, t in ipairs(tabs) do
        draw_btn(mon, w - (4-i)*tw - (4-i), 2, tw, t, t, ui.tab == t)
    end
end

function ui.draw(monName)
    local mon = peripheral.wrap(monName)
    if not mon then return end
    ui.btns = {}
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    
    rect(mon, 1, 1, w, h, colors.lightGray)
    draw_header(mon, w, h)

    if ui.modal then
        ui.draw_modal(mon, w, h)
        return
    end

    if ui.tab == "DASH" then
        -- Left Panel
        rect(mon, 2, 5, 20, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(3, 6)
        mon.write("WORKERS")
        local y = 8
        for id, info in pairs(dispatcher.workers) do
            mon.setCursorPos(3, y)
            mon.setTextColor(info.status == "IDLE" and colors.green or colors.orange)
            mon.write(string.format("#%d [%s]", id, info.status))
            y = y + 1
            if y > h-2 then break end
        end

        -- Right Panel
        rect(mon, 24, 5, w-25, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(25, 6)
        mon.write("QUEUE")
        local y = 8
        for i = #dispatcher.queue, 1, -1 do
            local t = dispatcher.queue[i]
            mon.setCursorPos(25, y)
            mon.setTextColor(t.status == "COMPLETED" and colors.gray or colors.black)
            local name = t.name:match(":(.+)") or t.name
            mon.write(string.format("- %-10s x%d", name, t.count))
            y = y + 1
            if y > h-2 then break end
        end

    elseif ui.tab == "RECIPE" then
        rect(mon, 2, 5, 20, 10, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(3, 6)
        mon.write("RECIPE GRID")
        draw_grid_preview(mon, 3, 8)
        draw_btn(mon, 2, 16, 20, "SCAN CURRENT GRID", "SCAN", false)
        
        rect(mon, 24, 5, w-25, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(25, 6)
        mon.write("KNOWN RECIPES")
        local y = 8
        for name, data in pairs(recipes.data) do
            mon.setCursorPos(25, y)
            mon.write("> " .. (name:match(":(.+)") or name))
            y = y + 1
            if y > h-2 then break end
        end

    elseif ui.tab == "CONF" then
        mon.setTextColor(colors.black)
        mon.setCursorPos(2, 5)
        mon.write("SELECT SCANNER CHEST:")
        local y = 7
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
                local active = (_G.GRID_NAME == name)
                mon.setBackgroundColor(active and colors.blue or colors.white)
                mon.setTextColor(active and colors.white or colors.black)
                mon.setCursorPos(3, y)
                mon.write(string.format(" %-20s ", name))
                table.insert(ui.btns, {x1=3, y1=y, x2=w-2, y2=y, id="SET_GRID:"..name})
                y = y + 1
            end
        end
    end
end

function ui.draw_modal(mon, w, h)
    local mw, mh = 40, 12
    local mx, my = (w-mw)/2, (h-mh)/2
    rect(mon, mx, my, mw, mh, colors.white, colors.blue)
    mon.setTextColor(colors.black)
    mon.setBackgroundColor(colors.white)
    mon.setCursorPos(mx+2, my+2)
    mon.write("CONFIRM NEW RECIPE")
    mon.setCursorPos(mx+2, my+4)
    local result = tostring(ui.modal.title):match(":(.+)") or tostring(ui.modal.title)
    mon.write("Item: " .. result)
    mon.setCursorPos(mx+2, my+5)
    mon.write("Detected from central slots (4-24)")
    
    draw_btn(mon, mx+2, my+9, 15, "SAVE RECIPE", "OK", false)
    draw_btn(mon, mx+mw-17, my+9, 15, "DISCARD", "CANCEL", false)
end

function ui.touch(x, y)
    for _, b in ipairs(ui.btns) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.id end
    end
end

return ui
