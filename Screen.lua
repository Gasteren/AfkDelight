--[[
	AfkDelight - Screen.lua
	By Frost-Lightbringer
	License: http://creativecommons.org/licenses/by-nc-sa/2.5
	LegalCode: http://creativecommons.org/licenses/by-nc-sa/2.5/legalcode

	Builds and animates the AFK screen:
	  backdrop -> stars -> spinning Azeroth -> shading -> character -> texts, messages and Close button
]]

local _, ns = ...
local L = ns.L

local Screen = {}
ns.Screen = Screen

local _G = _G
local issecretvalue = ns.issecretvalue
local ipairs, pcall, type = ipairs, pcall, type
local tremove = table.remove
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local rad, sin, cos, pi = math.rad, math.sin, math.cos, math.pi
local random = math.random
local format, strlower = string.format, string.lower
local date = date
local GetTime = GetTime

-- Azeroth, painted with environments/stars/moon.blp: Retail ships it at 512x512, WoW Forever a remastered
-- 2048x2048 version. Positions are fractions of the screen, sizes of the screen height. She turns
-- counter-clockwise, the way the Maelstrom's spiral arms trail, so the whirlpool looks like it is spinning.
local BODIES = {
	{ -- Azeroth (oceans, continents and the Maelstrom)
		texture = 130561, x = 0.42, y = 0.5, size = 0.42, drift = 8,
		turn = 120, -- seconds per turn
	},
}
-- Faint coloured stars from the game's own night sky (starrynight.blp), tiled across the screen.
local STAR_DUST_TEXTURE = 130627
local STAR_DUST_TILE = 512

local MAX_MESSAGES = 200

local FADE_IN_TIME = 1.0
local FADE_OUT_TIME = 0.6
local CAMERA_SPIN_SPEED = 0.035
local MODEL_SPIN_SPEED = 0.3 -- radians per second
local NUM_STARS = 170
local NUM_SPARKLES = 12

local ANIMATION = {
	STAND = 0,
	TALK = 60,
	BOW = 66,
	WAVE = 67,
	CHEER = 68,
	DANCE = 69,
	LAUGH = 70,
	APPLAUD = 80,
	FLEX = 82,
	SHY = 83,
	SALUTE = 113,
}
local RANDOM_EMOTES = {
	ANIMATION.TALK, ANIMATION.BOW, ANIMATION.CHEER, ANIMATION.DANCE, ANIMATION.LAUGH,
	ANIMATION.APPLAUD, ANIMATION.FLEX, ANIMATION.SHY, ANIMATION.SALUTE,
}

local STAR_TINTS = {
	{ 1, 1, 1 },
	{ 0.78, 0.86, 1 },
	{ 1, 0.94, 0.82 },
	{ 0.86, 0.8, 1 },
}

local CATEGORIES = { "WHISPERS", "GUILD", "GROUP" }
local CATEGORY_OPTION = { GUILD = "chatGuild", GROUP = "chatGroup" }
local SCROLL_KEYS = {
	UP = "OLDER", DOWN = "NEWER", PAGEUP = "PAGE_OLDER", PAGEDOWN = "PAGE_NEWER", HOME = "OLDEST", END = "NEWEST",
}

local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- Decorative font for the title, only for the alphabets it covers.
local FANCY_FONT = FONT
do
	local locale = GetLocale()
	if locale == "ruRU" then
		FANCY_FONT = "Fonts\\MORPHEUS_CYR.TTF"
	elseif locale ~= "koKR" and locale ~= "zhCN" and locale ~= "zhTW" then
		FANCY_FONT = "Fonts\\MORPHEUS.TTF"
	end
end

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

local function SetFont(fontString, size, fancy)
	if fancy and fontString:SetFont(FANCY_FONT, size, "") ~= false and fontString:GetFont() then
		return
	end
	fontString:SetFont(FONT, size, "")
end

local function CreateText(parent, size, fancy)
	local text = parent:CreateFontString(nil, "OVERLAY")
	SetFont(text, size, fancy)
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.9)
	text:SetJustifyH("LEFT")
	text.lineHeight = size
	return text
end

local function SetLine(fontString, text)
	if type(text) == "string" and text ~= "" then
		fontString:SetText(text)
		fontString:Show()
	else
		fontString:SetText("")
		fontString:Hide()
	end
end

-- A full-width or full-height colour wash that fades from startAlpha to endAlpha.
local function CreateShade(parent, orientation, startAlpha, endAlpha, r, g, b, subLevel)
	r, g, b = r or 0, g or 0, b or 0
	local texture = parent:CreateTexture(nil, "BACKGROUND", nil, subLevel or 0)
	if texture.SetGradient and CreateColor then
		texture:SetColorTexture(1, 1, 1, 1)
		texture:SetGradient(orientation, CreateColor(r, g, b, startAlpha), CreateColor(r, g, b, endAlpha))
	else
		texture:SetColorTexture(r, g, b, (startAlpha + endAlpha) / 2)
	end
	return texture
end

local function ClassColored(text, classFile)
	local color = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))
		or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile])
	if color and color.WrapTextInColorCode then
		return color:WrapTextInColorCode(text)
	end
	return text
end

local function ModelIsLoaded(model)
	local ok, fileID = pcall(model.GetModelFileID, model)
	if not ok or issecretvalue(fileID) then
		return false
	end
	return type(fileID) == "number" and fileID > 0
end

local function HasAnimation(model, animation)
	if not model.HasAnimation then
		return true
	end
	local ok, hasAnimation = pcall(model.HasAnimation, model, animation)
	return ok and not issecretvalue(hasAnimation) and hasAnimation == true
end

------------------------------------------------------------------------
-- Input: only Escape and the Close button close the screen
------------------------------------------------------------------------

