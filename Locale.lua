local _, ns = ...

local L = {
    LEVEL = "Level",
    CLASS = "Class",
    RACE = "Race",
    LEVEL_TOOLTIP = "Show the player's level next to their message.\n\nA gray level has not been confirmed for a while and may be out of date. Click it to check it with /who.",
    YELLOW_LEVEL = "Yellow level",
    YELLOW_LEVEL_TOOLTIP = "Show an up-to-date level in yellow.\n\nWhen off, it takes the color of the chat channel. An out-of-date or unknown level is gray either way.",
    CLASS_TOOLTIP = "Show the player's class icon next to their message.",
    RACE_TOOLTIP = "Show the player's race icon next to their message.",
    WHO_COOLDOWN = "/who is on cooldown, try again in %d s.",
}

if GetLocale() == "ruRU" then
    L.LEVEL = "Уровень"
    L.CLASS = "Класс"
    L.RACE = "Раса"
    L.LEVEL_TOOLTIP = "Показывать уровень игрока рядом с его сообщением.\n\nСерый уровень давно никто не подтверждал, он может быть устаревшим. Нажмите на него, чтобы проверить через /who."
    L.YELLOW_LEVEL = "Жёлтый уровень"
    L.YELLOW_LEVEL_TOOLTIP = "Показывать свежий уровень жёлтым.\n\nЕсли выключено, уровень берёт цвет канала чата. Устаревший или неизвестный уровень в любом случае серый."
    L.CLASS_TOOLTIP = "Показывать иконку класса игрока рядом с его сообщением."
    L.RACE_TOOLTIP = "Показывать иконку расы игрока рядом с его сообщением."
    L.WHO_COOLDOWN = "/who пока недоступен, попробуйте через %d с."
end

ns.L = L
