-- Levels.lua: откуда берётся уровень игрока и насколько он свежий.
--
-- Сервер не передаёт уровень вместе с сообщением. Кэш клиента (GetPlayerInfoByGUID)
-- запоминает уровень при первом знакомстве с игроком и потом его не обновляет,
-- а сбросить этот кэш из аддона нельзя. Поэтому аддон сам запоминает уровень и время,
-- когда его подтвердил живой источник:
--   * игрок сейчас доступен клиенту: таргет, фокус, мышка, табличка над головой, группа;
--   * список гильдии и сообщества (Club API);
--   * список друзей;
--   * /who, запущенный кликом по серому уровню (Chat.lua).
-- Уровень, который никто не подтверждал дольше ns.STALE_AFTER, считается устаревшим.

local _, ns = ...
local Usable = ns.Usable

-- guid -> уровень и guid -> time(), когда уровень подтвердили. Хранятся в ChatPlayerInfoDB,
-- чтобы пережить /reload: кэш клиента при /reload не сбрасывается.
local levels, seenAt

local function Store(guid, level)
    if levels then
        levels[guid] = level
        seenAt[guid] = time()
    end
end
ns.StoreLevel = Store

local function Prune()
    local now = time()
    for guid, seen in pairs(seenAt) do
        if type(seen) ~= "number" or now - seen > ns.FORGET_AFTER or type(levels[guid]) ~= "number" then
            seenAt[guid] = nil
            levels[guid] = nil
        end
    end
    for guid in pairs(levels) do
        if not seenAt[guid] then
            levels[guid] = nil
        end
    end
end

-- Уровень, который уже не может вырасти. Берётся у клиента каждый раз, поэтому
-- если в WoW Forever поднимут потолок, аддон узнает об этом сам.
local function IsMaxLevel(level)
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
    return type(maxLevel) == "number" and maxLevel > 1 and level >= maxLevel
end

-- Возвращает уровень (или nil), признак, что он свежий, и признак, что клиент
-- скрывает уровень (UnitLevel = -1: враг слишком высокого уровня, на таргете череп).
-- cachedLevel - уровень из кэша клиента (8-е значение GetPlayerInfoByGUID).
function ns.GetLevel(guid, cachedLevel)
    local tooHigh = false

    -- Игрок сейчас доступен клиенту: уровень живой.
    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if Usable(unit) and unit then
        local level = UnitLevel(unit)
        if Usable(level) and level > 0 then
            Store(guid, level)
            return level, true, false
        end
        tooHigh = Usable(level) and level == -1
    end

    if not levels then
        return nil, false, tooHigh
    end

    local level, seen = levels[guid], seenAt[guid]

    -- Кэш клиента знает больше нас: первое знакомство (клиент только что спросил сервер)
    -- или клиент получил уровень выше запомненного.
    if Usable(cachedLevel) and type(cachedLevel) == "number" and cachedLevel > 0
        and (not level or cachedLevel > level) then
        Store(guid, cachedLevel)
        level, seen = cachedLevel, time()
    end

    if not level then
        return nil, false, tooHigh
    end

    return level, time() - seen < ns.STALE_AFTER or IsMaxLevel(level), tooHigh
end

-- Живые источники ------------------------------------------------------------

local function RecordUnit(unit)
    if not unit or not UnitExists(unit) then
        return
    end
    local isPlayer = UnitIsPlayer(unit)
    if not Usable(isPlayer) or not isPlayer then
        return
    end
    local guid, level = UnitGUID(unit), UnitLevel(unit)
    if Usable(guid) and guid and Usable(level) and level > 0 then
        Store(guid, level)
    end
end

local function ScanGroup()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            RecordUnit("raid" .. i)
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            RecordUnit("party" .. i)
        end
    end
end

local function ScanFriends()
    local list = C_FriendList
    if not (list and list.GetNumFriends and list.GetFriendInfoByIndex) then
        return
    end
    for i = 1, list.GetNumFriends() or 0 do
        local info = list.GetFriendInfoByIndex(i)
        if info and Usable(info.guid) and info.guid and Usable(info.level) and info.level > 0 then
            Store(info.guid, info.level)
        end
    end
end

-- Гильдия и сообщества. Уровень офлайн-участника тоже верный: офлайн уровень не растёт.
local clubScanQueued = false

-- Таблица, которую можно читать. Пока действуют ограничения (бой с боссом и т.п.),
-- Club API отдаёт вместо списка участников секретное значение, и ipairs по нему падает.
local function Readable(value)
    return Usable(value) and type(value) == "table"
end

local function ScanClubs()
    clubScanQueued = false
    local club = C_Club
    if not (club and club.GetSubscribedClubs and club.GetClubMembers and club.GetMemberInfo) then
        return
    end
    local clubs = club.GetSubscribedClubs()
    if not Readable(clubs) then
        return
    end
    -- Если список скрыт, просто пропускаем: после снятия ограничений придёт новое
    -- GUILD_ROSTER_UPDATE (запрос гильдии раз в 2 минуты) или CLUB_MEMBER*_UPDATED.
    for _, clubInfo in ipairs(clubs) do
        local clubId = Readable(clubInfo) and clubInfo.clubId
        local members = Usable(clubId) and clubId and club.GetClubMembers(clubId)
        if Readable(members) then
            for _, memberId in ipairs(members) do
                local member = Usable(memberId) and club.GetMemberInfo(clubId, memberId)
                if Readable(member) and Usable(member.guid) and member.guid
                    and Usable(member.level) and type(member.level) == "number" and member.level > 0 then
                    Store(member.guid, member.level)
                end
            end
        end
    end
end

-- Список гильдии обновляется пачками событий: сканируем один раз после паузы.
local function QueueClubScan()
    if not clubScanQueued then
        clubScanQueued = true
        C_Timer.After(2, ScanClubs)
    end
end

-- Просим сервер прислать свежий список гильдии. Сервер сам ограничивает частоту.
local function RequestGuildRoster()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

local guildTicker

ns.OnLoad(function(db)
    if type(db.levels) ~= "table" then db.levels = {} end
    if type(db.seen) ~= "table" then db.seen = {} end
    levels, seenAt = db.levels, db.seen
    Prune()
end)

ns.On("PLAYER_LOGOUT", function()
    if levels then
        Prune()
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    ScanGroup()
    ScanFriends()
    QueueClubScan()
    if not guildTicker then
        C_Timer.After(5, RequestGuildRoster)
        guildTicker = C_Timer.NewTicker(120, RequestGuildRoster)
    end
end)

ns.On("UNIT_LEVEL", RecordUnit)
ns.On("NAME_PLATE_UNIT_ADDED", RecordUnit)
ns.On("PLAYER_TARGET_CHANGED", function() RecordUnit("target") end)
ns.On("PLAYER_FOCUS_CHANGED", function() RecordUnit("focus") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() RecordUnit("mouseover") end)
ns.On("GROUP_ROSTER_UPDATE", ScanGroup)
ns.On("FRIENDLIST_UPDATE", ScanFriends)
ns.On("GUILD_ROSTER_UPDATE", QueueClubScan)
ns.On("CLUB_MEMBERS_UPDATED", QueueClubScan)
ns.On("CLUB_MEMBER_UPDATED", QueueClubScan)
