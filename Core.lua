--[[
	AfkDelight - Core.lua
	By Frost-Lightbringer
	License: http://creativecommons.org/licenses/by-nc-sa/2.5
	LegalCode: http://creativecommons.org/licenses/by-nc-sa/2.5/legalcode

	Detects when you go AFK and drives the AFK screen (Screen.lua).

	World of Warcraft: Midnight and World of Warcraft: Forever hide some information
	from addons. Inside dungeons, raids, encounters, Mythic+ and PvP matches the
	game returns "secret values" for UnitIsAFK() and for every chat event. Every
	such read in this addon is checked with issecretvalue() first; while the AFK
	flag is hidden the screen simply stays closed instead of raising Lua errors.
]]

local ADDON_NAME, ns = ...
local L = ns.L

local _G = _G
local type, pairs, ipairs, select, pcall, tostring = type, pairs, ipairs, select, pcall, tostring
local floor, abs, min, max = math.floor, math.abs, math.min, math.max
local format, strlower = string.format, string.lower
local tconcat = table.concat
local GetTime = GetTime

-- Older clients don't have secret values at all, so everything is readable there.
local issecretvalue = _G.issecretvalue or function() return false end
ns.issecretvalue = issecretvalue

ns.title = "|cff00ccffAfkDelight|r"
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "1.0.0"

local tocVersion = select(4, GetBuildInfo()) or 0
ns.tocVersion = tocVersion
-- WoW Forever runs on the modern ("Mainline") client but reports its own 1.x interface number.
ns.isForever = (_G.WOW_PROJECT_CAMELOT ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CAMELOT)
	or (tocVersion >= 16000 and tocVersion < 20000)

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

ns.BACKGROUNDS = { "AZEROTH", "STARFIELD", "WORLD", "SOLID" }
ns.ANIMATIONS = { "RANDOM", "STAND", "DANCE", "TALK" }

local DB_VERSION = 4

ns.defaults = {
	enabled = true,
	delay = 0,
	disableInInstances = false,
	dismissOnPopups = true,
	showSummary = true,

	-- Azeroth, spinning over the stars, looks the same on Retail and WoW Forever.
	background = "AZEROTH",
	worldDim = 40,
	cameraSpin = true,
	showModel = true,
	animation = "RANDOM",
	introWave = true,
	modelFacing = -110,
	modelSpin = false,
	modelScale = 100,

	showInfo = true,
	showClock = true,
	showChat = true,
	chatGuild = true,
	chatGroup = true,
	flashOnWhisper = true,
}

ns.ranges = {
	delay = { 0, 300 },
	worldDim = { 0, 90 },
	modelFacing = { -180, 180 },
	modelScale = { 50, 150 },
}

local function Contains(list, value)
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end
	return false
end

function ns:InitDB()
	if type(_G.AfkDelightDB) ~= "table" then
		_G.AfkDelightDB = {}
	end
	local db = _G.AfkDelightDB
	local version = tonumber(db.dbVersion) or 0

	-- Settings version 2 (from the WoW Forever beta builds): the screen only closes with Escape or the Close button.
	if version < 2 then
		db.dismissOnInput = nil
	end
	-- Settings version 3: creature flybys were removed, and their setting with them.
	if version < 3 then
		db.dragonFlyby = nil
	end
	-- Settings version 4: the galaxy background was removed, and spinning Azeroth takes its place.
	if version < 4 and db.background == "GALAXY" then
		db.background = "AZEROTH"
	end

	for key, default in pairs(self.defaults) do
		if type(db[key]) ~= type(default) then
			db[key] = default
		end
	end
	for key, range in pairs(self.ranges) do
		db[key] = min(max(db[key], range[1]), range[2])
	end
	if not Contains(self.BACKGROUNDS, db.background) then
		db.background = self.defaults.background
	end
	if not Contains(self.ANIMATIONS, db.animation) then
		db.animation = self.defaults.animation
	end
	db.dbVersion = DB_VERSION

	self.db = db
end

-- Changes go through the Settings API when possible so the options panel stays in sync.
function ns:SetOption(key, value)
	if not (self.Options and self.Options:SetValue(key, value)) then
		self.db[key] = value
		self:OnSettingChanged(key)
	end
