local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")
local util = require("lib.util")
local widgets = require("ui.widgets")

local ui = {
    tab = "DASH",
    modal = nil,
    btns = {},
    pressed = nil,
    scroll = 0,
    recipe_scroll = 0,
    conf_scroll = 0
}

local theme = {
    bg = colors.black,
    sidebar = colors.gray,
    surface = colors.black,
    border = colors.gray,
    
    textBase = colors.white,
    textMuted = colors.lightGray,
    textActive = colors.black,
    
    accent = colors.lightBlue,
    btnBase = colors.blue,
    btnActive = colors.cyan,
    btnPressed = colors.white,
    
    ok = colors.lime,
    warn = colors.orange,
    bad = colors.red,
    
    header = colors.gray
}

local function cleanName(name)
    return util.cleanName(name)
end

local function shortName(name, n)
    return cleanName(name):sub(1, n or 16)
end

local function drawSidebar(mon, w, h)
    widgets.drawBox(mon, 1, 1, 10, h, theme.sidebar)
    
    local tabs = {
        { id = "DASH",    text = "HOME" },
        { id = "STORAGE", text = "ITEMS" },
        { id = "RECIPE",  text = "CRAFT" },
        { id = "CONF",    text = "CONF" }
    }
    
    for i, t in ipairs(tabs) do
        local y = 2 + (i - 1) * 4
        local id = "TAB:" .. t.id
        local isActive = (ui.tab == t.id)
        local isPressed = (ui.pressed == id)
        
        local bg = isPressed and theme.btnPressed or (isActive and theme.btnActive or theme.btnBase)
        widgets.drawButton(mon, 2, y, 8, 3, t.text, id, isActive or isPressed, theme, ui.btns)
    end
    
    local pingColor = theme.ok
    if #dispatcher.queue > 10 then pingColor = theme.warn end
    widgets.drawText(mon, 2, h - 1, "ONLINE", pingColor, theme.sidebar)
end

