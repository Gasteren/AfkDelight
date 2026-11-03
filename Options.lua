--[[
	AfkDelight - Options.lua
	By Frost-Lightbringer
	License: http://creativecommons.org/licenses/by-nc-sa/2.5
	LegalCode: http://creativecommons.org/licenses/by-nc-sa/2.5/legalcode

	The options page (Game Menu > Options > AddOns > AfkDelight), laid out like the game's own settings.

	It is a canvas page built from AfkDelight's own frames. Options added through the Settings API's vertical
	layouts become rows in Blizzard's shared settings list: the options search reads them and their frames are
	recycled for Blizzard's own rows, so whatever runs for an addon's rows can taint those. On WoW Forever the
	Social settings call the protected C_Discord.IsUserOAuthed() while drawing the Discord sign-in button and
	display name, which made that taint show up as "AfkDelight tried to call the protected function". On its own
	canvas AfkDelight never touches those shared rows: the search skips the page, Blizzard never reuses its frames,
	there are no dropdown menus, and its tooltips use GameTooltip rather than the game's own SettingsTooltip.
]]

local ADDON_NAME, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local floor, format, ipairs, pcall, error = math.floor, string.format, ipairs, pcall, error

-- Measurements of Blizzard's settings lists.
local ROW_HEIGHT = 26
local ROW_SPACING = 9
local HEADER_HEIGHT = 45
local CHOICE_HEIGHT = 20
local LABEL_X = 37
local INDENT = 15
local CONTROL_X = -80 -- from the middle of the row
local BUTTON_X = -40
local SLIDER_WIDTH = 250
local BUTTON_WIDTH = 200

local NORMAL_COLOR = { 1, 0.82, 0 }
local VALUE_COLOR = { 1, 1, 1 }
local DISABLED_COLOR = { 0.5, 0.5, 0.5 }

-- True while the page shows the saved settings, so the controls don't save them back.
local refreshing = false

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

-- When an option has an effect at all; the others are greyed out.
local function ScreenEnabled(db)
	return db.enabled
end

local function GameWorldBackground(db)
	return db.background == "WORLD"
end

local function ShowsModel(db)
	return db.showModel
end

local function ShowsChat(db)
	return db.showChat
end

