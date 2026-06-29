-- Monitor UI for cc-autocraft
-- Clean, tabbed interface: Dashboard / Storage / Recipes / Settings.
-- NOTE: ComputerCraft's font is ASCII-only; all on-screen text is English.
local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")
local util = require("lib.util")

local ui = {
    tab = "DASH",
    modal = nil,
    btns = {},
    scroll = 0,
    recipe_scroll = 0,
    conf_scroll = 0
}

-- Theme
local C = {
    bg       = colors.black,
    header   = colors.purple,     -- Sleek royal purple header
    tab_on   = colors.magenta,    -- Bright magenta active tab
    tab_off  = colors.gray,       -- Darker gray for inactive tabs
    panel    = colors.black,
    border   = colors.purple,     -- Purple accented borders
    title    = colors.cyan,       -- Cyan titles for high visibility
    text     = colors.white,
    muted    = colors.lightGray,
    ok       = colors.lime,       -- Lime for success / positive states
    warn     = colors.orange,     -- Orange for warning / progress states
    bad      = colors.red,        -- Red for errors
    active   = colors.cyan,
    accent   = colors.magenta
}

----------------------------------------------------------------------
-- Drawing primitives
----------------------------------------------------------------------
local function fill(mon, x, y, w, h, bg)
    if not bg then return end
    mon.setBackgroundColor(bg)
    for i = 0, h - 1 do
        mon.setCursorPos(x, y + i)
        mon.write(string.rep(" ", w))
    end
end

local function box(mon, x, y, w, h, bg, border)
    fill(mon, x, y, w, h, bg)
    if border then
        mon.setBackgroundColor(border)
        mon.setCursorPos(x, y);             mon.write(string.rep(" ", w))
        mon.setCursorPos(x, y + h - 1);     mon.write(string.rep(" ", w))
        for i = 0, h - 1 do
            mon.setCursorPos(x, y + i);         mon.write(" ")
            mon.setCursorPos(x + w - 1, y + i); mon.write(" ")
        end
    end
end

local function textAt(mon, x, y, s, fg, bg)
    mon.setTextColor(fg or C.text)
    mon.setBackgroundColor(bg or C.bg)
    mon.setCursorPos(x, y)
    mon.write(s)
end

