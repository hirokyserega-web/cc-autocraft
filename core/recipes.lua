-- Recipe management
local recipes = {}
local util = require("lib.util")

recipes.data = {} -- { [output_name] = { {ingredients={...}, output_count=1}, ... } }
recipes.PATH = "data/recipes.dat"

function recipes.load()
    recipes.data = util.load(recipes.PATH) or {}
end

function recipes.save()
    if not fs.exists("data") then fs.makeDir("data") end
    util.save(recipes.PATH, recipes.data)
end

function recipes.add(output_name, ingredients, output_count)
    if not recipes.data[output_name] then recipes.data[output_name] = {} end
    table.insert(recipes.data[output_name], {
        ingredients = ingredients, -- { {name=.., count=.., slot=..}, ... }
        output_count = output_count or 1
    })
    recipes.save()
end

function recipes.get(name)
    return recipes.data[name]
end

return recipes
