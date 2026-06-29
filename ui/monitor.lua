-- Monitor UI for Core
local dispatcher = require("core.dispatcher")

local ui = {}

function ui.draw(monitorName)
    local mon = peripheral.wrap(monitorName)
    if not mon then return end
    
    mon.setTextScale(0.5)
    mon.clear()
    mon.setCursorPos(1, 1)
    mon.write("--- CC-AUTOCRAFT CORE ---")
    
    local row = 3
    mon.setCursorPos(1, row)
    mon.write("Queue:")
    row = row + 1
    
    for i = #dispatcher.queue, math.max(1, #dispatcher.queue - 10), -1 do
        local task = dispatcher.queue[i]
        mon.setCursorPos(1, row)
        local statusColor = colors.white
        if task.status == "COMPLETED" then statusColor = colors.green
        elseif task.status == "CRAFTING" then statusColor = colors.yellow
        elseif task.status == "FAILED" then statusColor = colors.red
        end
        
        mon.setTextColor(statusColor)
        mon.write(string.format("[%s] %s x%d", task.status:sub(1,1), task.name, task.count))
        row = row + 1
    end
    mon.setTextColor(colors.white)
end

return ui