local function SetPropagateKeyboard(frame, propagate)
	-- Restricted for addons during combat; the screen never stays up in combat anyway.
	if frame.SetPropagateKeyboardInput and not InCombatLockdown() then
		frame:SetPropagateKeyboardInput(propagate)
	end
end

local function IsScreenshotKey(key)
	if key == "PRINTSCREEN" then
		return true
	end
	if GetBindingByKey then
		local action = GetBindingByKey(key)
		return not issecretvalue(action) and action == "SCREENSHOT"
	end
	return false
end

local function OnKeyDown(frame, key)
	if key == "ESCAPE" then
		SetPropagateKeyboard(frame, false)
		ns:Dismiss()
		return
	end
	if IsScreenshotKey(key) then
		-- Let the game take the screenshot.
		SetPropagateKeyboard(frame, true)
		return
	end
	-- Everything else stays on the AFK screen, so reading messages can't close it by accident.
	SetPropagateKeyboard(frame, false)
	if key == "TAB" then
		Screen:CycleTab(IsShiftKeyDown() and -1 or 1)
	elseif SCROLL_KEYS[key] then
		Screen:ScrollMessages(SCROLL_KEYS[key])
	end
end

local function OnMouseWheel(_, delta)
	if IsShiftKeyDown() then
		Screen:ScrollMessages(delta > 0 and "OLDEST" or "NEWEST")
	else
		Screen:ScrollMessages(delta > 0 and "OLDER" or "NEWER")
	end
end

local function OnHide()
	-- Hidden from the outside (e.g. the whole UI was hidden): treat it as a dismissal,
	-- and finish an interrupted fade-out right away since OnUpdate stops while hidden.
	if Screen.active then
		ns:Dismiss(true)
	elseif Screen.alpha > 0 then
		Screen:Finish()
	end
end

local function OnUpdate(_, elapsed)
	Screen:OnUpdate(elapsed)
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

function Screen:Create()
	if self.frame then
		return
	end

	local frame = CreateFrame("Frame", "AfkDelightFrame", UIParent)
	frame:SetFrameStrata("FULLSCREEN")
	frame:SetAllPoints(UIParent)
	frame:SetAlpha(0)
	frame:Hide()
	-- Lets the "Game world" background fade out the rest of the UI without fading this frame.
	if frame.SetIgnoreParentAlpha then
		frame:SetIgnoreParentAlpha(true)
	end
	self.frame = frame
	self.alpha = 0
	self.targetAlpha = 0
	local level = frame:GetFrameLevel()

	local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	backdrop:SetAllPoints()
	backdrop:SetColorTexture(0, 0, 0, 1)
	self.backdrop = backdrop

	local starfield = CreateFrame("Frame", nil, frame)
	starfield:SetAllPoints()
	starfield:SetFrameLevel(level + 1)
	self.starfield = starfield
	self:CreateStarfield()

	local sky = CreateFrame("Frame", nil, frame)
	sky:SetAllPoints()
	sky:SetFrameLevel(level + 2)
	sky:Hide()
	self.sky = sky
	self.bodies = {}
	for index, definition in ipairs(BODIES) do
		self.bodies[index] = self:CreateBody(definition)
	end

	local shade = CreateFrame("Frame", nil, frame)
	shade:SetAllPoints()
	shade:SetFrameLevel(level + 7)
	self.shadeBottom = CreateShade(shade, "VERTICAL", 0.95, 0)
	self.shadeBottom:SetPoint("BOTTOMLEFT")
	self.shadeBottom:SetPoint("BOTTOMRIGHT")
	self.shadeTop = CreateShade(shade, "VERTICAL", 0, 0.6)
	self.shadeTop:SetPoint("TOPLEFT")
	self.shadeTop:SetPoint("TOPRIGHT")
	self.shadeLeft = CreateShade(shade, "HORIZONTAL", 0.6, 0)
	self.shadeLeft:SetPoint("TOPLEFT")
	self.shadeLeft:SetPoint("BOTTOMLEFT")
	self.shadeRight = CreateShade(shade, "HORIZONTAL", 0, 0.45)
	self.shadeRight:SetPoint("TOPRIGHT")
	self.shadeRight:SetPoint("BOTTOMRIGHT")

	local model = CreateFrame("PlayerModel", nil, frame)
	model:SetFrameLevel(level + 8)
	if model.HasScript and model:HasScript("OnModelLoaded") then
		model:SetScript("OnModelLoaded", function()
			Screen:OnCharacterLoaded()
		end)
	end
	self.model = model

	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(level + 10)
	self.overlay = overlay
	self:CreateInfo(overlay)
	self:CreateClock(overlay)
	self:CreateChat(overlay)
	self:CreateHint(overlay)
	self:CreateCloseButton(overlay)

	frame:SetScript("OnKeyDown", OnKeyDown)
	frame:SetScript("OnMouseWheel", OnMouseWheel)
	frame:SetScript("OnHide", OnHide)
	frame:SetScript("OnUpdate", OnUpdate)
	frame:SetScript("OnSizeChanged", function()
		Screen:Layout()
	end)

	self:Layout()
end

