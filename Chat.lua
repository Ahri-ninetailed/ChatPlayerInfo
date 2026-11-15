-- Chat.lua: значки перед текстом сообщения и клик по серому уровню.
--
-- Значки ставятся фильтром сообщений в начало текста (arg1). Ничего не перехватывается
-- и не заменяется. С TwoLineChat это работает в любом порядке фильтров: он находит границу
-- по исходному тексту строки (C_ChatInfo.GetChatLineText), и значки попадают в первую строку.
--
-- Значки нельзя поставить внутрь имени (ChatFrameUtil.AddSenderNameFilter): имя - это ссылка
-- на игрока, а в неё нельзя вложить кликабельную ссылку серого уровня.

local ADDON_NAME, ns = ...
local L = ns.L
local Usable = ns.Usable

local EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM", -- твой шёпот "To [Имя]": значки получателя
    "CHAT_MSG_CHANNEL", -- General, Trade, LFG и пользовательские каналы
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local STALE_COLOR = "|cff808080"
-- Жёлтый, как уровень дружественного игрока на рамке цели (1, 0.82, 0).
local LEVEL_COLOR = "|cffffd100"
local LINK_PREFIX = "addon:" .. ADDON_NAME .. ":who:"
local WHO_COOLDOWN = 5 -- сервер всё равно не отвечает на /who чаще

-- Череп, как на рамке цели у слишком сильного врага. Запасной - метка "череп".
local SKULL_ATLAS = "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon"
local SKULL_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
-- Насколько враг должен быть выше, чтобы показать череп (как у клиента).
local SKULL_LEVEL_GAP = 10

local SEX = { [2] = "male", [3] = "female" }

-- englishRace из GetPlayerInfoByGUID, которые не совпадают с именем атласа raceicon-*.
local RACE_ATLAS = {
    scourge = "undead",
    highmountaintauren = "highmountain",
    lightforgeddraenei = "lightforged",
    zandalaritroll = "zandalari",
}

-- Иконки -----------------------------------------------------------------------

local atlasExists = {}

-- Имя атласа, если он есть в клиенте, иначе nil (тогда иконку не показываем).
local function Atlas(name)
    local exists = atlasExists[name]
    if exists == nil then
        exists = not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(name) ~= nil
        atlasExists[name] = exists
    end
    return exists and name or nil
end

-- Иконки по размеру шрифта окна чата.
local function IconSize(chatFrame)
    local height = chatFrame and chatFrame.GetFont and select(2, chatFrame:GetFont())
    if type(height) == "number" and height > 0 then
        return math.floor(height + 0.5)
    end
    return 14
end

-- /who ---------------------------------------------------------------------------

local function WhoAvailable()
    if not (C_FriendList and C_FriendList.SendWho) then
        return false
    end
    local rules = C_GameRules
    local rule = Enum.GameRule and Enum.GameRule.IngameWhoListDisabled
    if rules and rules.IsGameRuleActive and rule and rules.IsGameRuleActive(rule) then
        return false
    end
    return true
end

-- Фракция -------------------------------------------------------------------------

-- englishRace -> "Alliance"/"Horde" по данным клиента, так что новые расы учтутся сами.
-- Раса, которая бывает в обеих фракциях (пандарены), получает false: по ней не понять.
local factionByRace

local function RaceFaction(raceFile)
    if not factionByRace then
        factionByRace = {}
        local info = C_CreatureInfo
        if info and info.GetRaceInfo and info.GetFactionInfo then
            for raceID = 1, 100 do
                local race = info.GetRaceInfo(raceID)
                local faction = race and info.GetFactionInfo(raceID)
                local tag = faction and faction.groupTag
                if race and race.clientFileString and (tag == "Alliance" or tag == "Horde") then
                    local key = race.clientFileString:lower()
                    local known = factionByRace[key]
                    if known == nil then
                        factionByRace[key] = tag
                    elseif known ~= tag then
                        factionByRace[key] = false
                    end
                end
            end
        end
    end
    return factionByRace[raceFile:lower()] or nil
end

local function PlayerFaction(guid, raceFile)
    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if Usable(unit) and unit then
        local faction = UnitFactionGroup(unit)
        if Usable(faction) and (faction == "Alliance" or faction == "Horde") then
            return faction
        end
    end
    if Usable(raceFile) and type(raceFile) == "string" then
        return RaceFaction(raceFile)
    end
    return nil
end

-- Уровень -------------------------------------------------------------------------