-- Draw a clickable button and register its hit rect.
local function btn(mon, x, y, w, label, id, bg, fg)
    bg = bg or C.tab_on
    fg = fg or colors.white
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    mon.setCursorPos(x, y)
    local s = label
    if #s < w then
        local pad = math.floor((w - #s) / 2)
        s = string.rep(" ", pad) .. s .. string.rep(" ", w - #s - pad)
    elseif #s > w then
        s = s:sub(1, w)
    end
    mon.write(s)
    table.insert(ui.btns, { x1 = x, y1 = y, x2 = x + w - 1, y2 = y, id = id })
end

local function cleanName(name)
    if not name then return "" end
    return name:match(":(.+)") or name
end

local function shortName(name, n)
    return cleanName(name):sub(1, n or 16)
end

-- Group ingredients by name, summing counts. Returns sorted list.
local function groupIngredients(ingredients)
    local grouped = {}
    for _, ing in ipairs(ingredients) do
        grouped[ing.name] = (grouped[ing.name] or 0) + (ing.count or 1)
    end
    local list = {}
    for name, count in pairs(grouped) do
        table.insert(list, { name = name, count = count })
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Detect inventory role for a peripheral name.
local function roleOf(name)
    if name == _G.GRID_NAME then return "SCANNER" end
    for _, w in pairs(dispatcher.workers) do
        if w.buffers then
            if w.buffers.input == name then return "BUF-IN" end
            if w.buffers.output == name then return "BUF-OUT" end
        end
    end
    return "STORAGE"
end

----------------------------------------------------------------------
-- Header + status bar
----------------------------------------------------------------------
local function drawHeader(mon, w)
    fill(mon, 1, 1, w, 3, C.header)
    textAt(mon, 2, 2, "CC-AUTOCRAFT 3.0", colors.white, C.header)

    local tabs = {
        { id = "DASH",    text = "HOME" },
        { id = "STORAGE", text = "STORAGE" },
        { id = "RECIPE",  text = "RECIPES" },
        { id = "CONF",    text = "SETTINGS" }
    }
    local tw = 11
    local gap = 1
    local totalW = #tabs * tw + (#tabs - 1) * gap
    local startX = w - totalW - 1
    for i, t in ipairs(tabs) do
        local x = startX + (i - 1) * (tw + gap)
        local isActive = (ui.tab == t.id)
        btn(mon, x, 2, tw, t.text, "TAB:" .. t.id,
            isActive and C.tab_on or C.tab_off,
            isActive and colors.white or colors.lightGray)
    end
end

local function drawStatus(mon, w)
    fill(mon, 1, 4, w, 1, colors.black)
    local itemCount = 0
    for _ in pairs(storage.cache) do itemCount = itemCount + 1 end
    local workerCount = 0
    for _ in pairs(dispatcher.workers) do workerCount = workerCount + 1 end
    local pending = 0
    for _, t in ipairs(dispatcher.queue) do
        if t.status == "PENDING" or t.status == "ACTIVE" then pending = pending + 1 end
    end

    local scanner = _G.GRID_NAME and cleanName(_G.GRID_NAME) or "NONE"
    local s = string.format(" Scanner: %-14s  Items: %d  Workers: %d  Queue: %d",
        scanner:sub(1, 14), itemCount, workerCount, pending)
    textAt(mon, 1, 4, s, C.muted, colors.black)
end

----------------------------------------------------------------------
-- Tab: Dashboard
----------------------------------------------------------------------
local function drawDash(mon, w, h)
    local leftW = math.max(20, math.floor(w * 0.42))
    local leftX = 2
    local rightX = leftX + leftW + 1

    -- Workers panel
    box(mon, leftX, 5, leftW, h - 5, C.panel, C.border)
    textAt(mon, leftX + 1, 6, "WORKERS (TURTLES)", C.title, C.panel)

    local y = 8
    local anyWorker = false
    for id, info in pairs(dispatcher.workers) do
        anyWorker = true
        local badgeText, badgeColor
        if info.status == "IDLE" then
            badgeText, badgeColor = " IDLE ", C.ok
        elseif info.status == "CRAFTING" then
            badgeText, badgeColor = " CRAFT ", C.active
        elseif info.status == "TESTING" then
            badgeText, badgeColor = " TEST  ", C.warn
        else
            badgeText, badgeColor = " ERR   ", C.bad
        end
        textAt(mon, leftX + 1, y, string.format("#%-3d:", id), C.text, C.panel)
        textAt(mon, leftX + 10, y, badgeText, colors.black, badgeColor)
        y = y + 1
        if y > h - 2 then break end
    end
    if not anyWorker then
        textAt(mon, leftX + 1, 8, "No workers.", C.muted, C.panel)
        textAt(mon, leftX + 1, 9, "Run worker.lua", C.muted, C.panel)
        textAt(mon, leftX + 1, 10, "on turtles.", C.muted, C.panel)
    end

    -- Queue panel
    if rightX < w then
        local rw = w - rightX
        box(mon, rightX, 5, rw, h - 5, C.panel, C.border)
        textAt(mon, rightX + 1, 6, "TASK QUEUE", C.title, C.panel)
        btn(mon, w - 11, 6, 10, "CLEAR", "CLR_QUEUE", C.bad, colors.white)

        y = 8
        for i = #dispatcher.queue, 1, -1 do
            local t = dispatcher.queue[i]
            local badgeText, bgCol, fgCol
            if t.status == "COMPLETED" then
                badgeText, bgCol, fgCol = " DONE ", colors.gray, colors.white
            elseif t.status == "FAILED" then
                badgeText, bgCol, fgCol = " FAIL ", colors.red, colors.white
            elseif t.status == "ACTIVE" then
                badgeText, bgCol, fgCol = " WORK ", colors.cyan, colors.black
            else
                badgeText, bgCol, fgCol = " WAIT ", colors.lightGray, colors.black
            end
            
            -- Print task info
            local nameStr = string.format("%-11s x%d", shortName(t.name, 11), t.count)
            textAt(mon, rightX + 1, y, nameStr, C.text, C.panel)
            -- Print badge at the right side of the row
            textAt(mon, w - 8, y, badgeText, fgCol, bgCol)
            y = y + 1
            if y > h - 2 then break end
        end
        if #dispatcher.queue == 0 then
            textAt(mon, rightX + 1, 8, "Queue empty.", C.muted, C.panel)
        end
    end
end

----------------------------------------------------------------------
-- Tab: Storage
----------------------------------------------------------------------
local function drawStorage(mon, w, h)
    box(mon, 2, 5, w - 9, h - 5, C.panel, C.border)
    textAt(mon, 3, 6, "STORAGE CONTENTS", C.title, C.panel)

    btn(mon, w - 7, 6, 6, "/\\ UP", "SUP", C.tab_off, colors.black)
    btn(mon, w - 7, h - 2, 6, "\\/ DN", "SDN", C.tab_off, colors.black)

    local items = {}
    for name, qty in pairs(storage.cache) do
        table.insert(items, { name = name, qty = qty })
    end
    table.sort(items, function(a, b) return a.name < b.name end)

    local maxRows = h - 9
    local y = 8
    for i = ui.scroll + 1, math.min(#items, ui.scroll + maxRows) do
        local item = items[i]
        local hasRecipe = recipes.has(item.name)
        btn(mon, 4, y, 8, "ORDER", "CRAFT_INIT:" .. item.name,
            hasRecipe and C.tab_on or C.tab_off, colors.white)
        textAt(mon, 14, y, string.format("%-26s x%d", shortName(item.name, 26), item.qty),
            hasRecipe and C.ok or C.text, C.panel)
        y = y + 1
    end

    if #items == 0 then
        textAt(mon, 4, 9, "Storage empty.", C.bad, C.panel)
        textAt(mon, 4, 10, "Connect chests to wired network.", C.muted, C.panel)
        if _G.GRID_NAME then
            textAt(mon, 4, 12, "Scanner chest: " .. cleanName(_G.GRID_NAME), C.warn, C.panel)
            textAt(mon, 4, 13, "(excluded from storage - normal)", C.muted, C.panel)
        end
    end
end

----------------------------------------------------------------------
-- Tab: Recipes
----------------------------------------------------------------------
local function drawSlot(mon, x, y, item)
    if item then
        local name = shortName(item.name, 3):upper()
        if #name == 1 then name = " " .. name .. " "
        elseif #name == 2 then name = " " .. name
        end
        textAt(mon, x, y, name, colors.white, colors.gray)
    else
        textAt(mon, x, y, "   ", colors.lightGray, colors.gray)
    end
end

local function drawOutputSlot(mon, x, y, itemName)
    if itemName then
        local name = shortName(itemName, 3):upper()
        if #name == 1 then name = " " .. name .. " "
        elseif #name == 2 then name = " " .. name
        end
        textAt(mon, x, y, name, colors.black, colors.orange)
    else
        textAt(mon, x, y, " ? ", colors.gray, colors.lightGray)
    end
end

local function drawGridPreview(mon, x, y)
    local list = _G.GRID_ITEMS or {}
    local outItem = _G.GRID_OUTPUT

    -- positions of the 3x3 grid relative to (x,y)
    local cells = {
        { 4,  0, 0 }, { 5,  4, 0 }, { 6,  8, 0 },
        { 13, 0, 2 }, { 14, 4, 2 }, { 15, 8, 2 },
        { 22, 0, 4 }, { 23, 4, 4 }, { 24, 8, 4 }
    }

    for _, c in ipairs(cells) do
        local slot, dx, dy = c[1], c[2], c[3]
        local item = list[slot]
        drawSlot(mon, x + dx, y + dy, item)
    end

    textAt(mon, x + 12, y + 2, "->", C.accent, C.panel)
    drawOutputSlot(mon, x + 15, y + 2, outItem)
end

local function drawRecipe(mon, w, h)
    local leftW = 28
    local rightX = leftW + 3

    -- Left: live grid + test button
    box(mon, 2, 5, leftW, h - 5, C.panel, C.border)
    textAt(mon, 3, 6, "CRAFT GRID 3x3", C.title, C.panel)

    if not _G.GRID_NAME then
        textAt(mon, 3, 8, "No scanner chest selected.", C.bad, C.panel)
        textAt(mon, 3, 9, "Open SETTINGS tab.", C.muted, C.panel)
        return
    end

    textAt(mon, 3, 8, "Scanner: " .. shortName(_G.GRID_NAME, 20), C.muted, C.panel)
    drawGridPreview(mon, 4, 10)
    textAt(mon, 4, 16, "Place craft in center", C.muted, C.panel)
    textAt(mon, 4, 17, "slots 4-6 / 13-15 / 22-24", C.muted, C.panel)

    local testLabel = _G.active_test and "TESTING..." or "TEST CRAFT"
    btn(mon, 3, 19, leftW - 2, testLabel, "TEST_CRAFT",
        _G.active_test and C.muted or C.tab_on, colors.white)

    -- Right: saved recipes
    if rightX < w then
        local rw = w - rightX - 1
        box(mon, rightX, 5, rw, h - 5, C.panel, C.border)
        textAt(mon, rightX + 1, 6, "KNOWN RECIPES", C.title, C.panel)
        btn(mon, w - 7, 6, 6, "/\\ UP", "RSUP", C.tab_off, colors.black)
        btn(mon, w - 7, h - 2, 6, "\\/ DN", "RSDN", C.tab_off, colors.black)

        local recs = recipes.list()
        local maxRows = h - 9
        local y = 8
        for i = ui.recipe_scroll + 1, math.min(#recs, ui.recipe_scroll + maxRows) do
            local r = recs[i]
            btn(mon, rightX + 1, y, 7, "CRAFT", "REC_CRAFT:" .. r.name, C.tab_on, colors.white)
            textAt(mon, rightX + 9, y, string.format("%-16s x%d", shortName(r.name, 16), r.output_count),
                C.text, C.panel)
            btn(mon, w - 4, y, 3, " X", "REC_DEL:" .. r.name, C.bad, colors.white)
            y = y + 1
        end

        if #recs == 0 then
            textAt(mon, rightX + 1, 8, "No recipes.", C.bad, C.panel)
            textAt(mon, rightX + 1, 9, "Run TEST CRAFT", C.muted, C.panel)
            textAt(mon, rightX + 1, 10, "and save the result.", C.muted, C.panel)
        end
    end
end

----------------------------------------------------------------------
-- Tab: Settings
----------------------------------------------------------------------
local function drawConf(mon, w, h)
    box(mon, 2, 5, w - 9, h - 5, C.panel, C.border)
    textAt(mon, 3, 6, "SCANNER CHEST SELECT", C.title, C.panel)
    textAt(mon, 3, 7, "(used to record recipes; excluded from storage)", C.muted, C.panel)

    btn(mon, w - 7, 6, 6, "/\\ UP", "CSUP", C.tab_off, colors.black)
    btn(mon, w - 7, h - 2, 6, "\\/ DN", "CSDN", C.tab_off, colors.black)

    local invs = _G.NETWORK_INVENTORIES or {}
    table.sort(invs)

    local maxRows = math.floor((h - 10) / 1)
    local y = 9
    for i = ui.conf_scroll + 1, math.min(#invs, ui.conf_scroll + maxRows) do
        local name = invs[i]
        local role = roleOf(name)
        local isScanner = (name == _G.GRID_NAME)

        local label = "SELECT"
        local bg = isScanner and C.ok or C.tab_off
        if role ~= "STORAGE" and not isScanner then
            label = role
            bg = C.muted
        end
        btn(mon, 4, y, 12, isScanner and "[ SCANNER ]" or label,
            "SET_GRID:" .. name, bg,
            isScanner and colors.black or colors.white)

        textAt(mon, 18, y, string.format("%-26s", shortName(name, 26)), C.text, C.panel)
        textAt(mon, 46, y, "[" .. role .. "]", isScanner and C.ok or C.muted, C.panel)
        y = y + 1
        if y > h - 3 then break end
    end

    if #invs == 0 then
        textAt(mon, 4, 10, "No inventories found!", C.bad, C.panel)
        textAt(mon, 4, 11, "Connect chests to Core's wired network.", C.muted, C.panel)
    end
end

----------------------------------------------------------------------
-- Modals
----------------------------------------------------------------------
local function drawCraftModal(mon, w, h)
    local mw, mh = math.min(52, w - 4), math.min(20, h - 4)
    local mx, my = math.floor((w - mw) / 2), math.floor((h - mh) / 2)

    local options = recipes.get(ui.modal.name)
    local recipe = options and options[1]
    local outCount = recipe and recipe.output_count or 1
    local batches = math.ceil(ui.modal.count / outCount)
    local totalOutput = batches * outCount

    box(mon, mx, my, mw, mh, C.bg, C.tab_on)
    textAt(mon, mx + 2, my + 1, "AUTOCRAFT ORDER", C.title, C.bg)
    textAt(mon, mx + 2, my + 3, "Item: " .. shortName(ui.modal.name, mw - 7), C.text, C.bg)
    textAt(mon, mx + 2, my + 4,
        string.format("Recipe out: x%d  ->  will craft: x%d", outCount, totalOutput),
        C.muted, C.bg)

    textAt(mon, mx + 2, my + 6, "Amount: ", C.text, C.bg)
    textAt(mon, mx + 11, my + 6, tostring(ui.modal.count), C.title, C.bg)

    btn(mon, mx + 2,  my + 8, 5, "-1",  "DEC:1",  C.tab_off, colors.white)
    btn(mon, mx + 8,  my + 8, 5, "-10", "DEC:10", C.tab_off, colors.white)
    btn(mon, mx + 14, my + 8, 5, "-64", "DEC:64", C.tab_off, colors.white)
    btn(mon, mx + mw - 19, my + 8, 5, "+1",  "INC:1",  C.tab_off, colors.white)
    btn(mon, mx + mw - 13, my + 8, 5, "+10", "INC:10", C.tab_off, colors.white)
    btn(mon, mx + mw - 7,  my + 8, 5, "+64", "INC:64", C.tab_off, colors.white)

    textAt(mon, mx + 2, my + 10, "Ingredients (have / need):", C.muted, C.bg)

    -- Feasibility summary line (can the whole craft, incl. sub-recipes, be done?)
    if ui.modal.feasible_ok ~= nil then
        local fmsg = ui.modal.feasible_ok and "Craftable: YES" or ("Cannot: " .. tostring(ui.modal.feasible_msg))
        textAt(mon, mx + 2, my + mh - 5, fmsg:sub(1, mw - 4),
            ui.modal.feasible_ok and C.ok or C.warn, C.bg)
    end

    if recipe then
        local grouped = groupIngredients(recipe.ingredients)
        local iy = my + 11
        for _, ing in ipairs(grouped) do
            local needed = ing.count * batches
            local avail = storage.getAvailable(ing.name)
            local color = (avail >= needed) and C.ok or C.bad
            textAt(mon, mx + 2, iy,
                string.format("- %-20s : %d / %d", shortName(ing.name, 20), avail, needed),
                color, C.bg)
            iy = iy + 1
            if iy > my + mh - 6 then break end
        end
    else
        textAt(mon, mx + 2, my + 11, "Recipe not found! Save it via TEST CRAFT.", C.bad, C.bg)
    end

    if ui.modal.error then
        textAt(mon, mx + 2, my + mh - 3, ui.modal.error:sub(1, mw - 4), C.bad, C.bg)
    end

    btn(mon, mx + 2, my + mh - 2, 18, "START CRAFT", "CRAFT_OK", C.ok, colors.white)
    btn(mon, mx + mw - 14, my + mh - 2, 12, "CANCEL", "CRAFT_CANCEL", C.tab_off, colors.white)
end

local function drawRecipeSuccessModal(mon, w, h)
    local mw, mh = 48, 14
    local mx, my = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
    box(mon, mx, my, mw, mh, C.bg, C.ok)

    textAt(mon, mx + 2, my + 2, "TEST CRAFT SUCCESS!", C.ok, C.bg)
    textAt(mon, mx + 2, my + 4,
        "Got: " .. shortName(ui.modal.data.output.name, 24) .. " x" .. ui.modal.data.output.count,
        C.text, C.bg)
    textAt(mon, mx + 2, my + 6, "Ingredients recognized.", C.muted, C.bg)
    textAt(mon, mx + 2, my + 7, "Result in scanner slot 16.", C.muted, C.bg)
    textAt(mon, mx + 2, my + 9, "Save recipe to database?", C.text, C.bg)

    btn(mon, mx + 2, my + mh - 2, 18, "SAVE", "SAVE_OK", C.ok, colors.white)
    btn(mon, mx + mw - 14, my + mh - 2, 12, "CANCEL", "SAVE_CANCEL", C.tab_off, colors.white)
end

local function drawRecipeFailModal(mon, w, h)
    local mw, mh = 48, 12
    local mx, my = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
    box(mon, mx, my, mw, mh, C.bg, C.bad)

    textAt(mon, mx + 2, my + 2, "TEST CRAFT ERROR", C.bad, C.bg)
    textAt(mon, mx + 2, my + 5, "Reason: " .. tostring(ui.modal.error):sub(1, mw - 9), C.text, C.bg)
    btn(mon, mx + math.floor((mw - 12) / 2), my + mh - 2, 12, "CLOSE", "ERR_CLOSE", C.bad, colors.white)
end

local function drawModal(mon, w, h)
    if not ui.modal then return end
    if ui.modal.type == "CRAFT" then
        drawCraftModal(mon, w, h)
    elseif ui.modal.type == "RECIPE_SUCCESS" then
        drawRecipeSuccessModal(mon, w, h)
    elseif ui.modal.type == "RECIPE_FAILED" then
        drawRecipeFailModal(mon, w, h)
    end
end

----------------------------------------------------------------------
-- Main draw
----------------------------------------------------------------------
function ui.draw(monName)
    local mon = peripheral.wrap(monName)
    if not mon then return end
    ui.btns = {}
    mon.setTextScale(0.5)
    local w, h = mon.getSize()

    fill(mon, 1, 1, w, h, C.bg)
    drawHeader(mon, w)
    drawStatus(mon, w)

    if ui.modal then
        drawModal(mon, w, h)
        return
    end

    if ui.tab == "DASH" then
        drawDash(mon, w, h)
    elseif ui.tab == "STORAGE" then
        drawStorage(mon, w, h)
    elseif ui.tab == "RECIPE" then
        drawRecipe(mon, w, h)
    elseif ui.tab == "CONF" then
        drawConf(mon, w, h)
    end
end

-- Reverse-order hit test so modal buttons (drawn last) win over background.
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