function Screen:CreateStarfield()
	local parent = self.starfield
	self.stars = {}

	-- Faint colour washes so empty space isn't flat black.
	self.glowLow = CreateShade(parent, "VERTICAL", 0.4, 0, 0.12, 0.06, 0.28, 1)
	self.glowLow:SetPoint("BOTTOMLEFT")
	self.glowLow:SetPoint("BOTTOMRIGHT")
	self.glowSide = CreateShade(parent, "HORIZONTAL", 0.3, 0, 0.04, 0.1, 0.26, 1)
	self.glowSide:SetPoint("TOPLEFT")
	self.glowSide:SetPoint("BOTTOMLEFT")

	local dust = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
	dust:SetAllPoints()
	dust:SetTexture(STAR_DUST_TEXTURE, "REPEAT", "REPEAT")
	dust:SetBlendMode("ADD")
	dust:SetAlpha(0.8)
	self.starDust = dust

	for i = 1, NUM_STARS do
		local star = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
		local tint = STAR_TINTS[random(#STAR_TINTS)]
		star:SetColorTexture(tint[1], tint[2], tint[3], 1)
		local size = (random() < 0.85) and (1 + random() * 1.2) or (2.2 + random() * 1.3)
		star:SetSize(size, size)
		star.fx, star.fy = random(), random()
		local brightness = 0.3 + random() * 0.6
		star:SetAlpha(brightness)

		local twinkle = star:CreateAnimationGroup()
		twinkle:SetLooping("BOUNCE")
		local fade = twinkle:CreateAnimation("Alpha")
		fade:SetFromAlpha(brightness)
		fade:SetToAlpha(brightness * (0.15 + random() * 0.4))
		fade:SetDuration(1.5 + random() * 3.5)
		fade:SetStartDelay(random() * 4)
		fade:SetSmoothing("IN_OUT")
		star.twinkle = twinkle
		self.stars[i] = star
	end

	for _ = 1, NUM_SPARKLES do
		local sparkle = parent:CreateTexture(nil, "BACKGROUND", nil, 3)
		sparkle:SetTexture("Interface\\Cooldown\\star4")
		sparkle:SetBlendMode("ADD")
		local tint = STAR_TINTS[random(#STAR_TINTS)]
		sparkle:SetVertexColor(tint[1], tint[2], tint[3])
		local size = 12 + random() * 16
		sparkle:SetSize(size, size)
		sparkle.fx, sparkle.fy = random(), random()
		sparkle:SetAlpha(0.2)

		local twinkle = sparkle:CreateAnimationGroup()
		twinkle:SetLooping("BOUNCE")
		local fade = twinkle:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.1)
		fade:SetToAlpha(0.55 + random() * 0.35)
		fade:SetDuration(2 + random() * 3)
		fade:SetStartDelay(random() * 5)
		fade:SetSmoothing("IN_OUT")
		sparkle.twinkle = twinkle
		self.stars[#self.stars + 1] = sparkle
	end

	-- A reusable shooting star, drawn as a line between its tail and head.
	if parent.CreateLine then
		local streak = parent:CreateLine(nil, "BACKGROUND", nil, 4)
		streak:SetColorTexture(1, 1, 1, 1)
		streak:SetThickness(1.5)
		if streak.SetGradient and CreateColor then
			pcall(streak.SetGradient, streak, "HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.9))
		end
		streak:Hide()
		self.streak = streak
		self.streakState = {}
		self.nextStreak = 4 + random() * 6
	end
end

-- A body in the night sky. Its texture already has a transparent edge and a soft rim, so no mask is needed,
-- even while it turns.
function Screen:CreateBody(definition)
	local body = CreateFrame("Frame", nil, self.sky)
	body.definition = definition

	local surface = body:CreateTexture(nil, "ARTWORK", nil, 0)
	surface:SetAllPoints()
	surface:SetTexture(definition.texture)
	body.surface = surface

	if definition.turn then
		local spin = surface:CreateAnimationGroup()
		spin:SetLooping("REPEAT")
		local turn = spin:CreateAnimation("Rotation")
		turn:SetOrigin("CENTER", 0, 0)
		turn:SetDegrees(360) -- positive is counter-clockwise
		turn:SetDuration(definition.turn)
		body.spin = spin
	end
	return body
end

function Screen:CreateInfo(parent)
	local info = CreateFrame("Frame", nil, parent)
	info:SetSize(1, 1)
	self.info = info

	self.title = CreateText(info, 46, true)
	self.reason = CreateText(info, 18)
	self.reason:SetTextColor(0.65, 0.85, 1)
	self.timer = CreateText(info, 24)
	self.timer:SetTextColor(1, 0.82, 0)

	self.classIcon = info:CreateTexture(nil, "ARTWORK")
	self.classIcon:SetSize(44, 44)
	self.classIcon:Hide()

	self.name = CreateText(info, 30)
	self.subtitle = CreateText(info, 15)
	self.subtitle:SetTextColor(1, 0.82, 0)
	self.details = CreateText(info, 15)
	self.details:SetTextColor(0.92, 0.92, 0.92)
	self.guild = CreateText(info, 15)
	self.guild:SetTextColor(0.25, 1, 0.25)
	self.itemLevel = CreateText(info, 14)
	self.itemLevel:SetTextColor(0.75, 0.75, 0.75)
	self.zone = CreateText(info, 14)
	self.zone:SetTextColor(0.75, 0.75, 0.75)
	self.progress = CreateText(info, 14)
	self.progress:SetTextColor(0.55, 0.65, 1)

	self.classIcon:SetPoint("RIGHT", self.name, "LEFT", -10, 0)
end

function Screen:CreateClock(parent)
	self.clock = CreateText(parent, 56)
	self.clock:SetJustifyH("CENTER")
	self.clock:SetPoint("TOP", self.frame, "TOP", 0, -36)
	self.date = CreateText(parent, 16)
	self.date:SetJustifyH("CENTER")
	self.date:SetTextColor(0.8, 0.8, 0.8)
	self.date:SetPoint("TOP", self.clock, "BOTTOM", 0, -4)
end

-- Messages received while away, one tab per kind of chat.
function Screen:CreateChat(parent)
	local chat = CreateFrame("Frame", nil, parent)
	chat:Hide()
	self.chat = chat
	chat.tabs, chat.messages, chat.history, chat.counts, chat.unread = {}, {}, {}, {}, {}

	chat.header = CreateText(chat, 16)
	chat.header:SetPoint("TOPLEFT")
	chat.header:SetTextColor(1, 0.82, 0)
	chat.header:SetText(L.CHAT_HEADER)

	local rule = CreateShade(chat, "HORIZONTAL", 0.6, 0, 1, 0.82, 0)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", chat, "TOPLEFT", 0, -52)
	rule:SetPoint("RIGHT", chat, "RIGHT")

	for _, category in ipairs(CATEGORIES) do
		local tab = CreateFrame("Button", nil, chat)
		tab:SetHeight(22)
		tab.category = category
		tab.label = CreateText(tab, 14)
		tab.label:SetPoint("LEFT", tab, "LEFT", 2, 1)
		tab.underline = tab:CreateTexture(nil, "ARTWORK")
		tab.underline:SetColorTexture(1, 0.82, 0, 1)
		tab.underline:SetHeight(2)
		tab.underline:SetPoint("BOTTOMLEFT")
		tab.underline:SetPoint("BOTTOMRIGHT")
		tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
		tab.highlight:SetAllPoints()
		tab.highlight:SetColorTexture(1, 1, 1, 0.08)
		tab:SetScript("OnClick", function(button)
			Screen:SelectTab(button.category)
		end)
		chat.tabs[category] = tab

		local messages = CreateFrame("ScrollingMessageFrame", nil, chat)
		messages:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -8)
		messages:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", 0, 18)
		if _G.ChatFontNormal then
			messages:SetFontObject(_G.ChatFontNormal)
		end
		messages:SetFont(FONT, 14, "")
		messages:SetShadowOffset(1, -1)
		messages:SetShadowColor(0, 0, 0, 1)
		messages:SetJustifyH("LEFT")
		messages:SetIndentedWordWrap(true)
		-- Oldest message at the top, right under the tabs; newer ones follow below it.
		messages:SetInsertMode(_G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP or 1)
		messages:SetMaxLines(MAX_MESSAGES)
		messages:SetFading(false)
		-- The screen itself handles the mouse wheel, so scrolling works anywhere on it.
		messages:EnableMouse(false)
		messages:Hide()
		chat.messages[category] = messages
		chat.history[category] = {}
		chat.counts[category] = 0
		chat.unread[category] = 0
	end

	chat.empty = CreateText(chat, 13)
	chat.empty:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -10)
	chat.empty:SetTextColor(0.6, 0.6, 0.6)

	chat.help = CreateText(chat, 11)
	chat.help:SetPoint("BOTTOMLEFT")
	chat.help:SetTextColor(0.5, 0.5, 0.5)
	chat.help:SetText(L.CHAT_HELP)

	self.selectedTab = "WHISPERS"
end

function Screen:CreateHint(parent)
	local hint = CreateText(parent, 14)
	hint:SetJustifyH("CENTER")
	hint:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 22)
	hint:SetTextColor(0.85, 0.85, 0.85)

	local pulse = hint:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.9)
	fade:SetToAlpha(0.3)
	fade:SetDuration(1.6)
	fade:SetSmoothing("IN_OUT")
	hint.pulse = pulse
	self.hint = hint
end

function Screen:CreateCloseButton(parent)
	local button = CreateFrame("Button", "AfkDelightCloseButton", parent, "UIPanelButtonTemplate")
	button:SetText(L.CLOSE)
	button:SetSize(max(96, (button:GetTextWidth() or 40) + 34), 26)
	button:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 10, 10)
	button:SetAlpha(0.8)
	button:HookScript("OnEnter", function(frame)
		frame:SetAlpha(1)
	end)
	button:HookScript("OnLeave", function(frame)
		frame:SetAlpha(0.8)
	end)
	button:HookScript("OnClick", function()
		ns:Dismiss()
	end)
	self.closeButton = button
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------