end

function ns:SetEnabled(enabled)
	self:SetOption("enabled", enabled)
	self:Print(enabled and L.MSG_ENABLED or L.MSG_DISABLED)
end

function ns:ResetSettings()
	for key, default in pairs(self.defaults) do
		self:SetOption(key, default)
	end
	self:Print(L.MSG_RESET)
end

function ns:OnSettingChanged(key)
	if not self.loggedIn then
		return
	end
	if key == "enabled" and not self.db.enabled and not self.preview then
		self.Screen:Hide()
	end
	self.Screen:ApplySettings()
	self:Evaluate()
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

function ns:Print(message, ...)
	if select("#", ...) > 0 then
		message = format(message, ...)
	end
	print(self.title .. ": " .. message)
end

-- Returns the value, or nil when it is missing or hidden from addons.
local function Readable(value)
	if value == nil or issecretvalue(value) then
		return nil
	end
	return value
end
ns.Readable = Readable

-- True when none of the values are secret.
function ns.CanRead(...)
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return false
		end
	end
	return true
end

-- Treats hidden values as "set", which is the safe answer for every check below.
local function IsSet(value)
	if issecretvalue(value) then
		return true
	end
	return value and true or false
end

local function IsShownSafe(frame)
	if not frame or not frame.IsShown then
		return false
	end
	return IsSet(frame:IsShown())
end

function ns.FormatClock(seconds)
	seconds = floor(max(seconds or 0, 0))
	local hours = floor(seconds / 3600)
	local minutes = floor(seconds % 3600 / 60)
	if hours > 0 then
		return format("%d:%02d:%02d", hours, minutes, seconds % 60)
	end
	return format("%02d:%02d", minutes, seconds % 60)
end

local function FormatDuration(seconds)
	seconds = floor(seconds)
	if _G.SecondsToTime then
		local ok, text = pcall(_G.SecondsToTime, seconds)
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
	end
	return ns.FormatClock(seconds)
end

local function FormatMoney(copper)
	if _G.GetMoneyString then
		local ok, text = pcall(_G.GetMoneyString, copper, true)
		if ok and type(text) == "string" then
			return text
		end
	end
	return format("%dg %ds %dc", floor(copper / 10000), floor(copper / 100) % 100, copper % 100)
end

------------------------------------------------------------------------
-- Timers
------------------------------------------------------------------------

local timers = {}

function ns.CancelTimer(name)
	local timer = timers[name]
	if timer then
		timer:Cancel()
		timers[name] = nil
	end
end

function ns.StartTimer(name, seconds, callback)
	ns.CancelTimer(name)
	local timer
	timer = C_Timer.NewTimer(seconds, function()
		if timers[name] == timer then
			timers[name] = nil
		end
		callback()
	end)
	timers[name] = timer
end

local function EvaluateLater()
	ns:Evaluate()
end

------------------------------------------------------------------------
-- Player information (used by the screen)
------------------------------------------------------------------------

function ns:GetPlayerName()
	local name = Readable((UnitName("player")))
	if not name then
		return self.cachedName or ""
	end
	-- WoW Forever characters can have a surname. Show it the same way the game's unit frames do.
	local NameUtil = _G.NameUtil
	if _G.RegionalUniqueNamesEnabled and NameUtil and _G.RegionalUniqueNamesEnabled() then
		local showSurname = C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname and C_PlayerInfo.ShouldDisplaySurname()
		local ok, formatted
		if showSurname and NameUtil.FormatUnitNameForDisplay then
			ok, formatted = pcall(NameUtil.FormatUnitNameForDisplay, "player", true)
		elseif NameUtil.GetUnitFirstName then
			ok, formatted = pcall(NameUtil.GetUnitFirstName, "player")
		end
		if ok and Readable(formatted) and type(formatted) == "string" and formatted ~= "" then
			name = formatted
		end
	end
	self.cachedName = name
	return name
end