local function ShowTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", -10, 0)
	GameTooltip:SetText(title, 1, 1, 1)
	if text then
		GameTooltip:AddLine(text, NORMAL_COLOR[1], NORMAL_COLOR[2], NORMAL_COLOR[3], true)
	end
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function SetColor(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
end

local function Change(key, value)
	if refreshing then
		return
	end
	if ns.db[key] == value then
		-- Nothing to save, but the control may show otherwise (a radio button clicked off, a slider between steps).
		Options:Refresh()
	else
		ns:SetOption(key, value)
	end
end

------------------------------------------------------------------------
-- The page
------------------------------------------------------------------------

function Options:Build()
	local panel = CreateFrame("Frame")
	panel:Hide()

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 7, -22)
	title:SetText(ADDON_NAME)
	local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
	version:SetText(ns.version)
	local divider = panel:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("Options_HorizontalDivider", true)
	divider:SetPoint("TOP", 0, -50)

	local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -54)
	scroll:SetPoint("BOTTOMRIGHT", -28, 2)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(620, 1)
	scroll:SetScrollChild(content)
	-- The page only gets its size once the Settings panel shows it.
	scroll:HookScript("OnSizeChanged", function(_, width)
		if width > 0 then
			content:SetWidth(width)
		end
	end)

	local rows, byKey = {}, {}
	local y = 10

	local function AddRow(kind, height, key)
		local row = CreateFrame("Frame", nil, content)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -y)
		row:SetPoint("RIGHT", content, "RIGHT")
		row:SetHeight(height)
		row.kind, row.key = kind, key
		y = y + height + ROW_SPACING
		rows[#rows + 1] = row
		if key then
			byKey[key] = row
		end
		return row
	end

	local function Header(text)
		local row = AddRow("header", HEADER_HEIGHT)
		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		label:SetJustifyH("LEFT")
		label:SetPoint("TOPLEFT", 7, -16)
		label:SetText(text)
		row.label = label
	end

	-- A labelled row. Options that depend on another one are indented, like in the game's settings.
	local function AddOption(kind, key, text, tooltip, enabledIf, height)
		local row = AddRow(kind, height or ROW_HEIGHT, key)
		row.enabledIf = enabledIf
		local dependent = enabledIf ~= nil
		local label = row:CreateFontString(nil, "OVERLAY", dependent and "GameFontNormalSmall" or "GameFontNormal")
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		local x = LABEL_X + (dependent and INDENT or 0)
		if height then
			-- A list of choices: the label lines up with the first one.
			label:SetPoint("TOPLEFT", x, -5)
			label:SetPoint("TOPRIGHT", row, "TOP", CONTROL_X - 5, -5)
		else
			label:SetPoint("LEFT", x, 0)
			label:SetPoint("RIGHT", row, "CENTER", CONTROL_X - 5, 0)
		end
		label:SetText(text)
		row.label = label

		local hover = CreateFrame("Frame", nil, row)
		hover:SetPoint("TOPLEFT")
		hover:SetPoint("BOTTOMRIGHT", row, "BOTTOM", CONTROL_X, 0)
		hover:EnableMouse(true)
		hover:SetScript("OnEnter", function(frame)
			ShowTooltip(frame, text, tooltip)
		end)
		hover:SetScript("OnLeave", HideTooltip)
		row.hover = hover
		return row
	end

	local function Checkbox(key, text, tooltip, enabledIf)
		local row = AddOption("checkbox", key, text, tooltip, enabledIf)
		local box = CreateFrame("CheckButton", nil, row, "SettingsCheckboxTemplate")
		box:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
		-- The template's own hover script shows the game's SettingsTooltip; AfkDelight leaves that one alone.
		box:SetScript("OnEnter", function(frame)
			ShowTooltip(frame, text, tooltip)
		end)
		box:SetScript("OnLeave", HideTooltip)
		box:SetScript("OnClick", function(button)
			local checked = button:GetChecked() and true or false
			PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			Change(key, checked)
		end)
		-- Clicking the label toggles the checkbox too.
		row.hover:SetScript("OnMouseUp", function()
			if box:IsEnabled() then
				box:Click()
			end
		end)
		function row.UpdateControl(_, db, enabled)
			box:SetChecked(db[key] == true)
			box:SetEnabled(enabled)
		end
		row.control = box
	end

	local function Slider(key, text, tooltip, step, formatter, enabledIf)
		local row = AddOption("slider", key, text, tooltip, enabledIf)
		local range = ns.ranges[key]
		local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
		slider:SetWidth(SLIDER_WIDTH)
		slider:SetPoint("LEFT", row, "CENTER", CONTROL_X, 3)
		local valueLabel = MinimalSliderWithSteppersMixin.Label.Right
		slider:Init(ns.db[key], range[1], range[2], (range[2] - range[1]) / step,
			{ [valueLabel] = CreateMinimalSliderFormatter(valueLabel, formatter) })
		slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
			Change(key, floor(value / step + 0.5) * step)
		end, row)
		function row.UpdateControl(_, db, enabled)
			slider:SetValue(db[key])
			slider:SetEnabled(enabled)
		end
		row.control = slider
	end

	-- One of a few values, as radio buttons: all of them in view, and no dropdown menu.
	local function Choice(key, text, tooltip, choices, enabledIf)
		local row = AddOption("choice", key, text, tooltip, enabledIf, #choices * CHOICE_HEIGHT + 6)
		local buttons = {}
		for index, choice in ipairs(choices) do
			local value, name, description = choice[1], choice[2], choice[3]
			-- The template names its label "$parentText", so each button gets a name of its own.
			local button = CreateFrame("CheckButton", format("%sOption_%s_%d", ADDON_NAME, key, index), row, "UIRadioButtonTemplate")
			button:SetPoint("TOPLEFT", row, "TOP", CONTROL_X + 7, -3 - (index - 1) * CHOICE_HEIGHT)
			button.text:SetText(name)
			-- The label can be clicked too.
			button:SetHitRectInsets(0, -(button.text:GetStringWidth() + 8), 0, 0)
			button:SetScript("OnClick", function()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Change(key, value)
			end)
			button:SetScript("OnEnter", function(frame)
				ShowTooltip(frame, name, description)
			end)
			button:SetScript("OnLeave", HideTooltip)
			button.value = value
			buttons[index] = button
		end
		function row.UpdateControl(_, db, enabled)
			for _, button in ipairs(buttons) do
				button:SetChecked(db[key] == button.value)
				button:SetEnabled(enabled)
				SetColor(button.text, enabled and VALUE_COLOR or DISABLED_COLOR)
			end
		end
		row.buttons = buttons
	end

	local function Button(text, buttonText, tooltip, onClick)
		local row = AddOption("button", nil, text, tooltip)
		local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		button:SetWidth(BUTTON_WIDTH)
		button:SetPoint("LEFT", row, "CENTER", BUTTON_X, 0)
		button:SetText(buttonText)
		button:HookScript("OnClick", onClick)
		button:HookScript("OnEnter", function(frame)
			ShowTooltip(frame, text, tooltip)
		end)
		button:HookScript("OnLeave", HideTooltip)
		row.control = button
	end

	Header(L.OPT_GENERAL)
	Checkbox("enabled", L.OPT_ENABLED, L.OPT_ENABLED_TT)
	Slider("delay", L.OPT_DELAY, L.OPT_DELAY_TT, 5, Seconds, ScreenEnabled)
	Checkbox("disableInInstances", L.OPT_NO_INSTANCES, L.OPT_NO_INSTANCES_TT, ScreenEnabled)
	Checkbox("dismissOnPopups", L.OPT_DISMISS_POPUPS, L.OPT_DISMISS_POPUPS_TT, ScreenEnabled)
	Checkbox("showSummary", L.OPT_SUMMARY, L.OPT_SUMMARY_TT)

	Header(L.OPT_APPEARANCE)
	Choice("background", L.OPT_BACKGROUND, L.OPT_BACKGROUND_TT, {
		{ "AZEROTH", L.BG_AZEROTH, L.BG_AZEROTH_TT },
		{ "STARFIELD", L.BG_STARFIELD, L.BG_STARFIELD_TT },
		{ "WORLD", L.BG_WORLD, L.BG_WORLD_TT },
		{ "SOLID", L.BG_SOLID, L.BG_SOLID_TT },
	})
	Slider("worldDim", L.OPT_WORLD_DIM, L.OPT_WORLD_DIM_TT, 5, Percent, GameWorldBackground)
	Checkbox("cameraSpin", L.OPT_CAMERA_SPIN, L.OPT_CAMERA_SPIN_TT, GameWorldBackground)
	Checkbox("showModel", L.OPT_SHOW_MODEL, L.OPT_SHOW_MODEL_TT)
	Choice("animation", L.OPT_ANIMATION, L.OPT_ANIMATION_TT, {
		{ "RANDOM", L.ANIM_RANDOM },
		{ "STAND", L.ANIM_STAND },
		{ "DANCE", L.ANIM_DANCE },
		{ "TALK", L.ANIM_TALK },
	}, ShowsModel)
	Checkbox("introWave", L.OPT_INTRO_WAVE, L.OPT_INTRO_WAVE_TT, ShowsModel)
	Slider("modelFacing", L.OPT_FACING, L.OPT_FACING_TT, 5, Degrees, ShowsModel)
	Checkbox("modelSpin", L.OPT_MODEL_SPIN, L.OPT_MODEL_SPIN_TT, ShowsModel)
	Slider("modelScale", L.OPT_MODEL_SCALE, L.OPT_MODEL_SCALE_TT, 5, Percent, ShowsModel)

	Header(L.OPT_INFO)
	Checkbox("showInfo", L.OPT_SHOW_INFO, L.OPT_SHOW_INFO_TT)
	Checkbox("showClock", L.OPT_SHOW_CLOCK, L.OPT_SHOW_CLOCK_TT)
	Checkbox("showChat", L.OPT_SHOW_CHAT, L.OPT_SHOW_CHAT_TT)
	Checkbox("chatGuild", L.OPT_CHAT_GUILD, L.OPT_CHAT_GUILD_TT, ShowsChat)
	Checkbox("chatGroup", L.OPT_CHAT_GROUP, L.OPT_CHAT_GROUP_TT, ShowsChat)
	Checkbox("flashOnWhisper", L.OPT_FLASH, L.OPT_FLASH_TT)

	Header(L.OPT_TOOLS)
	Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, L.OPT_PREVIEW_TT, function()
		ns:TogglePreview()
	end)
	Button(L.OPT_RESET, L.OPT_RESET_BUTTON, L.OPT_RESET_TT, function()
		ns:ResetSettings()
	end)

	content:SetHeight(y)
	self.panel, self.rows, self.byKey = panel, rows, byKey
	return panel
