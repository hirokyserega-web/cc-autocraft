-- Setup a demo recipe (Chest)
local recipes = require("core.recipes")
recipes.load()

-- Chest recipe
recipes.add("minecraft:chest", {
    {name="minecraft:oak_planks", count=8}
}, 1)

print("Demo recipe added: Chest")