-- Places the visible lines bottom-up so hidden lines leave no gaps.
-- Each entry is { region, indent, spaceAbove }.
local function StackLines(anchor, lines)
	local y = 0
	for i = #lines, 1, -1 do
		local region, indent, spaceAbove = lines[i][1], lines[i][2], lines[i][3]
		if region:IsShown() then
			region:ClearAllPoints()
			region:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", indent, y)
			y = y + (region.lineHeight or 14) + spaceAbove
		end
	end
end

function Screen:Layout()
	local frame = self.frame
	if not frame then
		return
	end
	local width, height = frame:GetWidth(), frame:GetHeight()
	if issecretvalue(width) or issecretvalue(height) or not width or width <= 0 or not height or height <= 0 then
		width, height = UIParent:GetWidth(), UIParent:GetHeight()
	end
	self.width, self.height = width, height

	self.shadeBottom:SetHeight(height * 0.45)
	self.shadeTop:SetHeight(height * 0.2)
	self.shadeLeft:SetWidth(width * 0.14)
	self.shadeRight:SetWidth(width * 0.1)
	self.glowLow:SetHeight(height * 0.55)
	self.glowSide:SetWidth(width * 0.4)

	for _, star in ipairs(self.stars) do
		star:ClearAllPoints()
		star:SetPoint("CENTER", self.starfield, "BOTTOMLEFT", star.fx * width, star.fy * height)
	end
	self.starDust:SetTexCoord(0, width / STAR_DUST_TILE, 0, height / STAR_DUST_TILE)

	for _, body in ipairs(self.bodies) do
		local definition = body.definition
		local size = height * definition.size
		body:SetSize(size, size)
		body.baseX, body.baseY = width * definition.x, height * definition.y
		self:PlaceBody(body)
	end

	-- Same framing as the original AfkDelight: a large portrait rising from the bottom-right corner.
	local size = height * ((ns.db and ns.db.modelScale or 100) / 100)
	self.model:SetSize(size, size * 1.5)
	self.model:ClearAllPoints()
	self.model:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size * 0.25, -size * 0.5)

	local margin = max(30, height * 0.05)
	self.info:ClearAllPoints()
	self.info:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", margin, max(56, height * 0.09))

	self.chat:ClearAllPoints()
	self.chat:SetPoint("TOPLEFT", frame, "TOPLEFT", margin, -margin)
	self.chat:SetSize(min(560, width * 0.36), min(280, height * 0.32))

	self:LayoutInfo()
