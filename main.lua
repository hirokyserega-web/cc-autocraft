local args = {...}
local isTurtle = (turtle ~= nil)
if args[1] == "run" then
    if isTurtle then
        require("worker.worker").loop()
    else
        require("core.server").main()
    end
else
    print("Usage: main.lua run")
end