-- Уровень серым. Если его можно проверить через /who, это ссылка: клик проверяет уровень.
local function StaleText(info, text)
    if info.canWho then
        return STALE_COLOR .. "|H" .. LINK_PREFIX .. info.guid .. "|h" .. text .. "|h|r"
    end
    return STALE_COLOR .. text .. "|r"
end

-- Свежий уровень: жёлтым или, если галка "Жёлтый уровень" снята, цветом строки.
local function FreshText(level)
    if ns.db.yellowLevel then
        return LEVEL_COLOR .. level .. "|r"
    end
    return tostring(level)
end

local function SkullMarkup(size)
    if Atlas(SKULL_ATLAS) then
        return CreateAtlasMarkup(SKULL_ATLAS, size, size)
    end
    return "|T" .. SKULL_TEXTURE .. ":" .. size .. ":" .. size .. "|t"
end

local function LevelText(info, size)
    local skull = info.skull and SkullMarkup(size) or ""

    if info.level and info.fresh then
        return skull .. FreshText(info.level)
    end
    if info.level then
        return skull .. StaleText(info, tostring(info.level))
    end
    -- Уровень неизвестен: "?" имеет смысл, только если его можно узнать кликом.
    if info.canWho then
        return skull .. StaleText(info, "?")
    end
    return skull ~= "" and skull or nil
end

-- Что известно об авторе строки. Считается один раз на строку: фильтр вызывается
-- для каждого окна чата, в котором видна строка, и во всех окнах должно быть одно и то же.
local lineInfo, lineOrder = {}, {}
local MAX_LINES = 200

local function Remember(lineID, info)
    if type(lineID) ~= "number" then
        return
    end
    if not lineInfo[lineID] then
        table.insert(lineOrder, lineID)
        if #lineOrder > MAX_LINES then
            lineInfo[table.remove(lineOrder, 1)] = nil
        end
    end
    lineInfo[lineID] = info
end

local function Resolve(guid)
    local _, classFile, _, raceFile, sex, _, _, cachedLevel = GetPlayerInfoByGUID(guid)
    local info = { guid = guid }

    if Usable(classFile) and type(classFile) == "string" then
        info.classAtlas = Atlas("classicon-" .. classFile:lower())
    end
    if Usable(raceFile) and type(raceFile) == "string" and Usable(sex) and SEX[sex] then
        local race = raceFile:lower()
        info.raceAtlas = Atlas("raceicon-" .. (RACE_ATLAS[race] or race) .. "-" .. SEX[sex])
    end

    local tooHigh
    info.level, info.fresh, tooHigh = ns.GetLevel(guid, cachedLevel)

    -- Игрок другой фракции. /who показывает только свою фракцию, поэтому его уровень
    -- кликом не проверить. Если он на SKULL_LEVEL_GAP уровней выше, рядом с уровнем череп.
    local faction = PlayerFaction(guid, raceFile)
    local myFaction = UnitFactionGroup("player")
    local enemy = faction ~= nil and Usable(myFaction) and faction ~= myFaction
    local myLevel = UnitLevel("player")

    info.canWho = not enemy and WhoAvailable()
    info.skull = tooHigh or (enemy and info.level ~= nil and Usable(myLevel)
        and info.level >= myLevel + SKULL_LEVEL_GAP) or false
    return info
end

local function BuildPrefix(info, chatFrame)
    local db = ns.db
    local size = IconSize(chatFrame)

    local icons = ""
    if db.showClass and info.classAtlas then
        icons = icons .. CreateAtlasMarkup(info.classAtlas, size, size)
    end
    if db.showRace and info.raceAtlas then
        icons = icons .. CreateAtlasMarkup(info.raceAtlas, size, size)
    end

    -- Уровень сразу за иконками, без пробела: пробел в шрифте чата широкий, а у круглых
    -- иконок и так есть прозрачный край, так что цифры не слипаются с картинкой.
    local level = db.showLevel and LevelText(info, size) or nil
    if level then
        return icons .. level
    end
    return icons
end

-- В событиях чата GUID иногда приходит как "PLAYER-...", функции клиента ждут "Player-...".
local function PlayerGUID(guid)
    if not Usable(guid) or type(guid) ~= "string" or guid:sub(1, 7):lower() ~= "player-" then
        return nil
    end
    return "Player-" .. guid:sub(8)
end