end

-- Azeroth drifts a little over time, so the sky never looks frozen.
function Screen:PlaceBody(body)
	local time = self.skyTime or 0
	local drift = body.definition.drift
	body:ClearAllPoints()
	body:SetPoint("CENTER", self.sky, "BOTTOMLEFT", body.baseX + sin(time / 240) * drift, body.baseY + (1 - cos(time / 240)) * drift * 0.5)
end

function Screen:LayoutInfo()
	local indent = self.classIcon:IsShown() and 56 or 0
	StackLines(self.info, {
		{ self.title, 0, 0 },
		{ self.reason, 2, 2 },
		{ self.timer, 2, 4 },
		{ self.name, indent, 28 },
		{ self.subtitle, indent, 2 },
		{ self.details, indent, 4 },
		{ self.guild, indent, 3 },
		{ self.itemLevel, indent, 3 },
		{ self.zone, indent, 3 },
		{ self.progress, indent, 3 },
	})
end

------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------

function Screen:UpdateInfo()
	local showCharacter = ns.db.showInfo

	self.title:SetText(L.AWAY_TITLE)
	self:SetReason(not self.preview and ns.session and ns.session.reason or nil)

	local color, classFile = ns:GetClassColor()
	SetLine(self.name, showCharacter and ns:GetPlayerName() or nil)
	if color then
		self.name:SetTextColor(color.r, color.g, color.b)
	else
		self.name:SetTextColor(1, 1, 1)
	end

	local atlas = showCharacter and classFile and ("classicon-" .. strlower(classFile))
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		self.classIcon:SetAtlas(atlas)
		self.classIcon:Show()
	else
		self.classIcon:Hide()
	end

	SetLine(self.subtitle, showCharacter and ns:GetPlayerTitle() or nil)
	SetLine(self.details, showCharacter and ns:GetLevelLine() or nil)
	SetLine(self.guild, showCharacter and ns:GetGuildLine() or nil)
	local itemLevel = showCharacter and ns:GetItemLevel()
	SetLine(self.itemLevel, itemLevel and format("%s %d", L.ITEM_LEVEL, itemLevel) or nil)
	SetLine(self.zone, showCharacter and ns:GetZoneLine() or nil)
	self:UpdateProgress()
	self:LayoutInfo()
end

function Screen:UpdateProgress()
	local text
	if ns.db.showInfo then
		local xp, rested = ns:GetLevelProgress()
		if xp then
			text = format(L.XP_LINE, floor(xp))
			if rested and rested > 0 then
				text = text .. "     " .. format(L.RESTED_LINE, floor(rested + 0.5))
				local startRested = not self.preview and ns.session and ns.session.startRested
				if startRested and rested - startRested >= 1 then
					text = text .. "  (" .. format(L.RESTED_GAIN, floor(rested - startRested + 0.5)) .. ")"
				end
			end
			if IsResting then
				local resting = IsResting()
				if not issecretvalue(resting) and not resting then
					text = text .. "     |cff999999" .. L.NOT_RESTING .. "|r"
				end
			end
		end
	end
	SetLine(self.progress, text)
end

function Screen:SetReason(reason)
	if not self.reason then
		return
	end
	if type(reason) == "string" and reason ~= "" then
		self.reason:SetText("\"" .. reason .. "\"")
		self.reason:Show()
	else
		self.reason:Hide()
	end
	self:LayoutInfo()
end

function Screen:UpdateTimer()
	self.timer:SetText(format(L.AWAY_FOR, ns.FormatClock(GetTime() - (self.startTime or GetTime()))))
end

function Screen:UpdateClock()
	if not ns.db.showClock then
		self.clock:Hide()
		self.date:Hide()
		return
	end
	self.clock:Show()
	self.date:Show()

	local timeText = _G.GameTime_GetTime and _G.GameTime_GetTime(true)
	self.clock:SetText(type(timeText) == "string" and timeText or date("%H:%M"))

	local now = date("*t")
	local weekday = _G.CALENDAR_WEEKDAY_NAMES and _G.CALENDAR_WEEKDAY_NAMES[now.wday]
	local month = _G.CALENDAR_FULLDATE_MONTH_NAMES and _G.CALENDAR_FULLDATE_MONTH_NAMES[now.month]
	local dateText
	if weekday and month and _G.FULLDATE_NO_YEAR then
		local ok, text = pcall(format, _G.FULLDATE_NO_YEAR, weekday, month, now.day)
		dateText = ok and text or nil
	end
	self.date:SetText(dateText or date("%A, %B %d"))
end

function Screen:UpdateHint()
	self.hint:SetText(self.preview and L.HINT_PREVIEW or L.HINT_CLOSE)
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------

function Screen:IsTabVisible(category)
	local option = CATEGORY_OPTION[category]
	return not option or ns.db[option] == true
end

-- Opens the first tab with unread messages, so missed whispers come first.
function Screen:ChooseTab()
	for _, category in ipairs(CATEGORIES) do
		if self:IsTabVisible(category) and self.chat.unread[category] > 0 then
			return category
		end
	end
	return "WHISPERS"
