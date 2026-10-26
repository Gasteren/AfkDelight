--[[
	AfkDelight - Options.lua
	By Frost-Lightbringer
	License: http://creativecommons.org/licenses/by-nc-sa/2.5
	LegalCode: http://creativecommons.org/licenses/by-nc-sa/2.5/legalcode

	The options panel (Game Menu > Options > AddOns > AfkDelight), built with the
	game's own Settings API so it looks and behaves like the rest of the options.
]]

local ADDON_NAME, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local floor, format, ipairs, type = math.floor, string.format, ipairs, type

local settings = {}

function Options:SetValue(key, value)
	local setting = settings[key]
	if not setting then
		return false
	end
	setting:SetValue(value)
	return true
end

function Options:Open()
	if not (self.category and Settings and Settings.OpenToCategory) then
		return false
	end
	Settings.OpenToCategory(self.category:GetID())
	return true
end

local function Register(category, key, name)
	local default = ns.defaults[key]
	local setting = Settings.RegisterAddOnSetting(category, ADDON_NAME .. "_" .. key, key, ns.db, type(default), name, default)
	setting:SetValueChangedCallback(function()
		ns:OnSettingChanged(key)
	end)
	settings[key] = setting
	return setting
end

local function Checkbox(category, key, name, tooltip)
	return Settings.CreateCheckbox(category, Register(category, key, name), tooltip)
end

local function Slider(category, key, name, tooltip, step, formatter)
	local range = ns.ranges[key]
	local options = Settings.CreateSliderOptions(range[1], range[2], step)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
	end
	return Settings.CreateSlider(category, Register(category, key, name), options, tooltip)
end

local function Dropdown(category, key, name, tooltip, choices)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, choice in ipairs(choices) do
			container:Add(choice[1], choice[2], choice[3])
		end
		return container:GetData()
	end
	return Settings.CreateDropdown(category, Register(category, key, name), GetOptions, tooltip)
end

local function Header(layout, text)
	if CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end
end

local function Button(layout, name, buttonText, onClick, tooltip)
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
	end
end

-- Greys out a control unless the predicate is true; re-checked whenever the parent changes.
local function DependsOn(child, parent, predicate)
	if child and parent and child.SetParentInitializer then
		child:SetParentInitializer(parent, predicate)
	end
end

local function Seconds(value)
	value = floor(value + 0.5)
	if value == 0 then
		return L.OPT_INSTANT
	end
	return format(L.OPT_SECONDS, value)
end

local function Percent(value)
	return format(L.OPT_PERCENT, floor(value + 0.5))
end

local function Degrees(value)
	return format(L.OPT_DEGREES, floor(value + 0.5))
end

function Options:Init()
	if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end
	local category, layout = Settings.RegisterVerticalLayoutCategory("AfkDelight")
	self.category = category
	local db = ns.db

	Header(layout, L.OPT_GENERAL)
	local enabled = Checkbox(category, "enabled", L.OPT_ENABLED, L.OPT_ENABLED_TT)
	local function IsEnabled()
		return db.enabled
	end
	DependsOn(Slider(category, "delay", L.OPT_DELAY, L.OPT_DELAY_TT, 5, Seconds), enabled, IsEnabled)
	DependsOn(Checkbox(category, "disableInInstances", L.OPT_NO_INSTANCES, L.OPT_NO_INSTANCES_TT), enabled, IsEnabled)
	DependsOn(Checkbox(category, "dismissOnPopups", L.OPT_DISMISS_POPUPS, L.OPT_DISMISS_POPUPS_TT), enabled, IsEnabled)
	Checkbox(category, "showSummary", L.OPT_SUMMARY, L.OPT_SUMMARY_TT)

	Header(layout, L.OPT_APPEARANCE)
	local background = Dropdown(category, "background", L.OPT_BACKGROUND, L.OPT_BACKGROUND_TT, {
		{ "AZEROTH", L.BG_AZEROTH, L.BG_AZEROTH_TT },
		{ "STARFIELD", L.BG_STARFIELD, L.BG_STARFIELD_TT },
		{ "WORLD", L.BG_WORLD, L.BG_WORLD_TT },
		{ "SOLID", L.BG_SOLID, L.BG_SOLID_TT },
	})
	local function IsWorld()
		return db.background == "WORLD"
	end
	DependsOn(Slider(category, "worldDim", L.OPT_WORLD_DIM, L.OPT_WORLD_DIM_TT, 5, Percent), background, IsWorld)
	DependsOn(Checkbox(category, "cameraSpin", L.OPT_CAMERA_SPIN, L.OPT_CAMERA_SPIN_TT), background, IsWorld)

	local showModel = Checkbox(category, "showModel", L.OPT_SHOW_MODEL, L.OPT_SHOW_MODEL_TT)
	local function ShowsModel()
		return db.showModel
	end
	DependsOn(Dropdown(category, "animation", L.OPT_ANIMATION, L.OPT_ANIMATION_TT, {
		{ "RANDOM", L.ANIM_RANDOM },
		{ "STAND", L.ANIM_STAND },
		{ "DANCE", L.ANIM_DANCE },
		{ "TALK", L.ANIM_TALK },
	}), showModel, ShowsModel)
	DependsOn(Checkbox(category, "introWave", L.OPT_INTRO_WAVE, L.OPT_INTRO_WAVE_TT), showModel, ShowsModel)
	DependsOn(Slider(category, "modelFacing", L.OPT_FACING, L.OPT_FACING_TT, 5, Degrees), showModel, ShowsModel)
	DependsOn(Checkbox(category, "modelSpin", L.OPT_MODEL_SPIN, L.OPT_MODEL_SPIN_TT), showModel, ShowsModel)
	DependsOn(Slider(category, "modelScale", L.OPT_MODEL_SCALE, L.OPT_MODEL_SCALE_TT, 5, Percent), showModel, ShowsModel)

	Header(layout, L.OPT_INFO)
	Checkbox(category, "showInfo", L.OPT_SHOW_INFO, L.OPT_SHOW_INFO_TT)
	Checkbox(category, "showClock", L.OPT_SHOW_CLOCK, L.OPT_SHOW_CLOCK_TT)
	local showChat = Checkbox(category, "showChat", L.OPT_SHOW_CHAT, L.OPT_SHOW_CHAT_TT)
	local function ShowsChat()
		return db.showChat
	end
	DependsOn(Checkbox(category, "chatGuild", L.OPT_CHAT_GUILD, L.OPT_CHAT_GUILD_TT), showChat, ShowsChat)
	DependsOn(Checkbox(category, "chatGroup", L.OPT_CHAT_GROUP, L.OPT_CHAT_GROUP_TT), showChat, ShowsChat)
	Checkbox(category, "flashOnWhisper", L.OPT_FLASH, L.OPT_FLASH_TT)

	Header(layout, L.OPT_TOOLS)
	Button(layout, L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, function()
		ns:TogglePreview()
	end, L.OPT_PREVIEW_TT)
	Button(layout, L.OPT_RESET, L.OPT_RESET_BUTTON, function()
		ns:ResetSettings()
	end, L.OPT_RESET_TT)

	Settings.RegisterAddOnCategory(category)
end
