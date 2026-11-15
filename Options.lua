-- Options.lua: окно настроек (Настройки -> AddOns -> ChatPlayerInfo) и команда /cpi.

local ADDON_NAME, ns = ...
local L = ns.L

local category

-- Зависимая галочка ------------------------------------------------------------
--
-- "Жёлтый уровень" стоит под "Уровнем" с отступом и недоступен, пока "Уровень" снят.
--
-- Это своя строка (шаблон в Options.xml), а не галочка Blizzard:
--   * зависимость у Blizzard задаётся через initializer:SetParentInitializer, а поле
--     parentInitializer поиск по настройкам читает вне защищённого вызова
--     (Blizzard_SettingsPanel.lua, поиск);
--   * строка на шаблоне и миксине Blizzard хранит копии методов Blizzard в нашей таблице.
--     Список настроек читает строку и вне защиты, такой метод заражает (taint) его,
--     и дальше весь список, вплоть до назначения клавиш, работает от имени аддона.
-- Поэтому шаблон без скриптов и без миксинов Blizzard, а в миксине только то, что список
-- вызывает внутри securecallfunction: Init и Release (ScrollUtil.lua,
-- ScrollBoxFactoryInitializerMixin). Та же схема, что в LFGForever.

local CHILD_TEMPLATE = "ChatPlayerInfoSettingsChildCheckboxTemplate"
local CHILD_INDENT = 15 -- шаг отступа строк Blizzard
local LABEL_INSET = 37  -- с этого x начинаются подписи всех строк

-- Глобальный: Options.xml подключает миксин по имени, а XML ищет миксины в _G.
ChatPlayerInfoSettingsChildCheckboxMixin = {}
local ChildCheckbox = ChatPlayerInfoSettingsChildCheckboxMixin

-- Доступна, только пока стоит галочка выше; недоступная выглядит как у Blizzard.
local function UpdateEnabled(row)
    local parentSetting = row.data and row.data.parentSetting
    local enabled = not parentSetting or parentSetting:GetValue() == true
    row.Checkbox:SetEnabled(enabled)
    local color = enabled and NORMAL_FONT_COLOR or GRAY_FONT_COLOR
    row.Text:SetTextColor(color.r, color.g, color.b)
    row:DesaturateHierarchy(enabled and 0 or 1)
end

-- Колбэк настройки вызывается как (owner, setting, value).
local function OnSettingChanged(row, _, value)
    row.Checkbox:SetChecked(value == true)
end

local function OnParentSettingChanged(row)
    UpdateEnabled(row)
end

-- Один раз на кадр, внутри защищённого Init: список переиспользует строки.
local function SetUpOnFirstInit(row)
    if row.cbrHandles then
        return
    end
    row.cbrHandles = Settings.CreateCallbackHandleContainer()

    for _, hover in ipairs({ row.Tooltip, row.Checkbox }) do
        Mixin(hover, DefaultTooltipMixin)
        hover:OnLoad()
    end

    -- Клик по подписи переключает галочку, как у строк Blizzard.
    row.Tooltip:SetScript("OnMouseUp", function()
        if row.Checkbox:IsEnabled() then
            row.Checkbox:Click()
        end
    end)

    row.Checkbox:SetScript("OnClick", function(box)
        if row.data then
            local value = box:GetChecked() and true or false
            row.data.setting:SetValue(value)
            PlaySound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
    end)
end

function ChildCheckbox:Init(initializer)
    SetUpOnFirstInit(self)
    self.data = initializer.data

    self.Text:SetText(initializer:GetName())
    self.Text:SetPoint("LEFT", self, "LEFT", CHILD_INDENT + LABEL_INSET, 0)
    self.Text:SetPoint("RIGHT", self, "CENTER", -85, 0)

    local function InitTooltip()
        Settings.InitTooltip(initializer:GetName(), initializer:GetTooltip())
    end
    self.Tooltip:SetTooltipFunc(InitTooltip)
    self.Checkbox:SetTooltipFunc(InitTooltip)

    local setting = self.data.setting
    self.cbrHandles:SetOnValueChangedCallback(setting:GetVariable(), OnSettingChanged, self)
    if self.data.parentSetting then
        self.cbrHandles:SetOnValueChangedCallback(self.data.parentSetting:GetVariable(),
            OnParentSettingChanged, self)
    end

    self.Checkbox:SetChecked(setting:GetValue() == true)
    UpdateEnabled(self)
end

function ChildCheckbox:Release()
    self.cbrHandles:Unregister()
    self.data = nil
end

-- Окно настроек ------------------------------------------------------------------

local function BuildSettings(db)
    local newCategory, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

    local function Register(key, label)
        local default = ns.DEFAULTS[key]
        return Settings.RegisterAddOnSetting(newCategory, ADDON_NAME .. "_" .. key, key, db,
            Settings.VarType and Settings.VarType.Boolean or type(default), label, default)
    end

    local showLevel = Register("showLevel", L.LEVEL)
    Settings.CreateCheckbox(newCategory, showLevel, L.LEVEL_TOOLTIP)

    local yellowLevel = Register("yellowLevel", L.YELLOW_LEVEL)
    if layout and Settings.CreateSettingInitializerData and Settings.CreateSettingInitializer then
        local data = Settings.CreateSettingInitializerData(yellowLevel, nil, L.YELLOW_LEVEL_TOOLTIP)
        data.parentSetting = showLevel -- читает ChildCheckbox:Init / UpdateEnabled
        layout:AddInitializer(Settings.CreateSettingInitializer(CHILD_TEMPLATE, data))
    else
        Settings.CreateCheckbox(newCategory, yellowLevel, L.YELLOW_LEVEL_TOOLTIP)
    end

    Settings.CreateCheckbox(newCategory, Register("showClass", L.CLASS), L.CLASS_TOOLTIP)
    Settings.CreateCheckbox(newCategory, Register("showRace", L.RACE), L.RACE_TOOLTIP)

    Settings.RegisterAddOnCategory(newCategory)
    category = newCategory
end

ns.OnLoad(function(db)
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
        print(ns.PRINT_PREFIX .. "settings API not found, the options window is unavailable.")
        return
    end
    -- Ошибка здесь не должна остановить остальную загрузку аддона, но и молчать не должна.
    local ok, err = pcall(BuildSettings, db)
    if not ok then
        print(ns.PRINT_PREFIX .. "could not create the options window: " .. tostring(err))
    end
end)

SLASH_CHATPLAYERINFO1 = "/cpi"
SLASH_CHATPLAYERINFO2 = "/chatplayerinfo"
SlashCmdList.CHATPLAYERINFO = function()
    if category then
        Settings.OpenToCategory(category:GetID())
    end
end