local function drawHeader(mon, w, h)
    local title = "SYSTEM"
    if ui.tab == "DASH" then title = "DASHBOARD"
    elseif ui.tab == "STORAGE" then title = "STORAGE"
    elseif ui.tab == "RECIPE" then title = "RECIPES & CRAFTING"
    elseif ui.tab == "CONF" then title = "SETTINGS"
    end
    
    widgets.drawBox(mon, 11, 1, w - 10, 3, theme.header)
    widgets.drawText(mon, 13, 2, title, theme.textBase, theme.header)
    
    local wc = 0
    for _ in pairs(dispatcher.workers) do wc = wc + 1 end
    local status = string.format("Q:%d W:%d", #dispatcher.queue, wc)
    widgets.drawText(mon, w - #status - 1, 2, status, theme.accent, theme.header)
end

local function drawDash(mon, w, h)
    local mainX = 12
    local mainW = w - 12
    
    local cardW = math.floor(mainW / 2) - 1
    widgets.drawBox(mon, mainX, 5, cardW, h - 5, theme.surface, theme.border)
    widgets.drawText(mon, mainX + 2, 6, "WORKERS", theme.accent, theme.surface)
    
    local y = 8
    for id, info in pairs(dispatcher.workers) do
        local col = theme.ok
        if info.status == "CRAFTING" then col = theme.accent
        elseif info.status ~= "IDLE" then col = theme.warn end
        
        widgets.drawText(mon, mainX + 2, y, string.format("#%-3s", id), theme.textBase, theme.surface)
        widgets.drawText(mon, mainX + 7, y, info.status, col, theme.surface)
        y = y + 1
        if y > h - 2 then break end
    end

    local tasksX = mainX + cardW + 1
    widgets.drawBox(mon, tasksX, 5, w - tasksX, h - 5, theme.surface, theme.border)
    widgets.drawText(mon, tasksX + 2, 6, "ACTIVE QUEUE", theme.accent, theme.surface)
    widgets.drawButton(mon, w - 8, 6, 6, 1, "CLR", "CLR_QUEUE", ui.pressed == "CLR_QUEUE", theme, ui.btns)

    y = 8
    for i = #dispatcher.queue, 1, -1 do
        local t = dispatcher.queue[i]
        local col = theme.textMuted
        if t.status == "ACTIVE" then col = theme.accent end
        
        widgets.drawText(mon, tasksX + 2, y, shortName(t.name, 12), col, theme.surface)
        widgets.drawText(mon, w - 8, y, string.format("x%d", t.count), theme.textBase, theme.surface)
        y = y + 1
        if y > h - 2 then break end
    end
end

local function drawStorage(mon, w, h)
    local mainX = 12
    local mainW = w - 12
    widgets.drawBox(mon, mainX, 5, mainW, h - 5, theme.surface, theme.border)
    
    widgets.drawButton(mon, w - 8, 6, 3, 1, "^", "SUP", ui.pressed == "SUP", theme, ui.btns)
    widgets.drawButton(mon, w - 4, 6, 3, 1, "v", "SDN", ui.pressed == "SDN", theme, ui.btns)
    
    local items = {}
    for name, qty in pairs(storage.cache) do
        table.insert(items, { name = name, qty = qty })
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    
    local y = 7
    local maxItems = h - 9
    for i = ui.scroll + 1, math.min(#items, ui.scroll + maxItems) do
        local item = items[i]
        local hasRecipe = recipes.has(item.name)
        local cid = "CRAFT_INIT:" .. item.name
        
        widgets.drawText(mon, mainX + 2, y, shortName(item.name, 20), hasRecipe and theme.ok or theme.textBase, theme.surface)
        widgets.drawText(mon, mainX + 24, y, string.format("x%d", item.qty), theme.textMuted, theme.surface)
        
        if hasRecipe then
            widgets.drawButton(mon, w - 9, y, 7, 1, "ORDER", cid, ui.pressed == cid, theme, ui.btns)
        end
        y = y + 1
    end
end

local function drawRecipes(mon, w, h)
    local mainX = 12
    local mainW = w - 12
    
    local leftW = 20
    widgets.drawBox(mon, mainX, 5, leftW, h - 5, theme.surface, theme.border)
    widgets.drawText(mon, mainX + 2, 6, "SCANNER", theme.accent, theme.surface)
    
    if not _G.GRID_NAME then
        widgets.drawText(mon, mainX + 2, 8, "NO SCANNER", theme.bad, theme.surface)
    else
        widgets.drawText(mon, mainX + 2, 8, shortName(_G.GRID_NAME, 16), theme.textMuted, theme.surface)
        widgets.drawButton(mon, mainX + 2, 10, 16, 3, "TEST CRAFT", "TEST_CRAFT", ui.pressed == "TEST_CRAFT", theme, ui.btns)
    end

    local listX = mainX + leftW + 1
    widgets.drawBox(mon, listX, 5, w - listX, h - 5, theme.surface, theme.border)
    widgets.drawText(mon, listX + 2, 6, "RECIPES", theme.accent, theme.surface)
    
    widgets.drawButton(mon, w - 8, 6, 3, 1, "^", "RSUP", ui.pressed == "RSUP", theme, ui.btns)
    widgets.drawButton(mon, w - 4, 6, 3, 1, "v", "RSDN", ui.pressed == "RSDN", theme, ui.btns)

    local recs = recipes.list()
    local y = 8
    for i = ui.recipe_scroll + 1, math.min(#recs, ui.recipe_scroll + (h - 10)) do
        local r = recs[i]
        local cid = "REC_CRAFT:" .. r.name
        local did = "REC_DEL:" .. r.name
        widgets.drawText(mon, listX + 2, y, shortName(r.name, 12), theme.textBase, theme.surface)
        widgets.drawButton(mon, w - 12, y, 6, 1, "CRAFT", cid, ui.pressed == cid, theme, ui.btns)
        widgets.drawButton(mon, w - 4, y, 2, 1, "X", did, ui.pressed == did, theme, ui.btns)
        y = y + 1
    end
end

local function drawSettings(mon, w, h)
    local mainX = 12
    local mainW = w - 12
    widgets.drawBox(mon, mainX, 5, mainW, h - 5, theme.surface, theme.border)
    
    widgets.drawButton(mon, w - 8, 6, 3, 1, "^", "CSUP", ui.pressed == "CSUP", theme, ui.btns)
    widgets.drawButton(mon, w - 4, 6, 3, 1, "v", "CSDN", ui.pressed == "CSDN", theme, ui.btns)

    local invs = _G.NETWORK_INVENTORIES or {}
    local y = 7
    for i = ui.conf_scroll + 1, math.min(#invs, ui.conf_scroll + (h - 9)) do
        local name = invs[i]
        local isScanner = (_G.GRID_NAME == name)
        local gid = "SET_GRID:" .. name
        local sid = "SET_STORAGE:" .. name
        
        widgets.drawText(mon, mainX + 2, y, shortName(name, 16), theme.textBase, theme.surface)
        widgets.drawButton(mon, w - 15, y, 6, 1, "SCAN", gid, isScanner or ui.pressed == gid, theme, ui.btns)
        widgets.drawButton(mon, w - 7, y, 5, 1, "STOR", sid, (not isScanner) or ui.pressed == sid, theme, ui.btns)
        y = y + 1
    end
end

local function drawSelectWorkerModal(mon, mx, my, mw, mh)
    local modeText = (ui.modal.mode == "IN") and "INPUT" or "OUTPUT"
    widgets.drawText(mon, mx + 2, my + 2, "LINK WORKER (" .. modeText .. ")", theme.accent, theme.surface)
    widgets.drawText(mon, mx + 2, my + 4, "Chest: " .. shortName(ui.modal.chest, 20), theme.textMuted, theme.surface)

    local ids = {}
    for id in pairs(dispatcher.workers) do table.insert(ids, id) end
    table.sort(ids)

    local y = my + 6
    for _, id in ipairs(ids) do
        local bid = string.format("SET_WORKER_BUF:%s|%s|%s", ui.modal.mode, ui.modal.chest, id)
        widgets.drawButton(mon, mx + 2, y, 16, 1, "Worker #" .. id, bid, ui.pressed == bid, theme, ui.btns)
        y = y + 1
        if y > my + mh - 3 then break end
    end
    widgets.drawButton(mon, mx + mw - 12, my + mh - 2, 10, 1, "CANCEL", "MODAL_CANCEL", ui.pressed == "MODAL_CANCEL", theme, ui.btns)
end

local function drawModal(mon, w, h)
    if not ui.modal then return end
    local mw, mh = 40, 15
    local mx, my = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
    widgets.drawBox(mon, mx, my, mw, mh, theme.surface, theme.accent)
    
    if ui.modal.type == "CRAFT" then
        widgets.drawText(mon, mx + 2, my + 2, "CRAFT: " .. shortName(ui.modal.name, 20), theme.accent, theme.surface)
        widgets.drawText(mon, mx + 2, my + 4, "QTY: " .. ui.modal.count, theme.textBase, theme.surface)
        widgets.drawButton(mon, mx + 2, my + 6, 5, 3, "-1", "DEC:1", ui.pressed == "DEC:1", theme, ui.btns)
        widgets.drawButton(mon, mx + 8, my + 6, 5, 3, "+1", "INC:1", ui.pressed == "INC:1", theme, ui.btns)
        widgets.drawButton(mon, mx + 14, my + 6, 6, 3, "+64", "INC:64", ui.pressed == "INC:64", theme, ui.btns)
        widgets.drawButton(mon, mx + 2, my + 11, 15, 2, "START", "CRAFT_OK", ui.pressed == "CRAFT_OK", theme, ui.btns)
        widgets.drawButton(mon, mx + 20, my + 11, 15, 2, "CANCEL", "CRAFT_CANCEL", ui.pressed == "CRAFT_CANCEL", theme, ui.btns)
    elseif ui.modal.type == "RECIPE_SUCCESS" then
        widgets.drawText(mon, mx + 2, my + 2, "RECIPE CAPTURED", theme.ok, theme.surface)
        widgets.drawText(mon, mx + 2, my + 4, "Item: " .. ui.modal.data.output.name, theme.textBase, theme.surface)
        widgets.drawButton(mon, mx + 2, my + 10, 15, 2, "SAVE", "SAVE_OK", ui.pressed == "SAVE_OK", theme, ui.btns)
        widgets.drawButton(mon, mx + 20, my + 10, 15, 2, "CANCEL", "SAVE_CANCEL", ui.pressed == "SAVE_CANCEL", theme, ui.btns)
    elseif ui.modal.type == "RECIPE_FAILED" then
        widgets.drawText(mon, mx + 2, my + 2, "ERROR", theme.bad, theme.surface)
        widgets.drawText(mon, mx + 2, my + 5, tostring(ui.modal.error), theme.textBase, theme.surface)
        widgets.drawButton(mon, mx + 10, my + 10, 20, 2, "CLOSE", "ERR_CLOSE", ui.pressed == "ERR_CLOSE", theme, ui.btns)
    elseif ui.modal.type == "SELECT_WORKER" then
        drawSelectWorkerModal(mon, mx, my, mw, mh)
    end
end

function ui.draw(monName)
    local mon = peripheral.wrap(monName)
    if not mon then return end
    ui.btns = {}
    local w, h = mon.getSize()
    widgets.drawBox(mon, 1, 1, w, h, theme.bg)
    drawSidebar(mon, w, h)
    drawHeader(mon, w, h)
    if ui.modal then drawModal(mon, w, h)
    else
        if ui.tab == "DASH" then drawDash(mon, w, h)
        elseif ui.tab == "STORAGE" then drawStorage(mon, w, h)
        elseif ui.tab == "RECIPE" then drawRecipes(mon, w, h)
        elseif ui.tab == "CONF" then drawSettings(mon, w, h)
        end
    end
end

function ui.touch(x, y)
    for i = #ui.btns, 1, -1 do
        local b = ui.btns[i]
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            return b.id
        end
    end
    return nil
end

return ui
