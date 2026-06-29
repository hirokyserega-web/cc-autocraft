local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")

local ui = {
    tab = "DASH",
    modal = nil,
    btns = {}
}

local function box(mon, x, y, w, h, color)
    mon.setBackgroundColor(color)
    for i=0, h-1 do
        mon.setCursorPos(x, y+i)
        mon.write(string.rep(" ", w))
    end
end

local function draw_btn(mon, x, y, w, text, id, active)
    mon.setBackgroundColor(active and colors.blue or colors.lightGray)
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
    
    box(mon, 1, 1, w, h, colors.black)
    
    -- NEON HEADER (Very Different from old one)
    box(mon, 1, 1, w, 3, colors.purple)
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 2)
    mon.write(" >> SYSTEM: AUTOCRAFT NEXT-GEN << ")
    
    local bw = 9
    draw_btn(mon, w-bw*3-2, 2, bw, "[STATUS]", "DASH", ui.tab == "DASH")
    draw_btn(mon, w-bw*2-1, 2, bw, "[RECIPES]", "RECIPE", ui.tab == "RECIPE")
    draw_btn(mon, w-bw, 2, bw, "[SETUP]", "CONF", ui.tab == "CONF")

    if ui.modal then
        ui.draw_modal(mon, w, h)
        return
    end

    if ui.tab == "DASH" then
        -- Stats
        mon.setTextColor(colors.cyan)
        mon.setCursorPos(2, 5)
        mon.write("--- WORKER STATUS ---")
        local y = 7
        for id, info in pairs(dispatcher.workers) do
            mon.setCursorPos(3, y)
            mon.setTextColor(info.status == "IDLE" and colors.green or colors.orange)
            mon.write(string.format("Turtle #%d: %s", id, info.status))
            y = y + 1
        end

        mon.setTextColor(colors.cyan)
        mon.setCursorPos(25, 5)
        mon.write("--- TASK QUEUE ---")
        y = 7
        for i = #dispatcher.queue, math.max(1, #dispatcher.queue-8), -1 do
            local t = dispatcher.queue[i]
            mon.setCursorPos(26, y)
            mon.setTextColor(t.status == "COMPLETED" and colors.green or colors.white)
            mon.write(string.format("%s (x%d)", t.name:match(":(.+)") or t.name, t.count))
            y = y + 1
        end

    elseif ui.tab == "RECIPE" then
        draw_btn(mon, 2, 5, 18, " CREATE FROM GRID ", "SCAN", false)
        mon.setCursorPos(2, 8)
        mon.setTextColor(colors.lightBlue)
        mon.write("ACTIVE DATABASE:")
        local y = 9
        for name, _ in pairs(recipes.data) do
            mon.setCursorPos(3, y)
            mon.setTextColor(colors.white)
            mon.write(">> " .. (name:match(":(.+)") or name))
            y = y + 1
        end

    elseif ui.tab == "CONF" then
        mon.setCursorPos(2, 5)
        mon.setTextColor(colors.purple)
        mon.write("CONFIG: SCANNER SOURCE")
        local y = 7
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
                local active = (_G.GRID_NAME == name)
                mon.setCursorPos(2, y)
                mon.setTextColor(active and colors.green or colors.white)
                mon.write((active and "[X] " or "[ ] ") .. name)
                table.insert(ui.btns, {x1=2, y1=y, x2=25, y2=y, id="SET_GRID:"..name})
                y = y + 1
            end
        end
    end
end

function ui.draw_modal(mon, w, h)
    box(mon, 5, 5, w-10, 8, colors.blue)
    mon.setTextColor(colors.white)
    mon.setCursorPos(7, 7)
    mon.write("CONFIRM NEW RECIPE?")
    mon.setCursorPos(7, 8)
    mon.write("Result: " .. tostring(ui.modal.title):sub(1, 20))
    draw_btn(mon, 7, 10, 10, "ACCEPT", "OK", false)
    draw_btn(mon, 20, 10, 10, "ABORT", "CANCEL", false)
end

function ui.touch(x, y)
    for _, b in ipairs(ui.btns) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.id end
    end
end

return ui