local function Filter(chatFrame, _, text, author, ...)
    -- Клиент не вызывает фильтры с секретными аргументами, но проверка дешёвая.
    if not ns.db or not Usable(text) or type(text) ~= "string" or text == "" then
        return false
    end

    local lineID, guid = select(9, ...) -- arg11 = lineID, arg12 = GUID автора
    guid = PlayerGUID(guid)
    if not guid then
        return false
    end

    local info = Usable(lineID) and lineInfo[lineID]
    if not info then
        info = Resolve(guid)
        Remember(lineID, info)
    end

    local prefix = BuildPrefix(info, chatFrame)
    if prefix == "" then
        return false
    end
    return false, prefix .. " " .. text, author, ...
end

-- Клик по серому уровню -------------------------------------------------------

local function ForEachChatFrame(fn)
    if ChatFrameUtil and ChatFrameUtil.ForEachChatFrame then
        ChatFrameUtil.ForEachChatFrame(fn)
        return
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            fn(chatFrame)
        end
    end
end

-- Заменяет серый уровень игрока в уже показанных строках на проверенный.
local function RefreshLines(guid)
    local level = ns.GetLevel(guid)
    if not level then
        return
    end

    for _, info in pairs(lineInfo) do
        if info.guid == guid then
            info.level, info.fresh = level, true
        end
    end

    local mark = STALE_COLOR .. "|H" .. LINK_PREFIX .. guid .. "|h"
    local replacement = FreshText(level)

    local function Matches(message)
        return Usable(message) and type(message) == "string" and message:find(mark, 1, true) ~= nil
    end

    local function Transform(message, ...)
        local s, e = message:find(mark, 1, true)
        local close = s and message:find("|h|r", e + 1, true)
        if close then
            message = message:sub(1, s - 1) .. replacement .. message:sub(close + 4)
        end
        return message, ...
    end

    ForEachChatFrame(function(chatFrame)
        if chatFrame.TransformMessages then
            chatFrame:TransformMessages(Matches, Transform)
        end
    end)
end

local lastWho = 0
local pending = {} -- имя -> guid, ждут ответа /who

local function ScanWhoResults()
    if not next(pending) or not C_FriendList.GetNumWhoResults then
        return
    end
    for i = 1, C_FriendList.GetNumWhoResults() or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        local name = info and info.fullName
        if Usable(name) and type(name) == "string" then
            local baseName = name:match("^[^-]+") or name
            local guid = pending[name] or pending[baseName]
            if guid and Usable(info.level) and info.level > 0 then
                pending[name], pending[baseName] = nil, nil
                ns.StoreLevel(guid, info.level)
                RefreshLines(guid)
            end
        end
    end
end

-- /who разрешён только по действию игрока (клик, клавиша), поэтому запускается
-- только отсюда, из клика по ссылке.
local function RequestWho(guid)
    if not WhoAvailable() then
        return
    end
    local _, _, _, _, _, name = GetPlayerInfoByGUID(guid)
    if not Usable(name) or type(name) ~= "string" or name == "" then
        return
    end

    local wait = WHO_COOLDOWN - (GetTime() - lastWho)
    if wait > 0 then
        print(ns.PRINT_PREFIX .. L.WHO_COOLDOWN:format(math.ceil(wait)))
        return
    end
    lastWho = GetTime()

    pending[name] = guid
    local origin = Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Chat
    C_FriendList.SendWho((WHO_TAG_NAME or "n-") .. "\"" .. name .. "\"", origin)

    -- Ответ приходит через WHO_LIST_UPDATE. На случай, если клиент вывел результат только
    -- в чат и событие не пришло, список проверяется ещё и по таймеру.
    C_Timer.After(1.5, ScanWhoResults)
    C_Timer.After(4, ScanWhoResults)
    C_Timer.After(10, function()
        if pending[name] == guid then
            pending[name] = nil
        end
    end)
end

ns.On("WHO_LIST_UPDATE", ScanWhoResults)

if EventRegistry then
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then
            return
        end
        RequestWho(link:sub(#LINK_PREFIX + 1))
    end, ns)
end

-- Регистрация ---------------------------------------------------------------------

-- В клиенте 12.x фильтры живут в ChatFrameUtil; ChatFrame_AddMessageEventFilter - лишь
-- устаревший алиас.
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if not addFilter then
    print(ns.PRINT_PREFIX .. "chat filter API not found, the addon is disabled.")
    return
end

for _, event in ipairs(EVENTS) do
    addFilter(event, Filter)
end