function ns:GetPlayerTitle()
	if not (GetCurrentTitle and GetTitleName) then
		return nil
	end
	local titleID = Readable(GetCurrentTitle())
	if not titleID or titleID <= 0 then
		return nil
	end
	local title = Readable((GetTitleName(titleID)))
	if type(title) ~= "string" then
		return nil
	end
	title = strtrim(title):gsub("^,%s*", "")
	if title == "" then
		return nil
	end
	return title
end

function ns:GetClassColor()
	local _, classFile = UnitClass("player")
	classFile = Readable(classFile)
	if not classFile then
		return nil
	end
	local color = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))
		or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile])
	return color, classFile
end

function ns:GetLevelLine()
	local level = Readable(UnitLevel("player")) or 0
	local race = Readable((UnitRace("player"))) or ""
	local className = Readable((UnitClass("player"))) or ""
	if GetSpecialization and GetSpecializationInfo then
		local index = Readable(GetSpecialization())
		if index and index > 0 then
			local _, specName = GetSpecializationInfo(index)
			specName = Readable(specName)
			if specName and specName ~= "" and specName ~= className then
				className = specName .. " " .. className
			end
		end
	end
	return format("%s %d %s %s", L.LEVEL, level, race, className)
end

function ns:GetGuildLine()
	if not (IsInGuild and IsInGuild()) then
		return nil
	end
	local guildName, rankName = GetGuildInfo("player")
	guildName, rankName = Readable(guildName), Readable(rankName)
	if not guildName or guildName == "" then
		return nil
	end
	if rankName and rankName ~= "" then
		return format("<%s>  %s", guildName, rankName)
	end
	return format("<%s>", guildName)
end

function ns:GetItemLevel()
	if not GetAverageItemLevel then
		return nil
	end
	local _, equipped = GetAverageItemLevel()
	equipped = Readable(equipped)
	if equipped and equipped > 0 then
		return floor(equipped)
	end
	return nil
end

function ns:GetZoneLine()
	local zone = Readable(GetRealZoneText and GetRealZoneText() or GetZoneText())
	local subZone = Readable(GetSubZoneText and GetSubZoneText())
	if not zone or zone == "" then
		return nil
	end
	if subZone and subZone ~= "" and subZone ~= zone then
		return zone .. " - " .. subZone
	end
	return zone
end

function ns:IsMaxLevel()
	local level = Readable(UnitLevel("player")) or 0
	local maxLevel = GetMaxLevelForPlayerExpansion and Readable(GetMaxLevelForPlayerExpansion())
	return (maxLevel and maxLevel > 0 and level >= maxLevel) and true or false
end

-- Returns level progress and rested XP as percentages of the current level, or nil at max level.
function ns:GetLevelProgress()
	if self:IsMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then
		return nil
	end
	local xp, xpMax = Readable(UnitXP("player")), Readable(UnitXPMax("player"))
	if not xp or not xpMax or xpMax <= 0 then
		return nil
	end
	local rested = Readable(GetXPExhaustion and GetXPExhaustion()) or 0
	return xp / xpMax * 100, rested / xpMax * 100
end

------------------------------------------------------------------------
-- AFK state
------------------------------------------------------------------------

-- True while the game hides chat and AFK information from addons (Midnight / Forever).
function ns:IsRestricted()
	local inLockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
	if inLockdown then
		return IsSet(inLockdown())
	end
	return false
end

-- Returns true/false, or nil when the AFK flag can't be read right now.
function ns:ReadAFK()
	if self:IsRestricted() then
		return nil
	end
	local afk = UnitIsAFK("player")
	if issecretvalue(afk) then
		return nil
	end
	return afk and true or false
end

function ns:CanShowScreen()
	if InCombatLockdown() or IsSet(UnitAffectingCombat("player")) then
		return false
	end
	if self.db.disableInInstances and IsSet((IsInInstance())) then
		return false
	end
	if IsShownSafe(_G.CinematicFrame) or IsShownSafe(_G.MovieFrame) then
		return false, 5
	end
	if C_PetBattles and C_PetBattles.IsInBattle and IsSet(C_PetBattles.IsInBattle()) then
		return false, 10
	end
	-- Going AFK while crafting a long queue is common; wait until the casting is done.
	if IsSet((UnitCastingInfo("player"))) or IsSet((UnitChannelInfo("player"))) then
		return false, 10
	end
	return true
