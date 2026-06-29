local net = require("lib.net")
local worker = { id = os.getComputerID(), status = "IDLE", core_id = nil }

local slot_map = {
    [4] = 1,  [5] = 2,  [6] = 3,
    [13] = 5, [14] = 6, [15] = 7,
    [22] = 9, [23] = 10, [24] = 11
}

local function opposite_side(side)
    local opp = {
        down = "up",
        up = "down",
        front = "back",
        back = "front",
        left = "right",
        right = "left"
    }
    return opp[side] or "up"
end

local function get_adjacent_chests()
    local sides = {"down", "up", "front", "back", "left", "right"}
    local input_chest, output_chest
    local input_side, output_side
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) and (peripheral.getType(side) == "inventory" or peripheral.hasType(side, "inventory")) then
            if not input_chest then
                input_chest = peripheral.wrap(side)
                input_side = side
            elseif not output_chest then
                output_chest = peripheral.wrap(side)
                output_side = side
                break
            end
        end
    end
    return input_chest, input_side, output_chest, output_side
end

local function push_all_to_output(output, opp_output)
    if not output then return end
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            output.pullItems(opp_output, slot, 64)
        end
    end
end

function worker.loop()
    print("Worker booting...")
    for _, side in ipairs(redstone.getSides()) do
        if peripheral.getType(side) == "modem" then rednet.open(side) end
    end

    while true do
        if not worker.core_id then
            print("Seeking Core...")
            net.broadcast("DISCOVER", {id = worker.id})
        end
        
        local id, type, data = net.receive(3)
        if id and type == "DISCOVER_ACK" then
            worker.core_id = id
            print("Connected to Core: " .. id)
        elseif type == "CRAFT_REQUEST" or type == "TEST_CRAFT" then
            worker.status = (type == "TEST_CRAFT") and "TESTING" or "CRAFTING"
            if worker.core_id then
                net.send(worker.core_id, "HEARTBEAT", {status = worker.status})
            end
            
            local action_name = (type == "TEST_CRAFT") and "testing craft" or "crafting " .. tostring(data.name)
            print("Worker status: " .. action_name)
            
            local input, input_side, output, output_side = get_adjacent_chests()
            if not input or not output then
                print("Error: missing adjacent input/output chest!")
                net.send(worker.core_id, "RESULT", {
                    task_id = data.id,
                    success = false,
                    error = "Worker lacks 2 adjacent chests (IN and OUT)"
                })
            else
                local opp_input = opposite_side(input_side)
                local opp_output = opposite_side(output_side)
                
                -- 1. Clear turtle inventory first
                push_all_to_output(output, opp_output)
                
                -- 2. Pull ingredients from input chest
                local batches = data.batches or 1
                for chest_slot, turtle_slot in pairs(slot_map) do
                    input.pushItems(opp_input, chest_slot, batches, turtle_slot)
                end
                
                -- 3. Perform turtle craft
                print("Running turtle.craft()...")
                local success, err = turtle.craft()
                
                -- 4. Push results (and leftover ingredients) to output chest
                push_all_to_output(output, opp_output)
                
                print("Finish: success=" .. tostring(success) .. (err and (", err=" .. err) or ""))
                net.send(worker.core_id, "RESULT", {
                    task_id = data.id,
                    success = success,
                    error = err
                })
            end
            
            worker.status = "IDLE"
        end
        
        if worker.core_id then
            net.send(worker.core_id, "HEARTBEAT", {status = worker.status})
        end
        os.sleep(0.5)
    end
end

return worker
