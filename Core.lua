-- ChatPlayerInfo: иконки класса и расы и уровень игрока рядом с его сообщением в чате.
--
-- Core.lua: общие константы, сохранённые настройки и раздача событий.

local ADDON_NAME, ns = ...

ns.DEFAULTS = {
    showLevel = true,
    yellowLevel = true, -- свежий уровень жёлтым; иначе цветом канала
    showClass = true,
    showRace = true,
}

-- Уровень, который никто не подтверждал дольше этого, показывается серым (секунды).
ns.STALE_AFTER = 30 * 60
-- Запомненный уровень, который не подтверждался дольше этого, забывается (секунды).
ns.FORGET_AFTER = 12 * 60 * 60

ns.PRINT_PREFIX = "|cff33ff99" .. ADDON_NAME .. ":|r "

local issecretvalue = issecretvalue or function() return false end

-- Значение можно читать: оно есть и не скрыто клиентом (chat lockdown в бою с боссом и т.п.).
function ns.Usable(value)
    return value ~= nil and not issecretvalue(value)
end

-- События --------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

-- Подписывает handler на событие. Если такого события в клиенте нет, ничего не делает.
function ns.On(event, handler)
    if not handlers[event] then
        if not pcall(frame.RegisterEvent, frame, event) then
            return false
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], handler)
    return true
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, handler in ipairs(handlers[event]) do
        handler(...)
    end
end)

-- Загрузка -------------------------------------------------------------------

local onLoad = {}

-- fn(db) вызывается один раз, когда загружены сохранённые настройки.
function ns.OnLoad(fn)
    table.insert(onLoad, fn)
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME or ns.db then
        return
    end

    if type(ChatPlayerInfoDB) ~= "table" then
        ChatPlayerInfoDB = {}
    end
    local db = ChatPlayerInfoDB
    for key, value in pairs(ns.DEFAULTS) do
        if type(db[key]) ~= type(value) then
            db[key] = value
        end
    end
    ns.db = db

    for _, fn in ipairs(onLoad) do
        fn(db)
    end
end)
