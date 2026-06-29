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

local function clean_name(name)
    if not name then return "" end
    return name:match(":(.+)") or name
end

local function draw_grid_preview(mon, x, y)
    -- Wrap grid chest to show real items in 3x3
    local list = {}
    local out_item = nil
    if _G.GRID_NAME then
        local p = peripheral.wrap(_G.GRID_NAME)
        if p then
            list = p.list() or {}
            local od = p.getItemDetail(16)
            if od then out_item = od.name end
        end
    end

    local slot_map = {
        {4, 0, 0}, {5, 4, 0}, {6, 8, 0},
        {13, 0, 2}, {14, 4, 2}, {15, 8, 2},
        {22, 0, 4}, {23, 4, 4}, {24, 8, 4}
    }

    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    
    for _, info in ipairs(slot_map) do
        local slot, dx, dy = info[1], info[2], info[3]
        local item = list[slot]
        mon.setCursorPos(x + dx, y + dy)
        if item then
            local short = clean_name(item.name):sub(1, 2):upper()
            mon.write("[" .. short .. "]")
        else
            mon.write("[  ]")
        end
    end
    
    -- Draw arrow and output
    mon.setCursorPos(x + 13, y + 2)
    mon.write("=>")
    mon.setCursorPos(x + 16, y + 2)
    if out_item then
        local short = clean_name(out_item):sub(1, 3):upper()
        mon.write("[" .. short .. "]")
    else
        mon.write("[ ? ]")
    end
end