end

local function UpdateRows(rows, db)
	for _, row in ipairs(rows) do
		if row.UpdateControl then
			local enabled = not row.enabledIf or row.enabledIf(db) == true
			row:UpdateControl(db, enabled)
			SetColor(row.label, enabled and NORMAL_COLOR or DISABLED_COLOR)
			row:DesaturateHierarchy(enabled and 0 or 1)
		end
	end
end

-- Shows the saved settings, and greys out the options that have no effect right now.
function Options:Refresh()
	if not (self.rows and ns.db) then
		return
	end
	refreshing = true
	local ok, err = pcall(UpdateRows, self.rows, ns.db)
	refreshing = false
	if not ok then
		error(err, 0)
	end
end

function Options:Open()
	if not (self.category and Settings and Settings.OpenToCategory) then
		return false
	end
	Settings.OpenToCategory(self.category:GetID())
	return true
end

function Options:Init()
	if self.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local panel = self:Build()
	-- The Settings panel calls these: OnRefresh whenever it shows the page, OnDefault for "Defaults" > "All Settings".
	function panel.OnRefresh()
		Options:Refresh()
	end
	function panel.OnDefault()
		ns:ResetSettings()
	end
	local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
	Settings.RegisterAddOnCategory(category)
	self.category = category
	self:Refresh()
end
