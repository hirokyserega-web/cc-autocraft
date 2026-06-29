-- Localization
local lang = {}
lang.current = "en"
lang.strings = {
    en = {
        no_resources = "Not enough resources: %s",
        worker_busy = "Worker %d busy",
        task_added = "Task %s added to queue",
    }
}

function lang.get(key, ...)
    local s = lang.strings[lang.current] and lang.strings[lang.current][key] or key
    return s:format(...)
end

return lang
