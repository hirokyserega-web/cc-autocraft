-- Localization
local lang = {}
lang.current = "ru"
lang.strings = {
    ru = {
        no_resources = "Недостаточно ресурсов: %s",
        worker_busy = "Воркер %d занят",
        task_added = "Задача %s добавлена в очередь",
    }
}

function lang.get(key, ...)
    local s = lang.strings[lang.current][key] or key
    return s:format(...)
end

return lang
