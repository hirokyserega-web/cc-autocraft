local widgets = {}

local function fill(mon, x, y, w, h, bg)
    mon.setBackgroundColor(bg)
    local s = string.rep(" ", w)
    for i = 0, h - 1 do
        mon.setCursorPos(x, y + i)
        mon.write(s)
    end
end

function widgets.drawBox(mon, x, y, w, h, bg, borderCol)
    fill(mon, x, y, w, h, bg)
    if borderCol then
        mon.setBackgroundColor(borderCol)
        mon.setCursorPos(x, y); mon.write(string.rep(" ", w))
        mon.setCursorPos(x, y + h - 1); mon.write(string.rep(" ", w))
        for i = 1, h - 2 do
            mon.setCursorPos(x, y + i); mon.write(" ")
            mon.setCursorPos(x + w - 1, y + i); mon.write(" ")
        end
    end
end

function widgets.drawText(mon, x, y, text, fg, bg)
    mon.setTextColor(fg)
    mon.setBackgroundColor(bg)
    mon.setCursorPos(x, y)
    mon.write(text)
end

function widgets.drawButton(mon, x, y, w, h, label, id, active, theme, btns)
    local bg = active and theme.btnActive or theme.btnBase
    local fg = active and theme.textActive or theme.textBase
    
    fill(mon, x, y, w, h, bg)
    
    local textX = x + math.floor((w - #label) / 2)
    local textY = y + math.floor((h - 1) / 2)
    widgets.drawText(mon, textX, textY, label, fg, bg)
    
    table.insert(btns, { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1, id = id })
end

function widgets.drawProgressBar(mon, x, y, w, percent, theme)
    widgets.drawBox(mon, x, y, w, 1, theme.bgMuted)
    local fillW = math.floor(w * percent)
    if fillW > 0 then
        fill(mon, x, y, fillW, 1, theme.accent)
    end
end

return widgets
