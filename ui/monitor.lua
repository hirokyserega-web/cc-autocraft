local dispatcher = require("core.dispatcher")
local storage = require("core.storage")
local recipes = require("core.recipes")

local ui = {
    tab = "DASH",
    modal = nil,
    btns = {},
    scroll = 0,
    recipe_scroll = 0
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

local function draw_small_btn(mon, x, y, w, text, id, bg, fg)
    mon.setBackgroundColor(bg or colors.blue)
    mon.setTextColor(fg or colors.white)
    mon.setCursorPos(x, y)
    local label = text
    if #label < w then
        local pad = math.floor((w - #label) / 2)
        label = string.rep(" ", pad) .. label .. string.rep(" ", w - #label - pad)
    end
    mon.write(label)
    table.insert(ui.btns, {x1=x, y1=y, x2=x+w-1, y2=y, id=id})
end

local function draw_btn(mon, x, y, w, text, id, active)
    local bg = active and colors.blue or colors.gray
    draw_small_btn(mon, x, y, w, text, id, bg, colors.white)
end

local function clean_name(name)
    if not name then return "" end
    return name:match(":(.+)") or name
end

local function group_ingredients(ingredients)
    local grouped = {}
    for _, ing in ipairs(ingredients) do
        grouped[ing.name] = (grouped[ing.name] or 0) + (ing.count or 1)
    end
    local list = {}
    for name, count in pairs(grouped) do
        table.insert(list, {name = name, count = count})
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
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
        draw_small_btn(mon, w - (5-i)*tw - (5-i)*2, 2, tw, t.text, t.id, ui.tab == t.id and colors.blue or colors.gray, colors.white)
    end
end

function ui.draw(monName)
    local mon = peripheral.wrap(monName)
    if not mon then return end
    ui.btns = {}
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    
    rect(mon, 1, 1, w, h, colors.black)
    draw_header(mon, w, h)

    if ui.modal then
        ui.draw_modal(mon, w, h)
        return
    end

    if ui.tab == "DASH" then
        -- Left Panel: Workers
        rect(mon, 2, 5, 23, h-6, colors.black, colors.gray)
        mon.setTextColor(colors.cyan)
        mon.setBackgroundColor(colors.black)
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
        rect(mon, 27, 5, w-28, h-6, colors.black, colors.gray)
        mon.setTextColor(colors.cyan)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(28, 6)
        mon.write("ОЧЕРЕДЬ ЗАДАЧ")
        
        -- Reset Queue button
        draw_small_btn(mon, w - 12, 6, 10, "СБРОС", "CLEAR_QUEUE", colors.red, colors.white)
        
        local y = 8
        for i = #dispatcher.queue, 1, -1 do
            local t = dispatcher.queue[i]
            mon.setCursorPos(28, y)
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
                mon.setTextColor(colors.white)
                mon.write(string.format("[-] %-16s x%d (ОЖИДАНИЕ)", clean_name(t.name), t.count))
            end
            y = y + 1
            if y > h-2 then break end
        end

    elseif ui.tab == "STORAGE" then
        -- Storage display with full lists and scrolling
        rect(mon, 2, 5, w-11, h-6, colors.black, colors.gray)
        mon.setTextColor(colors.cyan)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(3, 6)
        mon.write("ДОСТУПНЫЕ ПРЕДМЕТЫ НА СКЛАДЕ")

        -- Get and sort items
        local items = {}
        for name, qty in pairs(storage.cache) do
            table.insert(items, {name = name, qty = qty})
        end
        table.sort(items, function(a, b) return a.name < b.name end)

        -- Scroll buttons on the far right
        draw_small_btn(mon, w - 8, 5, 7, "/\\ UP", "SCROLL_UP", colors.gray, colors.white)
        draw_small_btn(mon, w - 8, h - 3, 7, "\\/ DN", "SCROLL_DOWN", colors.gray, colors.white)

        local max_display = h - 9
        local y = 8
        for i = ui.scroll + 1, math.min(#items, ui.scroll + max_display) do
            local item = items[i]
            
            -- Draw order button
            draw_small_btn(mon, 4, y, 7, "ЗАКАЗ", "CRAFT_INIT:" .. item.name, colors.blue, colors.white)

            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.white)
            mon.setCursorPos(13, y)
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
        rect(mon, 2, 5, 24, h-6, colors.black, colors.gray)
        mon.setTextColor(colors.cyan)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(3, 6)
        mon.write("СЕТКА КРАФТА 3х3")
        
        draw_grid_preview(mon, 4, 8)
        
        draw_small_btn(mon, 3, 16, 22, "ТЕСТ И ЗАПИСЬ", "TEST_CRAFT_INIT", colors.blue, colors.white)
        
        -- Right Panel: Known Recipes
        rect(mon, 28, 5, w-37, h-6, colors.black, colors.gray)
        mon.setTextColor(colors.cyan)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(29, 6)
        mon.write("БАЗА ИЗВЕСТНЫХ РЕЦЕПТОВ")
        
        -- Get sorted recipes
        local recipe_list = {}
        for name, data in pairs(recipes.data) do
            table.insert(recipe_list, {name = name, data = data})
        end
        table.sort(recipe_list, function(a, b) return a.name < b.name end)
        
        -- Scroll buttons for recipes
        draw_small_btn(mon, w - 8, 5, 7, "/\\ UP", "RECIPE_SCROLL_UP", colors.gray, colors.white)
        draw_small_btn(mon, w - 8, h - 3, 7, "\\/ DN", "RECIPE_SCROLL_DOWN", colors.gray, colors.white)
        
        local max_display = h - 9
        local y = 8
        for i = ui.recipe_scroll + 1, math.min(#recipe_list, ui.recipe_scroll + max_display) do
            local rec = recipe_list[i]
            mon.setCursorPos(29, y)
            mon.setTextColor(colors.white)
            mon.write(string.format("> %-14s x%d", clean_name(rec.name):sub(1, 14), rec.data.output_count or 1))
            
            -- Delete button [X]
            draw_small_btn(mon, w - 13, y, 3, "X", "DELETE_RECIPE:" .. rec.name, colors.red, colors.white)
            y = y + 1
        end

    elseif ui.tab == "CONF" then
        -- Settings tab
        rect(mon, 2, 5, w-11, h-6, colors.black, colors.gray)
        mon.setTextColor(colors.cyan)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(3, 6)
        mon.write("ВЫБЕРИТЕ СУНДУК-СКАНЕР ДЛЯ РЕЦЕПТОВ:")
        
        -- Get all inventories
        local inventories = {}
        local names = peripheral.getNames()
        for _, name in ipairs(names) do
            if peripheral.getType(name) == "inventory" or peripheral.hasType(name, "inventory") then
                if not storage.buffers[name] then
                    table.insert(inventories, name)
                end
            end
        end
        table.sort(inventories)
        
        -- Scroll buttons
        draw_small_btn(mon, w - 8, 5, 7, "/\\ UP", "SCROLL_UP", colors.gray, colors.white)
        draw_small_btn(mon, w - 8, h - 3, 7, "\\/ DN", "SCROLL_DOWN", colors.gray, colors.white)
        
        local max_display = math.floor((h - 9) / 2)
        local y = 8
        for i = ui.scroll + 1, math.min(#inventories, ui.scroll + max_display) do
            local name = inventories[i]
            local active = (_G.GRID_NAME == name)
            
            local btn_bg = active and colors.blue or colors.gray
            local btn_fg = colors.white
            
            draw_small_btn(mon, 4, y, 24, name, "SET_GRID:" .. name, btn_bg, btn_fg)
            
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.white)
            mon.setCursorPos(30, y)
            if active then
                mon.setTextColor(colors.green)
                mon.write("[АКТИВНЫЙ СКАНЕР]")
            else
                mon.setTextColor(colors.gray)
                mon.write("[ДОСТУПЕН]")
            end
            
            y = y + 2
        end
        
        if #inventories == 0 then
            mon.setCursorPos(4, 9)
            mon.setTextColor(colors.red)
            mon.write("Инвентари не найдены!")
        end
    end
end

function ui.draw_modal(mon, w, h)
    local mw, mh = 46, 18
    local mx, my = math.floor((w-mw)/2), math.floor((h-mh)/2)
    
    if ui.modal.type == "CRAFT" then
        local options = recipes.get(ui.modal.name)
        local recipe = options and options[1]
        local out_count = recipe and recipe.output_count or 1
        local batches = math.ceil(ui.modal.count / out_count)
        local total_output = batches * out_count
        
        rect(mon, mx, my, mw, mh, colors.black, colors.blue)
        mon.setTextColor(colors.cyan)
        mon.setBackgroundColor(colors.black)
        
        mon.setCursorPos(mx+2, my+1)
        mon.write("ЗАКАЗАТЬ АВТОКРАФТ")
        
        mon.setTextColor(colors.white)
        mon.setCursorPos(mx+2, my+3)
        mon.write("Предмет: " .. clean_name(ui.modal.name))
        
        mon.setTextColor(colors.gray)
        mon.setCursorPos(mx+2, my+4)
        mon.write(string.format("Выход рецепта: x%d (Будет изготовлено: x%d)", out_count, total_output))
        
        mon.setTextColor(colors.white)
        mon.setCursorPos(mx+2, my+6)
        mon.write("Количество: ")
        mon.setTextColor(colors.cyan)
        mon.write(tostring(ui.modal.count))
        
        -- Draw count adjustment buttons
        draw_small_btn(mon, mx+2, my+8, 5, "-1", "DEC:1", colors.gray, colors.white)
        draw_small_btn(mon, mx+8, my+8, 5, "-10", "DEC:10", colors.gray, colors.white)
        draw_small_btn(mon, mx+14, my+8, 5, "-64", "DEC:64", colors.gray, colors.white)
        
        draw_small_btn(mon, mx+mw-19, my+8, 5, "+1", "INC:1", colors.gray, colors.white)
        draw_small_btn(mon, mx+mw-13, my+8, 5, "+10", "INC:10", colors.gray, colors.white)
        draw_small_btn(mon, mx+mw-7, my+8, 5, "+64", "INC:64", colors.gray, colors.white)
        
        -- Ingredients list title
        mon.setTextColor(colors.lightGray)
        mon.setCursorPos(mx+2, my+10)
        mon.write("Ингредиенты (Доступно / Нужно):")
        
        -- List unique ingredients
        if recipe then
            local grouped = group_ingredients(recipe.ingredients)
            local ing_y = my + 11
            for _, ing in ipairs(grouped) do
                local total_needed = ing.count * batches
                local available = storage.getAvailable(ing.name)
                
                mon.setCursorPos(mx+2, ing_y)
                if available >= total_needed then
                    mon.setTextColor(colors.green)
                else
                    mon.setTextColor(colors.red)
                end
                
                mon.write(string.format("- %-18s : %d / %d", clean_name(ing.name):sub(1, 18), available, total_needed))
                ing_y = ing_y + 1
                if ing_y > my+14 then break end
            end
        else
            mon.setCursorPos(mx+2, my+11)
            mon.setTextColor(colors.red)
            mon.write("Рецепт отсутствует!")
        end
        
        if ui.modal.error then
            mon.setCursorPos(mx+2, my+15)
            mon.setTextColor(colors.red)
            mon.write(ui.modal.error:sub(1, mw-4))
        end
        
        draw_small_btn(mon, mx+2, my+mh-2, 16, "ЗАПУСТИТЬ КРАФТ", "CRAFT_START_OK", colors.blue, colors.white)
        draw_small_btn(mon, mx+mw-14, my+mh-2, 12, "ОТМЕНА", "CRAFT_CANCEL", colors.gray, colors.white)
        
    elseif ui.modal.type == "RECIPE_SUCCESS" then
        rect(mon, mx, my, mw, mh, colors.black, colors.green)
        mon.setTextColor(colors.green)
        mon.setBackgroundColor(colors.black)
        
        mon.setCursorPos(mx+2, my+2)
        mon.write("ТЕСТ КРАФТА УСПЕШЕН!")
        
        mon.setTextColor(colors.white)
        mon.setCursorPos(mx+2, my+4)
        mon.write("Получено: " .. clean_name(ui.modal.data.output.name) .. " x" .. ui.modal.data.output.count)
        
        mon.setCursorPos(mx+2, my+6)
        mon.write("Ингредиенты распознаны.")
        mon.setCursorPos(mx+2, my+7)
        mon.write("Записать рецепт в память?")
        
        draw_small_btn(mon, mx+2, my+11, 16, "СОХРАНИТЬ РЕЦЕПТ", "SAVE_RECIPE_OK", colors.green, colors.white)
        draw_small_btn(mon, mx+mw-14, my+11, 12, "ОТМЕНИТЬ", "SAVE_RECIPE_CANCEL", colors.gray, colors.white)
        
    elseif ui.modal.type == "RECIPE_FAILED" then
        rect(mon, mx, my, mw, mh, colors.black, colors.red)
        mon.setTextColor(colors.red)
        mon.setBackgroundColor(colors.black)
        
        mon.setCursorPos(mx+2, my+2)
        mon.write("ОШИБКА ТЕСТА КРАФТА!")
        
        mon.setTextColor(colors.white)
        mon.setCursorPos(mx+2, my+5)
        mon.write("Причина: " .. tostring(ui.modal.error))
        
        draw_small_btn(mon, mx+math.floor((mw-10)/2), my+11, 10, "ЗАКРЫТЬ", "REC_ERR_CLOSE", colors.red, colors.white)
    end
end

function ui.touch(x, y)
    for _, b in ipairs(ui.btns) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.id end
    end
end

return ui