local function draw_header(mon, w, h)
    rect(mon, 1, 1, w, 3, colors.gray)
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 2)
    mon.write("CC-AUTOCRAFT 2.0")
    
    local tabs = {
        {id="DASH", text="ГЛАВНАЯ"},
        {id="STORAGE", text="СКЛАД"},
        {id="RECIPE", text="РЕЦЕПТЫ"},
        {id="CONF", text="НАСТРОЙКИ"}
    }
    local tw = 12
    for i, t in ipairs(tabs) do
        draw_btn(mon, w - (5-i)*tw - (5-i)*2, 2, tw, t.text, t.id, ui.tab == t.id)
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
        -- Left Panel: Workers
        rect(mon, 2, 5, 22, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(3, 6)
        mon.write("ЧЕРЕПАХИ (ВОРКЕРЫ)")
        
        local y = 8
        for id, info in pairs(dispatcher.workers) do
            mon.setCursorPos(3, y)
            if info.status == "IDLE" then
                mon.setTextColor(colors.green)
                mon.write(string.format("#%d [СВОБОДЕН]", id))
            elseif info.status == "CRAFTING" then
                mon.setTextColor(colors.orange)
                mon.write(string.format("#%d [КРАФТИТ]", id))
            elseif info.status == "TESTING" then
                mon.setTextColor(colors.yellow)
                mon.write(string.format("#%d [ТЕСТ]", id))
            else
                mon.setTextColor(colors.red)
                mon.write(string.format("#%d [%s]", id, info.status))
            end
            y = y + 1
            if y > h-2 then break end
        end

        -- Right Panel: Crafting Queue
        rect(mon, 26, 5, w-27, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(27, 6)
        mon.write("ОЧЕРЕДЬ ЗАДАЧ")
        
        local y = 8
        for i = #dispatcher.queue, 1, -1 do
            local t = dispatcher.queue[i]
            mon.setCursorPos(27, y)
            if t.status == "COMPLETED" then
                mon.setTextColor(colors.gray)
                mon.write(string.format("[+] %-16s x%d (ОК)", clean_name(t.name), t.count))
            elseif t.status == "FAILED" then
                mon.setTextColor(colors.red)
                mon.write(string.format("[!] %-16s x%d (ОШИБКА)", clean_name(t.name), t.count))
            elseif t.status == "ACTIVE" then
                mon.setTextColor(colors.blue)
                mon.write(string.format("[>] %-16s x%d (АКТИВЕН)", clean_name(t.name), t.count))
            else
                mon.setTextColor(colors.black)
                mon.write(string.format("[-] %-16s x%d (ОЖИДАНИЕ)", clean_name(t.name), t.count))
            end
            y = y + 1
            if y > h-2 then break end
        end

    elseif ui.tab == "STORAGE" then
        -- Storage display with full lists and scrolling
        rect(mon, 2, 5, w-11, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(3, 6)
        mon.write("ДОСТУПНЫЕ ПРЕДМЕТЫ НА СКЛАДЕ")

        -- Get and sort items
        local items = {}
        for name, qty in pairs(storage.cache) do
            table.insert(items, {name = name, qty = qty})
        end
        table.sort(items, function(a, b) return a.name < b.name end)

        -- Scroll buttons on the far right
        draw_btn(mon, w - 8, 5, 7, "/\\ UP", "SCROLL_UP", false)
        draw_btn(mon, w - 8, h - 3, 7, "\\/ DN", "SCROLL_DOWN", false)

        local max_display = h - 9
        local y = 8
        for i = ui.scroll + 1, math.min(#items, ui.scroll + max_display) do
            local item = items[i]
            mon.setCursorPos(4, y)
            mon.setTextColor(colors.blue)
            mon.write("[Заказ]")
            
            -- Make the "[Заказ]" button tapable
            table.insert(ui.btns, {x1=3, y1=y, x2=10, y2=y, id="CRAFT_INIT:" .. item.name})

            mon.setTextColor(colors.black)
            mon.setCursorPos(12, y)
            mon.write(string.format("%-22s  x%d", clean_name(item.name), item.qty))
            y = y + 1
        end

        if #items == 0 then
            mon.setCursorPos(4, 9)
            mon.setTextColor(colors.red)
            mon.write("Склад пуст! Подключите сундуки к сети.")
        end

    elseif ui.tab == "RECIPE" then
        -- Left Panel: Recipe Grid Info
        rect(mon, 2, 5, 23, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(3, 6)
        mon.write("СЕТКА КРАФТА 3х3")
        
        draw_grid_preview(mon, 4, 8)
        
        draw_btn(mon, 3, 16, 21, "ТЕСТ И ЗАПИСЬ", "TEST_CRAFT_INIT", false)
        
        -- Right Panel: Known Recipes
        rect(mon, 27, 5, w-28, h-6, colors.white, colors.gray)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        mon.setCursorPos(28, 6)
        mon.write("БАЗА ИЗВЕСТНЫХ РЕЦЕПТОВ")
        
        local y = 8
        for name, data in pairs(recipes.data) do
            mon.setCursorPos(28, y)
            mon.setTextColor(colors.black)
            mon.write(string.format("> %-20s x%d", clean_name(name), data.output_count or 1))
            y = y + 1
            if y > h-2 then break end
        end

    elseif ui.tab == "CONF" then
        mon.setTextColor(colors.black)
        mon.setCursorPos(2, 5)
        mon.write("ВЫБЕРИТЕ СУНДУК-СКАНЕР ДЛЯ РЕЦЕПТОВ:")
        local y = 7
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
                -- Skip worker buffers in select scanner list
                if not storage.buffers[name] then
                    local active = (_G.GRID_NAME == name)
                    mon.setBackgroundColor(active and colors.blue or colors.white)
                    mon.setTextColor(active and colors.white or colors.black)
                    mon.setCursorPos(3, y)
                    mon.write(string.format(" %-24s ", name))
                    table.insert(ui.btns, {x1=3, y1=y, x2=w-2, y2=y, id="SET_GRID:"..name})
                    y = y + 2
                    if y > h-2 then break end
                end
            end
        end
    end
end

function ui.draw_modal(mon, w, h)
    local mw, mh = 42, 14
    local mx, my = math.floor((w-mw)/2), math.floor((h-mh)/2)
    
    if ui.modal.type == "CRAFT" then
        rect(mon, mx, my, mw, mh, colors.white, colors.blue)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        
        mon.setCursorPos(mx+2, my+2)
        mon.write("ЗАКАЗАТЬ АВТОКРАФТ")
        
        mon.setCursorPos(mx+2, my+4)
        mon.write("Предмет: " .. clean_name(ui.modal.name))
        
        -- Adjusting Count Controls
        mon.setCursorPos(mx+2, my+6)
        mon.write("Количество: ")
        mon.setTextColor(colors.blue)
        mon.write(tostring(ui.modal.count))
        
        draw_btn(mon, mx+2, my+8, 5, "-1", "DEC:1", false)
        draw_btn(mon, mx+8, my+8, 5, "-10", "DEC:10", false)
        draw_btn(mon, mx+14, my+8, 5, "-64", "DEC:64", false)
        
        draw_btn(mon, mx+mw-19, my+8, 5, "+1", "INC:1", false)
        draw_btn(mon, mx+mw-13, my+8, 5, "+10", "INC:10", false)
        draw_btn(mon, mx+mw-7, my+8, 5, "+64", "INC:64", false)
        
        if ui.modal.error then
            mon.setCursorPos(mx+2, my+10)
            mon.setTextColor(colors.red)
            mon.write(ui.modal.error:sub(1, mw-4))
        end
        
        draw_btn(mon, mx+2, my+12, 16, "ЗАПУСТИТЬ КРАФТ", "CRAFT_START_OK", false)
        draw_btn(mon, mx+mw-14, my+12, 12, "ОТМЕНА", "CRAFT_CANCEL", false)
        
    elseif ui.modal.type == "RECIPE_SUCCESS" then
        rect(mon, mx, my, mw, mh, colors.white, colors.green)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        
        mon.setCursorPos(mx+2, my+2)
        mon.setTextColor(colors.green)
        mon.write("ТЕСТ КРАФТА УСПЕШЕН!")
        
        mon.setTextColor(colors.black)
        mon.setCursorPos(mx+2, my+4)
        mon.write("Получено: " .. clean_name(ui.modal.data.output.name) .. " x" .. ui.modal.data.output.count)
        
        mon.setCursorPos(mx+2, my+6)
        mon.write("Ингредиенты распознаны.")
        mon.setCursorPos(mx+2, my+7)
        mon.write("Записать рецепт в память?")
        
        draw_btn(mon, mx+2, my+10, 16, "СОХРАНИТЬ РЕЦЕПТ", "SAVE_RECIPE_OK", false)
        draw_btn(mon, mx+mw-14, my+10, 12, "ОТМЕНИТЬ", "SAVE_RECIPE_CANCEL", false)
        
    elseif ui.modal.type == "RECIPE_FAILED" then
        rect(mon, mx, my, mw, mh, colors.white, colors.red)
        mon.setTextColor(colors.black)
        mon.setBackgroundColor(colors.white)
        
        mon.setCursorPos(mx+2, my+2)
        mon.setTextColor(colors.red)
        mon.write("ОШИБКА ТЕСТА КРАФТА!")
        
        mon.setTextColor(colors.black)
        mon.setCursorPos(mx+2, my+5)
        mon.write("Причина: " .. tostring(ui.modal.error))
        
        draw_btn(mon, mx+math.floor((mw-10)/2), my+10, 10, "ЗАКРЫТЬ", "REC_ERR_CLOSE", false)
    end
end

function ui.touch(x, y)
    for _, b in ipairs(ui.btns) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.id end
    end
end

return ui