end

function Screen:SelectTab(category)
	if not self.chat then
		return
	end
	if not self:IsTabVisible(category) then
		category = "WHISPERS"
	end
	self.selectedTab = category
	self.chat.unread[category] = 0
	self:UpdateChat()
end

function Screen:CycleTab(direction)
	if not (self.chat and self.chat:IsShown()) then
		return
	end
	local visible, current = {}, 1
	for _, category in ipairs(CATEGORIES) do
		if self:IsTabVisible(category) then
			visible[#visible + 1] = category
			if category == self.selectedTab then
				current = #visible
			end
		end
	end
	self:SelectTab(visible[(current - 1 + direction) % #visible + 1])
end

-- The list starts with the oldest message (insert mode TOP), so a larger scroll offset shows newer messages.
function Screen:ScrollMessages(action)
	if not (self.chat and self.chat:IsShown()) then
		return
	end
	local messages = self.chat.messages[self.selectedTab]
	if not messages then
		return
	end
	if action == "OLDER" then
		messages:ScrollDown()
	elseif action == "NEWER" then
		messages:ScrollUp()
	elseif action == "PAGE_OLDER" then
		messages:PageDown()
	elseif action == "PAGE_NEWER" then
		messages:PageUp()
	elseif action == "OLDEST" then
		messages:ScrollToBottom()
	elseif action == "NEWEST" then
		-- Scroll so the newest messages fill the panel, rather than leaving just the last one at the top.
		local lines = messages:GetNumVisibleLines()
		local page = max(1, (type(lines) == "number" and lines or 0) - 2)
		messages:SetScrollOffset(max(0, messages:GetNumMessages() - page))
	end
end

function Screen:ResetMessages()
	local chat = self.chat
	if not chat then
		return
	end
	for _, category in ipairs(CATEGORIES) do
		chat.messages[category]:Clear()
		chat.history[category] = {}
		chat.counts[category], chat.unread[category] = 0, 0
	end
	self.selectedTab = "WHISPERS"
	self:UpdateChat()
end

-- Rebuilds a tab from its history, oldest first. Used once a tab holds more than MAX_MESSAGES.
function Screen:RefillMessages(category)
	local messages = self.chat.messages[category]
	local offset = messages:GetScrollOffset()
	messages:Clear()
	for _, entry in ipairs(self.chat.history[category]) do
		messages:BackFillMessage(entry[1], entry[2], entry[3], entry[4])
	end
	-- The oldest line is gone, so step back one line to keep the same messages in view.
	messages:SetScrollOffset(max(0, (type(offset) == "number" and offset or 0) - 1))
end

function Screen:AddMessage(category, text, r, g, b)
	local chat = self.chat
	if not (chat and chat.messages[category]) then
		return
	end
	local stamp = _G.GameTime_GetLocalTime and _G.GameTime_GetLocalTime(false)
	if type(stamp) ~= "string" then
		stamp = date("%H:%M")
	end
	local line = "|cff808080" .. stamp .. "|r  " .. text
	local history = chat.history[category]
	history[#history + 1] = { line, r, g, b }
	if #history > MAX_MESSAGES then
		tremove(history, 1)
		self:RefillMessages(category)
	else
		-- BackFillMessage appends after the older lines, so reading goes top to bottom like a letter.
		chat.messages[category]:BackFillMessage(line, r, g, b)
	end
	chat.counts[category] = chat.counts[category] + 1
	if category ~= self.selectedTab or not self.active then
		chat.unread[category] = chat.unread[category] + 1
	end
	self:UpdateChat()
end

function Screen:UpdateChat()
	local chat = self.chat
	chat:SetShown(ns.db.showChat == true)
	if not self:IsTabVisible(self.selectedTab) then
		self.selectedTab = "WHISPERS"
	end

	local previous
	for _, category in ipairs(CATEGORIES) do
		local tab = chat.tabs[category]
		local selected = category == self.selectedTab
		if self:IsTabVisible(category) then
			tab.label:SetText(format(L.TAB_FORMAT, L["TAB_" .. category], chat.counts[category]))
			if selected then
				tab.label:SetTextColor(1, 1, 1)
			elseif chat.unread[category] > 0 then
				tab.label:SetTextColor(1, 0.82, 0)
			else
				tab.label:SetTextColor(0.6, 0.6, 0.6)
			end
			tab.underline:SetShown(selected)
			tab:SetWidth((tab.label:GetStringWidth() or 60) + 6)
			tab:ClearAllPoints()
			if previous then
				tab:SetPoint("LEFT", previous, "RIGHT", 18, 0)
			else
				tab:SetPoint("TOPLEFT", chat.header, "BOTTOMLEFT", 0, -6)
			end
			tab:Show()
			previous = tab
		else
			tab:Hide()
		end
		chat.messages[category]:SetShown(selected)
	end

	chat.empty:SetText(L["EMPTY_" .. self.selectedTab])
	chat.empty:SetShown(chat.counts[self.selectedTab] == 0)
end

function Screen:AddSampleMessages()
	local info = _G.ChatTypeInfo or {}
	local function Sample(category, chatType, formatString, name, classFile, text)
		local ok, prefix = pcall(format, formatString, "[" .. ClassColored(name, classFile) .. "]")
		local color = info[chatType] or { r = 1, g = 1, b = 1 }
		self:AddMessage(category, (ok and prefix or "") .. text, color.r or 1, color.g or 1, color.b or 1)
	end
	Sample("WHISPERS", "WHISPER", _G.CHAT_WHISPER_GET or "%s whispers: ", L.SAMPLE_NAME_1, "MAGE", L.SAMPLE_WHISPER)
	Sample("GUILD", "GUILD", _G.CHAT_GUILD_GET or "[Guild] %s: ", L.SAMPLE_NAME_2, "SHAMAN", L.SAMPLE_GUILD)
	Sample("GROUP", "PARTY", _G.CHAT_PARTY_GET or "[Party] %s: ", L.SAMPLE_NAME_3, "PALADIN", L.SAMPLE_GROUP)
end

------------------------------------------------------------------------
-- Backgrounds
------------------------------------------------------------------------

function Screen:SetStarsAnimating(animating)
	if self.starsAnimating == animating then
		return
	end
	self.starsAnimating = animating
	for _, star in ipairs(self.stars) do
		if animating then
			star.twinkle:Play()
		else
			star.twinkle:Stop()
		end
	end
	if not animating and self.streak then
		self.streak:Hide()
		self.streakActive = false
	end
end

function Screen:SetSkyShown(shown)
	if self.skyShown == shown then
		return
	end
	self.skyShown = shown
	self.sky:SetShown(shown)
	for _, body in ipairs(self.bodies) do
		if body.spin then
			if shown then
				body.spin:Play()
			else
				body.spin:Stop()
			end
		end
	end
end

function Screen:ApplyBackground()
	local mode = ns.db.background

	self.backdrop:SetColorTexture(0, 0, 0, mode == "WORLD" and (ns.db.worldDim / 100) or 1)
	local stars = mode == "AZEROTH" or mode == "STARFIELD"
	self.starfield:SetShown(stars)
	self:SetStarsAnimating(stars)
	self:SetSkyShown(mode == "AZEROTH")

	if mode == "WORLD" then
		self:BeginWorldMode()
	else
		self:EndWorldMode()
	end
end

function Screen:BeginWorldMode()
	if not self.uiFaded then
		local alpha = UIParent:GetAlpha()
		self.savedUIAlpha = (not issecretvalue(alpha) and type(alpha) == "number") and alpha or 1
		self.uiFaded = true
	end
	if ns.db.cameraSpin then
		self:StartCameraSpin()
	else
		self:StopCameraSpin()
	end
end

function Screen:EndWorldMode()
	if self.uiFaded then
		self.uiFaded = false
		UIParent:SetAlpha(self.savedUIAlpha or 1)
	end
	self:StopCameraSpin()
end

function Screen:StartCameraSpin()
	if self.spinning or not _G.MoveViewLeftStart then
		return
	end
	if pcall(_G.MoveViewLeftStart, CAMERA_SPIN_SPEED) then
		self.spinning = true
		ns.db.cameraSpinActive = true
	end
end

function Screen:StopCameraSpin(force)
	if (self.spinning or force) and _G.MoveViewLeftStop then
		pcall(_G.MoveViewLeftStop)
	end
	self.spinning = false
	if ns.db then
		ns.db.cameraSpinActive = false
	end
end

function Screen:UpdateStreak(elapsed)
	local streak = self.streak
	if not streak or not self.starsAnimating then
		return
	end
	local state = self.streakState
	if not self.streakActive then
		self.nextStreak = self.nextStreak - elapsed
		if self.nextStreak > 0 then
			return
		end
		local angle = rad(200 + random() * 25) -- heading down and to the left
		state.x = self.width * (0.35 + random() * 0.6)
		state.y = self.height * (0.6 + random() * 0.35)
		state.dx, state.dy = cos(angle), sin(angle)
		state.distance = 250 + random() * 250
		state.length = 90 + random() * 60
		state.duration = 0.7 + random() * 0.5
		state.time = 0
		self.streakActive = true
		streak:Show()
	end

	state.time = state.time + elapsed
	local progress = state.time / state.duration
	if progress >= 1 then
		streak:Hide()
		self.streakActive = false
		self.nextStreak = 6 + random() * 10
		return
	end
	local travelled = state.distance * progress
	local headX, headY = state.x + state.dx * travelled, state.y + state.dy * travelled
	local tail = min(state.length, travelled)
	streak:SetStartPoint("BOTTOMLEFT", self.starfield, headX - state.dx * tail, headY - state.dy * tail)
	streak:SetEndPoint("BOTTOMLEFT", self.starfield, headX, headY)
	streak:SetAlpha(sin(progress * pi))
end

------------------------------------------------------------------------
-- Character model
------------------------------------------------------------------------

function Screen:RefreshCharacter()
	local model = self.model
	if not ns.db.showModel then
		model:Hide()
		self.animTimer = nil
		return
	end
	model:Show()
	self.characterLoaded = false
	model:SetUnit("player")
	self.facingTarget = rad(ns.db.modelFacing)
	-- Turn towards the viewer for the wave, then ease back into the chosen pose.
	self.facing = ns.db.introWave and rad(-15) or self.facingTarget
	self.appliedFacing = nil
	if ModelIsLoaded(model) then
		self.characterLoaded = true
	end
	self:StartAnimations()
end

function Screen:OnCharacterLoaded()
	self.characterLoaded = true
	self.appliedFacing = nil
	if self.active and self.currentAnimation then
		self:PlayAnimation(self.currentAnimation)
	end
end

function Screen:PlayAnimation(animation)
	if animation ~= ANIMATION.STAND and self.characterLoaded and not HasAnimation(self.model, animation) then
		animation = ANIMATION.STAND
	end
	self.currentAnimation = animation
	self.model:SetAnimation(animation)
end

function Screen:StartAnimations()
	if ns.db.introWave then
		self:PlayAnimation(ANIMATION.WAVE)
		self.animPhase, self.animTimer = "intro", 2.8
	else
		self:StartIdle()
	end
end

function Screen:StartIdle()
	local choice = ns.db.animation
	if choice == "RANDOM" then
		self:PlayAnimation(ANIMATION.STAND)
		self.animPhase, self.animTimer = "rest", 4 + random() * 6
	else
		self:PlayAnimation(ANIMATION[choice] or ANIMATION.STAND)
		self.animPhase, self.animTimer = "loop", nil
	end
end

function Screen:UpdateCharacter(elapsed)
	local model = self.model
	if not model:IsShown() then
		return
	end
	-- Not every client fires OnModelLoaded for unit models, so also notice the load here.
	if not self.characterLoaded and ModelIsLoaded(model) then
		self:OnCharacterLoaded()
	end

	if self.animTimer then
		self.animTimer = self.animTimer - elapsed
		if self.animTimer <= 0 then
			if self.animPhase == "intro" then
				self:StartIdle()
			elseif self.animPhase == "rest" then
				self:PlayAnimation(RANDOM_EMOTES[random(#RANDOM_EMOTES)])
				self.animPhase, self.animTimer = "emote", 3.5 + random() * 2.5
			else
				self:PlayAnimation(ANIMATION.STAND)
				self.animPhase, self.animTimer = "rest", 8 + random() * 10
			end
		end
	end

	if self.animPhase ~= "intro" then
		if ns.db.modelSpin then
			self.facing = (self.facing + elapsed * MODEL_SPIN_SPEED) % (2 * pi)
		else
			-- Shortest way round to the chosen facing.
			local diff = ((self.facingTarget - self.facing) + pi) % (2 * pi) - pi
			if abs(diff) > 0.001 then
				self.facing = self.facing + diff * min(1, elapsed * 2.5)
			end
		end
	end
	if self.facing ~= self.appliedFacing then
		self.appliedFacing = self.facing
		model:SetRotation(self.facing, false)
	end
end

------------------------------------------------------------------------
-- Showing and hiding
------------------------------------------------------------------------

function Screen:IsActive()
	return self.active == true
end

function Screen:SetInputEnabled(enabled)
	local frame = self.frame
	frame:EnableKeyboard(enabled)
	frame:EnableMouse(enabled)
	frame:EnableMouseWheel(enabled)
	if enabled then
		SetPropagateKeyboard(frame, false)
	end
end

function Screen:Show(isPreview)
	if not self.frame then
		self:Create()
	end
	-- Samples go in before the screen counts as open, so they all start out unread.
	if isPreview and not ns.session then
		self:ResetMessages()
		self:AddSampleMessages()
	end

	self.active = true
	self.preview = isPreview and true or false
	self.targetAlpha = 1
	self.startTime = (not isPreview and ns.session and ns.session.startTime) or GetTime()
	self.infoTick, self.clockTick = 0, 0

	self:ApplyBackground()
	self:Layout()
	self:UpdateInfo()
	self:UpdateTimer()
	self:UpdateClock()
	self:UpdateHint()
	self:SelectTab(self:ChooseTab())
	self:RefreshCharacter()
	self.hint.pulse:Play()

	self:SetInputEnabled(true)
	self.frame:Show()
end

-- Re-applies settings while the screen is up (e.g. after a change in the options panel).
function Screen:ApplySettings()
	if not self.active then
		return
	end
	self:ApplyBackground()
	self:Layout()
	self:UpdateInfo()
	self:UpdateClock()
	self:UpdateChat()
	self:UpdateHint()
	self:RefreshCharacter()
end

function Screen:Hide(instant)
	-- Nothing to do when the screen is already fully closed.
	if not self.frame or (not self.active and not self.frame:IsShown()) then
		return
	end
	self.active = false
	self.targetAlpha = 0
	-- Let clicks and keys reach the game again while the screen fades away.
	self:SetInputEnabled(false)
	if instant or not self.frame:IsShown() or self.alpha <= 0 then
		self:Finish()
	end
end

-- Final cleanup once the screen is fully hidden. Safe to call more than once.
function Screen:Finish()
	local frame = self.frame
	self.active = false
	self.preview = false
	self.alpha, self.targetAlpha = 0, 0
	frame:SetAlpha(0)
	frame:Hide()

	self:EndWorldMode()
	self:SetStarsAnimating(false)
	self:SetSkyShown(false)
	self.hint.pulse:Stop()
	self.animTimer, self.animPhase, self.currentAnimation = nil, nil, nil
	self.model:ClearModel()
end

function Screen:OnUpdate(elapsed)
	local alpha, target = self.alpha, self.targetAlpha
	if alpha ~= target then
		if target > alpha then
			alpha = min(target, alpha + elapsed / FADE_IN_TIME)
		else
			alpha = max(target, alpha - elapsed / FADE_OUT_TIME)
		end
		self.alpha = alpha
		local eased = alpha * alpha * (3 - 2 * alpha)
		self.frame:SetAlpha(eased)
		if self.uiFaded then
			UIParent:SetAlpha((self.savedUIAlpha or 1) * (1 - eased))
		end
		if alpha <= 0 and target <= 0 then
			self:Finish()
			return
		end
	end

	self.clockTick = (self.clockTick or 0) + elapsed
	if self.clockTick >= 1 then
		self.clockTick = 0
		self:UpdateTimer()
		self:UpdateClock()
		self.infoTick = (self.infoTick or 0) + 1
		if self.infoTick >= 10 then
			self.infoTick = 0
			self:UpdateInfo()
		end
	end

	if self.skyShown then
		self.skyTime = (self.skyTime or 0) + elapsed
		for _, body in ipairs(self.bodies) do
			self:PlaceBody(body)
		end
	end
	self:UpdateCharacter(elapsed)
	self:UpdateStreak(elapsed)
end