end

function ns:StartSession()
	local _, rested = self:GetLevelProgress()
	self.session = {
		startTime = GetTime(),
		startMoney = Readable(GetMoney()) or 0,
		startRested = rested,
		counts = { WHISPERS = 0, GUILD = 0, GROUP = 0 },
		reason = self:GetRecentAFKReason(),
	}
	self.Screen:ResetMessages()
	self:UpdateChatEvents()
	return self.session
end

function ns:EndSession()
	local session = self.session
	if not session then
		return
	end
	self.session = nil
	self.lastReason = nil
	self.CancelTimer("evaluate")
	self:UpdateChatEvents()
	if self.db.showSummary then
		self:PrintSummary(session)
	end
end

function ns:PrintSummary(session)
	local duration = GetTime() - session.startTime
	local counts = session.counts
	local missed = counts.WHISPERS + counts.GUILD + counts.GROUP
	if duration < 30 and missed == 0 then
		return
	end

	local parts = { format(L.SUMMARY, FormatDuration(duration)) }
	if missed > 0 then
		local kinds = {}
		if counts.WHISPERS > 0 then
			kinds[#kinds + 1] = format(L.MISSED_WHISPERS, counts.WHISPERS)
		end
		if counts.GUILD > 0 then
			kinds[#kinds + 1] = format(L.MISSED_GUILD, counts.GUILD)
		end
		if counts.GROUP > 0 then
			kinds[#kinds + 1] = format(L.MISSED_GROUP, counts.GROUP)
		end
		parts[#parts + 1] = format(L.SUMMARY_MISSED, tconcat(kinds, ", "))
	end
	local money = (Readable(GetMoney()) or session.startMoney) - session.startMoney
	if money ~= 0 then
		parts[#parts + 1] = format(L.SUMMARY_MONEY, (money > 0 and "+" or "-") .. FormatMoney(abs(money)))
	end
	local _, rested = self:GetLevelProgress()
	if rested and session.startRested and rested - session.startRested >= 1 then
		parts[#parts + 1] = format(L.SUMMARY_RESTED, floor(rested - session.startRested + 0.5))
	end
	self:Print(tconcat(parts, " "))
end

-- Central state machine: decides whether the screen should be up right now.
function ns:Evaluate()
	if not self.loggedIn then
		return
	end
	self.CancelTimer("evaluate")

	local afk = self:ReadAFK()
	if afk == nil then
		-- The AFK flag is hidden from addons here, so never leave the screen up blindly.
		if not self.preview then
			self.Screen:Hide(true)
		end
		return
	end

	if not afk then
		if self.session then
			self:EndSession()
		end
		if not self.preview then
			self.Screen:Hide()
		end
		return
	end

	local session = self.session or self:StartSession()
	if self.preview or session.dismissed or not self.db.enabled or self.Screen:IsActive() then
		return
	end

	local canShow, retryIn = self:CanShowScreen()
	if not canShow then
		if retryIn then
			self.StartTimer("evaluate", retryIn, EvaluateLater)
		end
		return
	end

	local remaining = self.db.delay - (GetTime() - session.startTime)
	if remaining > 0.1 then
		self.StartTimer("evaluate", remaining, EvaluateLater)
		return
	end

	self.Screen:Show(false)
end

-- Closes the screen. It stays closed until you leave AFK and go AFK again.
function ns:Dismiss(instant)
	self.preview = false
	if self.session then
		self.session.dismissed = true
	end
	self.CancelTimer("evaluate")
	self.Screen:Hide(instant)
end

function ns:TogglePreview()
	if not self.loggedIn then
		return
	end
	if self.Screen:IsActive() then
		self:Dismiss()
		return
	end
	if InCombatLockdown() then
		self:Print(L.MSG_COMBAT)
		return
	end
	self.preview = true
	self.Screen:Show(true)
end

------------------------------------------------------------------------
-- AFK message ("/afk Getting coffee")
------------------------------------------------------------------------

-- Turns a Blizzard format string like "You are now AFK: %s" into a Lua pattern.
local function FormatToPattern(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local pattern = text:gsub("%%%d*%$?s", "\001")
	pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	pattern = pattern:gsub("\001", "(.+)")
	return "^" .. pattern .. "$"
end

local AFK_MESSAGE_PATTERN = FormatToPattern(_G.MARKED_AFK_MESSAGE)

function ns:OnSystemMessage(text)
	if not AFK_MESSAGE_PATTERN or not ns.CanRead(text) or type(text) ~= "string" then
		return
	end
	local reason = text:match(AFK_MESSAGE_PATTERN)
	if not reason then
		return
	end
	if reason == _G.DEFAULT_AFK_MESSAGE then
		reason = nil
	end
	self.lastReason = reason
	self.lastReasonTime = GetTime()
	if self.session then
		self.session.reason = reason
		self.Screen:SetReason(reason)
	end
end

function ns:GetRecentAFKReason()
	if self.lastReasonTime and GetTime() - self.lastReasonTime < 5 then
		return self.lastReason
	end
	return nil
end

------------------------------------------------------------------------
-- Messages received while away
------------------------------------------------------------------------

local CHAT_EVENTS = {
	CHAT_MSG_WHISPER = "WHISPER",
	CHAT_MSG_BN_WHISPER = "BN_WHISPER",
	CHAT_MSG_GUILD = "GUILD",
	CHAT_MSG_OFFICER = "OFFICER",
	CHAT_MSG_PARTY = "PARTY",
	CHAT_MSG_PARTY_LEADER = "PARTY_LEADER",
	CHAT_MSG_RAID = "RAID",
	CHAT_MSG_RAID_LEADER = "RAID_LEADER",
	CHAT_MSG_RAID_WARNING = "RAID_WARNING",
	CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
	CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT_LEADER",
}

-- Which tab of the AFK screen each kind of chat goes to.
local CHAT_CATEGORIES = {
	WHISPER = "WHISPERS",
	BN_WHISPER = "WHISPERS",
	GUILD = "GUILD",
	OFFICER = "GUILD",
	PARTY = "GROUP",
	PARTY_LEADER = "GROUP",
	RAID = "GROUP",
	RAID_LEADER = "GROUP",
	RAID_WARNING = "GROUP",
	INSTANCE_CHAT = "GROUP",
	INSTANCE_CHAT_LEADER = "GROUP",
}

local CATEGORY_FILTERS = {
	GUILD = "chatGuild",
	GROUP = "chatGroup",
}

local GM_ICON = "|TInterface\\ChatFrame\\UI-ChatIcon-Blizz:12:20:0:0:32:16:4:28:0:16|t "

function ns:UpdateChatEvents()
	local active = self.session ~= nil
	if active == (self.chatEventsActive or false) then
		return
	end
	self.chatEventsActive = active
	for event in pairs(CHAT_EVENTS) do
		if active then
			self:RegisterEvent(event)
		else
			self:UnregisterEvent(event)
		end
	end
end

function ns:FormatSender(chatType, sender, guid)
	-- Battle.net names arrive as protected |K strings that only the game can display.
	if chatType == "BN_WHISPER" then
		return "[" .. sender .. "]"
	end
	local name = sender
	if Ambiguate then
		name = Ambiguate(sender, "none")
	end
	if type(guid) == "string" and guid ~= "" and GetPlayerInfoByGUID then
		local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
		classFile = ok and Readable(classFile)
		local color = classFile and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))
			or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]))
		if color and color.WrapTextInColorCode then
			name = color:WrapTextInColorCode(name)
		end
	end
	return "[" .. name .. "]"
end

function ns:OnChatEvent(event, text, sender, _, _, _, flag, _, _, _, _, _, guid)
	local session = self.session
	if not session then
		return
	end
	-- In restricted content the whole payload is secret; skip it rather than error.
	if not ns.CanRead(text, sender, flag, guid) or type(text) ~= "string" or type(sender) ~= "string" then
		return
	end

	local chatType = CHAT_EVENTS[event]
	local category = CHAT_CATEGORIES[chatType]
	local filter = CATEGORY_FILTERS[category]
	if filter and not self.db[filter] then
		return
	end
	session.counts[category] = session.counts[category] + 1
	if category == "WHISPERS" and self.db.flashOnWhisper and FlashClientIcon then
		FlashClientIcon()
	end

	local name = self:FormatSender(chatType, sender, guid)
	local ok, prefix = pcall(format, _G["CHAT_" .. chatType .. "_GET"] or "%s: ", name)
	if not ok then
		prefix = name .. ": "
	end
	if flag == "GM" or flag == "DEV" then
		prefix = GM_ICON .. prefix
	end

	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
	local r, g, b = 1, 0.5, 1
	if info then
		r, g, b = info.r or r, info.g or g, info.b or b
	end
	-- Kept even while the message list is turned off, so turning it on shows them.
	self.Screen:AddMessage(category, prefix .. text, r, g, b)
end

------------------------------------------------------------------------
-- Important popups that the screen must never hide
------------------------------------------------------------------------

local POPUP_EVENTS = {
	"READY_CHECK",
	"LFG_PROPOSAL_SHOW",
	"LFG_ROLE_CHECK_SHOW",
	"ROLE_POLL_BEGIN",
	"PET_BATTLE_QUEUE_PROPOSE_MATCH",
	"UPDATE_BATTLEFIELD_STATUS",
	"PARTY_INVITE_REQUEST",
	"GROUP_INVITE_CONFIRMATION",
	"CONFIRM_SUMMON",
	"RESURRECT_REQUEST",
	"DUEL_REQUESTED",
	"TRADE_SHOW",
	"PLAYER_CAMPING",
}

local popupLookup = {}
for _, event in ipairs(POPUP_EVENTS) do
	popupLookup[event] = true
end

function ns:OnPopupEvent(event, ...)
	if not self.db.dismissOnPopups or not self.Screen:IsActive() then
		return
	end
	if event == "UPDATE_BATTLEFIELD_STATUS" then
		local index = Readable((...))
		if not index or not GetBattlefieldStatus then
			return
		end
		local status = Readable((GetBattlefieldStatus(index)))
		if status ~= "confirm" then
			return
		end
	end
	self:Dismiss()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:RegisterEvent(event)
	-- Unknown events raise errors, and not every event exists on every client.
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		return false
	end
	return (pcall(eventFrame.RegisterEvent, eventFrame, event))
end

function ns:UnregisterEvent(event)
	pcall(eventFrame.UnregisterEvent, eventFrame, event)
end

local RUNTIME_EVENTS = {
	"PLAYER_FLAGS_CHANGED",
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LEAVING_WORLD",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_STARTED_MOVING",
	"ADDON_RESTRICTION_STATE_CHANGED",
	"CHAT_MSG_SYSTEM",
	"CINEMATIC_START",
	"PLAY_MOVIE",
	"DISPLAY_SIZE_CHANGED",
	"UI_SCALE_CHANGED",
	"PLAYER_LOGOUT",
}

function handlers:ADDON_LOADED(name)
	if name ~= ADDON_NAME then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	self:InitDB()
	if self.Options then
		local ok, err = pcall(self.Options.Init, self.Options)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

function handlers:PLAYER_LOGIN()
	if not self.db then
		self:InitDB()
	end
	self.loggedIn = true
	self.Screen:Create()
	-- The camera keeps turning across a /reload, so stop a spin that was left running.
	if self.db.cameraSpinActive then
		self.Screen:StopCameraSpin(true)
	end
	for _, event in ipairs(RUNTIME_EVENTS) do
		self:RegisterEvent(event)
	end
	for _, event in ipairs(POPUP_EVENTS) do
		self:RegisterEvent(event)
	end
	self:Evaluate()
end

function handlers:PLAYER_FLAGS_CHANGED(unit)
	if issecretvalue(unit) or unit ~= "player" then
		return
	end
	self:Evaluate()
end

function handlers:PLAYER_ENTERING_WORLD()
	self:Evaluate()
end

function handlers:PLAYER_LEAVING_WORLD()
	self.preview = false
	self.Screen:Hide(true)
end

function handlers:PLAYER_REGEN_DISABLED()
	if self.Screen:IsActive() then
		self:Dismiss(true)
	end
end

-- Moving means you're back, even when the game's "auto clear AFK" option is turned off.
function handlers:PLAYER_STARTED_MOVING()
	if self.Screen:IsActive() then
		self:Dismiss()
	end
end

function handlers:ADDON_RESTRICTION_STATE_CHANGED()
	-- Restriction checks always report "inactive" while this event is being dispatched.
	self.StartTimer("restriction", 0.2, EvaluateLater)
end

function handlers:CHAT_MSG_SYSTEM(text)
	self:OnSystemMessage(text)
end

function handlers:CINEMATIC_START()
	if self.Screen:IsActive() then
		self:Dismiss(true)
	end
end
handlers.PLAY_MOVIE = handlers.CINEMATIC_START

function handlers:DISPLAY_SIZE_CHANGED()
	self.Screen:Layout()
end
handlers.UI_SCALE_CHANGED = handlers.DISPLAY_SIZE_CHANGED

function handlers:PLAYER_LOGOUT()
	self.Screen:Hide(true)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler then
		handler(ns, ...)
	elseif CHAT_EVENTS[event] then
		ns:OnChatEvent(event, ...)
	elseif popupLookup[event] then
		ns:OnPopupEvent(event, ...)
	end
end)

ns:RegisterEvent("ADDON_LOADED")
ns:RegisterEvent("PLAYER_LOGIN")

------------------------------------------------------------------------
-- Slash commands, options and addon compartment
------------------------------------------------------------------------

function ns:OpenSettings()
	if InCombatLockdown() then
		self:Print(L.MSG_COMBAT)
		return
	end
	if not (self.Options and self.Options:Open()) then
		self:Print(L.MSG_NO_SETTINGS)
	end
end

function ns:PrintHelp()
	self:Print(L.HELP_HEADER)
	for _, line in ipairs({ L.HELP_OPTIONS, L.HELP_TEST, L.HELP_TOGGLE, L.HELP_RESET, L.HELP_STATUS }) do
		print("   " .. format(line, "/afkd"))
	end
end

function ns:PrintStatus()
	local afk = self:ReadAFK()
	local afkText = (afk == nil and L.STATUS_HIDDEN) or (afk and L.YES) or L.NO
	self:Print(L.STATUS_LINE, self.version, self.isForever and L.FLAVOR_FOREVER or L.FLAVOR_RETAIL,
		tostring(self.tocVersion), self.db.enabled and L.STATUS_ENABLED or L.STATUS_DISABLED, afkText)
end

_G.SLASH_AFKDELIGHT1 = "/afkdelight"
_G.SLASH_AFKDELIGHT2 = "/afkd"
SlashCmdList.AFKDELIGHT = function(input)
	if not ns.db then
		return
	end
	local command = strlower(strtrim(input or ""))
	if command == "" or command == "options" or command == "config" or command == "settings" then
		ns:OpenSettings()
	elseif command == "test" or command == "preview" then
		ns:TogglePreview()
	elseif command == "on" or command == "enable" then
		ns:SetEnabled(true)
	elseif command == "off" or command == "disable" then
		ns:SetEnabled(false)
	elseif command == "toggle" then
		ns:SetEnabled(not ns.db.enabled)
	elseif command == "reset" then
		ns:ResetSettings()
	elseif command == "status" then
		ns:PrintStatus()
	else
		ns:PrintHelp()
	end
end

function _G.AfkDelight_OnAddonCompartmentClick(_, buttonName)
	if buttonName == "RightButton" then
		ns:TogglePreview()
	else
		ns:OpenSettings()
	end
end

function _G.AfkDelight_OnAddonCompartmentEnter(_, button)
	if not (GameTooltip and button) then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.title .. " |cff808080" .. ns.version .. "|r")
	GameTooltip:AddLine(L.COMPARTMENT_LEFT, 1, 1, 1)
	GameTooltip:AddLine(L.COMPARTMENT_RIGHT, 1, 1, 1)
	GameTooltip:Show()
end

function _G.AfkDelight_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end
