local isTurtle = (turtle ~= nil)
print("---------------------------------")
print("CC-AUTOCRAFT SYSTEM STARTING...")
print("Computer ID: " .. os.getComputerID())
print("Mode: " .. (isTurtle and "WORKER" or "CORE"))
print("---------------------------------")

local ok, err = pcall(function()
    if isTurtle then
        require("worker.worker").loop()
    else
        require("core.server").main()
    end
end)

if not ok then
    printError("CRITICAL FAILURE:")
    printError(err)
end
