-- Worker (turtle) loop: receives craft requests, pulls ingredients from the
-- adjacent input chest into its 3x3 craft grid, crafts, pushes results to the
-- adjacent output chest, and reports back to Core.
local net = require("lib.net")
local worker = { id = os.getComputerID(), status = "IDLE", core_id = nil }

-- Map the input chest's central 3x3 (slots 4,5,6 / 13,14,15 / 22,23,24) onto
-- the turtle's 3x3 craft grid (slots 1,2,3 / 5,6,7 / 9,10,11).
local slot_map = {
    [4]  = 1,  [5]  = 2,  [6]  = 3,
    [13] = 5,  [14] = 6,  [15] = 7,
    [22] = 9,  [23] = 10, [24] = 11
}

local function opposite_side(side)
    local opp = {
        down = "up", up = "down",
        front = "back", back = "front",
        left = "right", right = "left"
    }
    return opp[side] or "up"
end

-- Robust inventory detection on a side (works on every CC:T version).
local function isInventorySide(side)
    if not peripheral.isPresent(side) then return false end
    local p = peripheral.wrap(side)
    if not p then return false end
    return type(p.list) == "function" and type(p.size) == "function"
end

-- Find two adjacent inventories: first found = input, second = output.
local function get_adjacent_chests()
    local sides = { "down", "up", "front", "back", "left", "right" }
    local input_chest, input_side, output_chest, output_side
    for _, side in ipairs(sides) do
        if isInventorySide(side) then
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

local function get_adjacent_chest_names()
    local input, _, output, _ = get_adjacent_chests()
    local in_name = input and peripheral.getName(input) or nil
    local out_name = output and peripheral.getName(output) or nil
    return in_name, out_name
end

local function push_all_to_output(output, turtle_name)
    if not output then return end
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            output.pullItems(turtle_name, slot, 64)
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
            local in_name, out_name = get_adjacent_chest_names()
            net.broadcast("DISCOVER", {
                id = worker.id,
                input_chest = in_name,
                output_chest = out_name
            })
        end

        local id, msg_type, data = net.receive(3)
        if id and msg_type == "DISCOVER_ACK" then
            worker.core_id = id
            print("Connected to Core: " .. id)

        elseif msg_type == "CRAFT_REQUEST" or msg_type == "TEST_CRAFT" then
            worker.status = (msg_type == "TEST_CRAFT") and "TESTING" or "CRAFTING"
            if worker.core_id then
                net.send(worker.core_id, "HEARTBEAT", { status = worker.status })
            end

            local action = (msg_type == "TEST_CRAFT") and "testing craft" or ("crafting " .. tostring(data.name))
            print("Worker: " .. action)

            local input, input_side, output, output_side = get_adjacent_chests()
            if not input or not output then
                print("Error: need 2 adjacent chests (IN and OUT)")
                print("Current adjacent peripherals:")
                for _, s in ipairs({ "down", "up", "front", "back", "left", "right" }) do
                    if peripheral.isPresent(s) then
                        local ptype = peripheral.getType(s) or "unknown"
                        local p = peripheral.wrap(s)
                        local isInv = p and type(p.list) == "function" and type(p.size) == "function"
                        print(string.format(" %-5s: %s (%s)", s, ptype:sub(1,10), isInv and "INV" or "NOT-INV"))
                    else
                        print(" " .. s .. ": empty")
                    end
                end
                if worker.core_id then
                    net.send(worker.core_id, "RESULT", {
                        task_id = data.id,
                        success = false,
                        error = "Worker needs 2 adjacent chests (input and output)"
                    })
                end
            else
                local turtle_name = peripheral.getNameLocal() or opposite_side(input_side)
                local target_output_name = peripheral.getNameLocal() or opposite_side(output_side)

                -- 1. Clear turtle inventory into the output chest.
                push_all_to_output(output, target_output_name)

                -- 2. Pull ingredients from the input chest's central 3x3 into
                --    the turtle's craft grid, `batches` items per cell.
                local batches = data.batches or 1
                for chest_slot, turtle_slot in pairs(slot_map) do
                    input.pushItems(turtle_name, chest_slot, batches, turtle_slot)
                end

                -- 3. Craft.
                print("Running turtle.craft()...")
                local success, err = turtle.craft()

                -- 4. Push everything (result + leftovers) to the output chest.
                push_all_to_output(output, target_output_name)

                print("Finish: success=" .. tostring(success) .. (err and (", err=" .. err) or ""))
                if worker.core_id then
                    net.send(worker.core_id, "RESULT", {
                        task_id = data.id,
                        success = success,
                        error = err
                    })
                end
            end

            worker.status = "IDLE"
        end

        if worker.core_id then
            local in_name, out_name = get_adjacent_chest_names()
            net.send(worker.core_id, "HEARTBEAT", {
                status = worker.status,
                input_chest = in_name,
                output_chest = out_name
            })
        end
        os.sleep(0.5)
    end
end

return worker
