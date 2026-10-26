-- Behavioural tests for AfkDelight, run against mock.lua on a real Lua 5.1 VM.
local ns, H, scenario = ...
local S = H.S
local L = ns.L
local Screen

local results, failures = {}, 0

local function check(condition, message)
	if not condition then
		error("CHECK FAILED: " .. tostring(message), 2)
	end
end

local function step(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		results[#results + 1] = "  PASS  " .. name
	else
		failures = failures + 1
		results[#results + 1] = "  FAIL  " .. name .. "\n" .. tostring(err)
	end
end

local function contains(text, part)
	return type(text) == "string" and text:find(part, 1, true) ~= nil
end

local function GoAFK()
	S.afk = true
	H.Fire("PLAYER_FLAGS_CHANGED", "player")
end

local function Return()
	S.afk = false
	H.Fire("PLAYER_FLAGS_CHANGED", "player")
end

local function Close()
	H.Key("ESCAPE")
end

-- Close and let the fade-out finish, so the next opening starts from scratch.
local function CloseFully()
	H.Key("ESCAPE")
	H.Advance(1)
end

local function lines(category)
	return Screen.chat.messages[category or "WHISPERS"].__lines or {}
end

local function printedSince(index, part)
	for i = index + 1, #H.printed do
		if contains(H.printed[i], part) then
			return true
		end
	end
	return false
end

local function chat(event, text, sender, flag, guid, bnID)
	H.Fire(event, text, sender, "", "", "", flag or "", 0, 0, "", 0, 100, guid or "", bnID or 0, false, false, false)
end

local function Load()
	H.Fire("ADDON_LOADED", "SomeOtherAddon")
	check(ns.db == nil, "db must wait for our own ADDON_LOADED")
	H.Fire("ADDON_LOADED", "AfkDelight")
	check(ns.db ~= nil and ns.db == AfkDelightDB, "db initialised")
	H.Fire("PLAYER_LOGIN")
	Screen = ns.Screen
	check(Screen.frame ~= nil and not Screen.frame:IsShown(), "screen built and hidden")
	H.Fire("PLAYER_ENTERING_WORLD", true, false)
end

local function tab(category)
	return Screen.chat.tabs[category]
end

------------------------------------------------------------------------
if scenario == "retail" then
------------------------------------------------------------------------

step("load, saved variables, options panel", function()
	Load()
	check(ns.isForever == false, "detected retail")
	check(ns.db.background == "GALAXY", "retail starts with the galaxy")
	check(ns.db.dbVersion == 2 and ns.db.dismissOnInput == nil, "current settings version")
	local count = 0
	for key, default in pairs(ns.defaults) do
		count = count + 1
		check(ns.db[key] == default, "default for " .. key)
		check(H.settings.byVariable["AfkDelight_" .. key], "setting registered for " .. key)
	end
	check(#H.settings.list == count, "one setting per option")
	check(H.settings.registered == H.settings.category, "category registered")
	check(H.IsRegistered("PLAYER_FLAGS_CHANGED") and H.IsRegistered("READY_CHECK") and H.IsRegistered("ADDON_RESTRICTION_STATE_CHANGED"), "runtime events registered")
	check(not H.IsRegistered("CHAT_MSG_WHISPER"), "chat events only while AFK")
	check(not Screen:IsActive(), "no screen while not AFK")
end)

step("options panel controls are valid", function()
	local kinds = {}
	for _, init in ipairs(H.settings.layout.initializers) do
		kinds[init.kind] = (kinds[init.kind] or 0) + 1
		if init.kind == "slider" then
			local formatter = init.options.formatters[MinimalSliderWithSteppersMixin.Label.Right]
			check(type(formatter) == "function", "slider formatter")
			for _, value in ipairs({ init.options.minValue, init.options.maxValue, 0, 37.4 }) do
				check(type(formatter(value)) == "string", "formatter output")
			end
		elseif init.kind == "dropdown" then
			local data = init.options()
			local found = false
			for _, option in ipairs(data) do
				check(type(option.value) == "string" and type(option.label) == "string", "dropdown entry")
				found = found or option.value == init.setting:GetValue()
			end
			check(found, "current dropdown value listed")
		end
		if init.predicate then
			check(type(init.predicate()) == "boolean", "predicate returns a boolean")
		end
	end
	check(kinds.header == 4 and kinds.button == 2 and kinds.dropdown == 2 and kinds.slider == 4, "control mix")
	local backgrounds = {}
	for _, init in ipairs(H.settings.layout.initializers) do
		if init.kind == "dropdown" and init.setting.key == "background" then
			for _, option in ipairs(init.options()) do backgrounds[option.value] = true end
		end
	end
	check(backgrounds.AZEROTH and backgrounds.GALAXY and backgrounds.STARFIELD and backgrounds.WORLD and backgrounds.SOLID, "all backgrounds offered")
	check(H.settings.byVariable.AfkDelight_dismissOnInput == nil, "close-on-any-key option removed")
	check(L.Formatters == "Formatters", "missing locale keys fall back to the key")
end)

step("going AFK shows the screen with character info", function()
	H.Fire("CHAT_MSG_SYSTEM", "You are now AFK: Getting coffee", "", "", "", "", "", 0, 0, "", 0, 1, "", 0, false, false, false)
	GoAFK()
	check(Screen:IsActive() and Screen.frame:IsShown(), "screen active")
	check(Screen.frame.__strata == "FULLSCREEN", "fullscreen strata")
	check(Screen.frame.__keyboard and Screen.frame.__mouse and Screen.frame.__wheel, "screen takes keyboard, mouse and wheel")
	check(Screen.frame.__propagate == false, "keys stay on the screen")
	check(H.IsRegistered("CHAT_MSG_WHISPER"), "chat events while AFK")
	check(ns.session.reason == "Getting coffee", "AFK message captured")
	H.Advance(1.25)
	check(math.abs(Screen.frame:GetAlpha() - 1) < 1e-6, "faded in")
	check(Screen.title:GetText() == "Away from Keyboard", "title")
	check(Screen.reason:IsShown() and contains(Screen.reason:GetText(), "Getting coffee"), "reason")
	check(Screen.name:GetText() == "Frostanon", "name " .. tostring(Screen.name:GetText()))
	check(Screen.details:GetText() == "Level 80 Void Elf Frost Mage", "details " .. tostring(Screen.details:GetText()))
	check(Screen.guild:GetText() == "<Wicked Demise>  Officer", "guild")
	check(Screen.itemLevel:GetText() == "Item Level 678", "item level")
	check(Screen.zone:GetText() == "Stormwind City - Trade District", "zone")
	check(not Screen.subtitle:IsShown(), "no title selected")
	check(not Screen.progress:IsShown(), "no leveling line at max level")
	check(Screen.classIcon:IsShown(), "class icon")
	check(Screen.timer:GetText() == "Away for 00:01", "timer " .. tostring(Screen.timer:GetText()))
	check(Screen.clock:GetText() == "17:05", "clock")
	check(Screen.date:GetText():match("^%a+, %a+ %d+$"), "date " .. tostring(Screen.date:GetText()))
	check(Screen.galaxy:IsShown() and Screen.galaxy.__display == 67918, "galaxy model")
	check(Screen.galaxyVerified, "galaxy model loaded")
	check(not Screen.sky:IsShown(), "no moons over the galaxy")
	check(Screen.starfield:IsShown() and Screen.starsAnimating, "starfield behind the galaxy")
	check(Screen.model:IsShown() and Screen.model.__unit == "player", "character model")
	check(H.animations[1] == 67, "waves first")
	check(Screen.hint:GetText() == L.HINT_CLOSE, "hint")
	check(Screen.chat:IsShown(), "message panel is always there")
	check(Screen.selectedTab == "WHISPERS" and tab("WHISPERS"):IsShown() and tab("GUILD"):IsShown() and tab("GROUP"):IsShown(), "three tabs")
	check(tab("WHISPERS").label:GetText() == "Whispers (0)" and tab("WHISPERS").underline:IsShown(), "whispers tab selected")
	check(Screen.chat.empty:IsShown() and Screen.chat.empty:GetText() == L.EMPTY_WHISPERS, "empty placeholder")
	H.Fire("PLAYER_FLAGS_CHANGED", "party1")
	check(Screen:IsActive(), "other units' flags are ignored")
end)

step("messages land in their own tabs", function()
	chat("CHAT_MSG_WHISPER", "Hey, are you there?", "Bob-Silvermoon", nil, "Player-1-00000001")
	check(ns.session.counts.WHISPERS == 1 and H.flashCount == 1, "whisper counted, taskbar flashed")
	local first = lines("WHISPERS")[1]
	check(contains(first, "Bob") and not contains(first, "Silvermoon") and contains(first, "whispers: ") and contains(first, "Hey, are you there?"), "whisper line " .. tostring(first))
	check(contains(first, "|cff3fc6ebBob|r") or contains(first, "|cff3fc6eaBob|r"), "class-coloured sender " .. tostring(first))
	check(not Screen.chat.empty:IsShown(), "placeholder gone")
	chat("CHAT_MSG_BN_WHISPER", "Real ID hello", "|Kq42|k", nil, nil, 77)
	chat("CHAT_MSG_GUILD", "Guild hello", "Alice-Silvermoon", nil, "Player-1-00000002")
	chat("CHAT_MSG_OFFICER", "Officer note", "Erin-Silvermoon", nil, "Player-1-00000005")
	chat("CHAT_MSG_PARTY", "Party hello", "Carl-Silvermoon", nil, "Player-1-00000003")
	chat("CHAT_MSG_INSTANCE_CHAT", "Instance hello", "Dan-Silvermoon", nil, "Player-1-00000004")
	check(#lines("WHISPERS") == 2 and #lines("GUILD") == 2 and #lines("GROUP") == 2, "split per tab")
	check(H.flashCount == 2, "only whispers flash")
	check(contains(lines("WHISPERS")[2], "|Kq42|k"), "Battle.net name kept as protected string")
	check(contains(lines("GUILD")[1], "[Guild]") and contains(lines("GUILD")[2], "[Officer]"), "guild prefixes")
	check(contains(lines("GROUP")[2], "Dan") and contains(lines("GROUP")[2], "Instance hello"), "fallback prefix")
	check(tab("WHISPERS").label:GetText() == "Whispers (2)", "whisper count")
	check(tab("GUILD").label:GetText() == "Guild (2)" and Screen.chat.unread.GUILD == 2, "guild unread")
	check(Screen.chat.messages.WHISPERS:IsShown() and not Screen.chat.messages.GUILD:IsShown(), "only the selected tab is shown")
	for _, category in ipairs({ "WHISPERS", "GUILD", "GROUP" }) do
		check(Screen.chat.messages[category].__insertMode == SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP, "messages start at the top of the " .. category .. " tab")
	end
	check(contains(lines("WHISPERS")[1], "Hey, are you there?") and contains(lines("WHISPERS")[2], "Real ID hello"), "oldest message first")

	H.RunScript(tab("GUILD"), "OnClick", "LeftButton")
	check(Screen:IsActive(), "clicking a tab doesn't close the screen")
	check(Screen.selectedTab == "GUILD" and Screen.chat.messages.GUILD:IsShown() and not Screen.chat.messages.WHISPERS:IsShown(), "guild tab opened")
	check(Screen.chat.unread.GUILD == 0 and tab("GUILD").underline:IsShown() and not tab("WHISPERS").underline:IsShown(), "guild read")

	chat("CHAT_MSG_WHISPER", "Another whisper", "Bob-Silvermoon", nil, "Player-1-00000001")
	check(Screen.chat.unread.WHISPERS == 1 and Screen.selectedTab == "GUILD", "new whisper marked unread without switching")

	check(H.Key("TAB") == false and Screen.selectedTab == "GROUP", "Tab cycles forward")
	H.Key("TAB")
	check(Screen.selectedTab == "WHISPERS" and Screen.chat.unread.WHISPERS == 0, "Tab wraps around")
	S.shift = true
	H.Key("TAB")
	S.shift = false
	check(Screen.selectedTab == "GROUP", "Shift-Tab cycles backwards")

	local group = Screen.chat.messages.GROUP
	for _, key in ipairs({ "PAGEUP", "PAGEDOWN", "UP", "DOWN", "HOME", "END" }) do H.Key(key) end
	H.RunScript(Screen.frame, "OnMouseWheel", 1)
	S.shift = true
	H.RunScript(Screen.frame, "OnMouseWheel", -1)
	S.shift = false
	local scrolls = table.concat(group.__scrolls or {}, ",")
	-- Oldest first: Page Up / Up / wheel up go back to older messages, End jumps to the newest page.
	check(scrolls == "PageDown,PageUp,ScrollDown,ScrollUp,ScrollToBottom,SetScrollOffset:0,ScrollDown,SetScrollOffset:0", "scrolling " .. scrolls)
	check(Screen:IsActive(), "still open after all that")

	ns:SetOption("chatGuild", false)
	check(not tab("GUILD"):IsShown() and tab("GROUP"):IsShown(), "guild tab hidden")
	chat("CHAT_MSG_GUILD", "filtered", "Alice-Silvermoon", nil, "Player-1-00000002")
	check(#lines("GUILD") == 2 and ns.session.counts.GUILD == 2, "guild chat not collected")
	ns:SetOption("chatGroup", false)
	check(Screen.selectedTab == "WHISPERS", "falls back to whispers when the open tab goes away")
	ns:SetOption("chatGuild", true)
	ns:SetOption("chatGroup", true)

	local secret = H.SECRET
	H.Fire("CHAT_MSG_WHISPER", secret, secret, secret, secret, secret, secret, secret, secret, secret, secret, secret, secret, secret, secret, secret, secret)
	check(#lines("WHISPERS") == 3 and ns.session.counts.WHISPERS == 3, "secret chat payload skipped safely")

	chat("CHAT_MSG_WHISPER", "This is a Game Master", "Gamemaster-Silvermoon", "GM", "Player-1-00000009")
	check(contains(lines("WHISPERS")[4], "UI-ChatIcon-Blizz"), "GM icon")

	ns:SetOption("showChat", false)
	check(not Screen.chat:IsShown(), "panel can be turned off")
	chat("CHAT_MSG_WHISPER", "Still collected", "Bob-Silvermoon", nil, "Player-1-00000001")
	ns:SetOption("showChat", true)
	check(Screen.chat:IsShown() and #lines("WHISPERS") == 5, "messages kept while the panel was off")

	H.Fire("CHAT_MSG_SYSTEM", "Bob has come online.", "", "", "", "", "", 0, 0, "", 0, 1, "", 0, false, false, false)
	H.Fire("CHAT_MSG_SYSTEM", secret, secret)
	check(ns.session.reason == "Getting coffee", "unrelated system messages ignored")
end)

step("only Escape or Close closes the screen", function()
	S.bgStatus = "queued"
	H.Fire("UPDATE_BATTLEFIELD_STATUS", 1)
	check(Screen:IsActive(), "queue update without a pop keeps the screen")
	for _, key in ipairs({ "W", "A", "B", "SPACE", "ENTER", "LSHIFT", "1" }) do
		check(H.Key(key) == false and Screen:IsActive(), key .. " is swallowed and doesn't close")
	end
	H.Click()
	check(Screen:IsActive(), "clicking doesn't close")
	check(H.Key("PRINTSCREEN") == true and Screen:IsActive(), "screenshot key goes to the game")
	check(H.Key("ESCAPE") == false, "escape consumed")
	check(not Screen:IsActive() and Screen.frame:IsShown(), "fading out")
	check(not Screen.frame.__keyboard and not Screen.frame.__mouse, "input released while fading")
	H.Advance(0.75)
	check(not Screen.frame:IsShown(), "hidden after fade")
	check(ns.session.dismissed, "dismissed for this AFK session")
	H.Fire("PLAYER_FLAGS_CHANGED", "player")
	check(not Screen:IsActive(), "stays closed while still AFK")
end)

step("returning prints a summary and ends the session", function()
	local before = #H.printed
	S.money = S.money + 12345
	H.Advance(30)
	Return()
	check(ns.session == nil and not H.IsRegistered("CHAT_MSG_WHISPER"), "session ended")
	check(printedSince(before, "Welcome back!"), "welcome back")
	check(printedSince(before, "Missed: 5 |4whisper:whispers;, 2 guild |4message:messages;, 2 group |4message:messages;."), "missed summary " .. tostring(H.printed[#H.printed]))
	check(printedSince(before, "Money: +12345c."), "money")
	S.money = S.money - 12345
end)

step("Close button closes; a new session starts clean", function()
	GoAFK()
	check(Screen:IsActive() and #lines("WHISPERS") == 0 and #lines("GUILD") == 0, "new session starts with empty tabs")
	check(Screen.chat:IsShown() and Screen.chat.empty:IsShown(), "empty panel")
	H.RunScript(Screen.closeButton, "OnClick", "LeftButton")
	check(not Screen:IsActive(), "close button works")
	local before = #H.printed
	Return()
	check(not printedSince(before, "Welcome back"), "no summary for a short AFK")
end)

step("messages received before the screen shows are unread", function()
	ns:SetOption("delay", 10)
	GoAFK()
	chat("CHAT_MSG_GUILD", "Early guild message", "Alice-Silvermoon", nil, "Player-1-00000002")
	check(not Screen:IsActive(), "still waiting")
	H.Advance(10.5)
	check(Screen:IsActive() and Screen.selectedTab == "GUILD", "opens on the tab with unread messages")
	check(Screen.timer:GetText() == "Away for 00:10", "timer counts from going AFK: " .. tostring(Screen.timer:GetText()))
	Close()
	Return()
	ns:SetOption("delay", 0)
end)

step("long AFK: the oldest messages make room for new ones", function()
	GoAFK()
	H.RunScript(tab("GUILD"), "OnClick", "LeftButton")
	for i = 1, 205 do
		chat("CHAT_MSG_GUILD", "Message #" .. i .. ".", "Alice-Silvermoon", nil, "Player-1-00000002")
	end
	local guild = lines("GUILD")
	check(#guild == 200 and contains(guild[1], "Message #6.") and contains(guild[200], "Message #205."), "newest 200 kept, oldest first")
	check(H.droppedMessages == nil, "no message refused by a full buffer")
	check(tab("GUILD").label:GetText() == "Guild (205)", "tab counts every message")
	H.Key("END")
	check(Screen.chat.messages.GUILD.__offset == 190, "End shows the newest page")
	chat("CHAT_MSG_GUILD", "Message #206.", "Alice-Silvermoon", nil, "Player-1-00000002")
	check(contains(lines("GUILD")[1], "Message #7.") and contains(lines("GUILD")[200], "Message #206."), "still in order after a refill")
	check(Screen.chat.messages.GUILD.__offset == 189, "view stays on the same messages")
	CloseFully()
	Return()
end)

step("combat closes instantly", function()
	GoAFK()
	H.Advance(1)
	H.Fire("PLAYER_REGEN_DISABLED")
	check(not Screen:IsActive() and not Screen.frame:IsShown(), "hidden immediately")
	Return()
end)

step("restricted content (secret values) never shows or errors", function()
	S.lockdown = true
	GoAFK()
	check(not Screen:IsActive(), "nothing shown during chat lockdown")
	S.lockdown = false
	S.afkValue = H.SECRET
	H.Fire("PLAYER_FLAGS_CHANGED", "player")
	check(not Screen:IsActive(), "secret AFK flag treated as unknown")
	S.afkValue = nil
	H.Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
	check(not Screen:IsActive(), "re-check is deferred")
	H.Advance(0.3)
	check(Screen:IsActive(), "shown once the restriction lifts")
	S.lockdown = true
	H.Fire("PLAYER_FLAGS_CHANGED", "player")
	check(not Screen:IsActive() and not Screen.frame:IsShown(), "hidden when restrictions start")
	S.lockdown = false
	Return()
end)

step("waits while casting, in combat, cinematics or instances", function()
	S.casting = "Crafting"
	GoAFK()
	check(not Screen:IsActive(), "not while casting")
	H.Advance(11)
	check(not Screen:IsActive(), "still casting")
	S.casting = nil
	H.Advance(11)
	check(Screen:IsActive(), "shown after casting")
	Close()
	Return()

	S.combat = true
	GoAFK()
	check(not Screen:IsActive(), "not in combat")
	S.combat = false
	Return()

	CinematicFrame:Show()
	GoAFK()
	check(not Screen:IsActive(), "not during cinematics")
	CinematicFrame:Hide()
	H.Advance(5.5)
	check(Screen:IsActive(), "shown after the cinematic")
	H.Fire("CINEMATIC_START", false)
	check(not Screen:IsActive(), "cinematic closes the screen")
	Return()

	S.instance = true
	ns:SetOption("disableInInstances", true)
	GoAFK()
	check(not Screen:IsActive(), "disabled in instances")
	Return()
	ns:SetOption("disableInInstances", false)
	GoAFK()
	check(Screen:IsActive(), "allowed in instances when the option is off")
	Close()
	Return()
	S.instance = false
end)

step("important popups close the screen", function()
	for _, event in ipairs({ "READY_CHECK", "LFG_PROPOSAL_SHOW", "PARTY_INVITE_REQUEST", "CONFIRM_SUMMON", "RESURRECT_REQUEST", "DUEL_REQUESTED", "TRADE_SHOW", "PLAYER_CAMPING", "LFG_ROLE_CHECK_SHOW", "ROLE_POLL_BEGIN", "GROUP_INVITE_CONFIRMATION", "PET_BATTLE_QUEUE_PROPOSE_MATCH" }) do
		GoAFK()
		check(Screen:IsActive(), "shown before " .. event)
		check(H.Fire(event, "Leader", 30) > 0, event .. " is registered")
		check(not Screen:IsActive(), event .. " closes the screen")
		Return()
	end
	GoAFK()
	S.bgStatus = "confirm"
	H.Fire("UPDATE_BATTLEFIELD_STATUS", 1)
	check(not Screen:IsActive(), "battleground queue pop closes the screen")
	S.bgStatus = "none"
	Return()

	ns:SetOption("dismissOnPopups", false)
	GoAFK()
	H.Fire("READY_CHECK", "Leader", 30)
	check(Screen:IsActive(), "option off keeps the screen")
	Close()
	Return()
	ns:SetOption("dismissOnPopups", true)
end)

step("moving, zoning and logging out", function()
	GoAFK()
	H.Fire("PLAYER_STARTED_MOVING")
	check(not Screen:IsActive(), "moving closes the screen")
	Return()
	GoAFK()
	H.Fire("PLAYER_LEAVING_WORLD")
	check(not Screen:IsActive() and not Screen.frame:IsShown(), "loading screen hides instantly")
	H.Fire("PLAYER_ENTERING_WORLD", false, false)
	check(Screen:IsActive(), "back after the loading screen while still AFK")
	H.Fire("PLAYER_LOGOUT")
	check(not Screen:IsActive(), "logout hides")
	Return()
end)

step("Azeroth and her moons, with creature flybys", function()
	ns:SetOption("background", "AZEROTH")
	GoAFK()
	check(Screen.sky:IsShown() and Screen.starfield:IsShown() and not Screen.galaxy:IsShown(), "sky over stars, no galaxy")
	check(#Screen.bodies == 3, "Azeroth, the White Lady and the Blue Child")
	local azeroth, whiteLady, blueChild = Screen.bodies[1], Screen.bodies[2], Screen.bodies[3]
	check(azeroth.surface.__file == 130561 and whiteLady.surface.__file == 130521 and blueChild.surface.__file == 130449, "the game's own sky textures")
	check(azeroth.__width > whiteLady.__width * 2 and whiteLady.__width > blueChild.__width, "Azeroth first, then the White Lady, then the Blue Child")
	check(not azeroth.glow and not azeroth.surface.__desaturated and not azeroth.surface.__masks, "Azeroth keeps her colours, no masks needed")
	check(whiteLady.surface.__desaturated and whiteLady.glow.__desaturated and whiteLady.glow.__blend == "ADD", "the White Lady is pale and glows")
	local tint = blueChild.surface.__vertexColor
	check(tint and tint[1] < 0.6 and tint[3] == 1 and blueChild.glow.__vertexColor[1] == tint[1], "the Blue Child is blue")
	check(whiteLady.pulse:IsPlaying() and blueChild.pulse:IsPlaying(), "moons glow")
	local dust = Screen.starDust
	check(dust.__file == 130627 and dust.__blend == "ADD" and dust.__wrap[1] == "REPEAT" and dust.__wrap[2] == "REPEAT", "star dust")
	check(math.abs(dust.__texCoord[2] - 1600 / 512) < 1e-6 and math.abs(dust.__texCoord[4] - 900 / 512) < 1e-6, "star dust tiled at its own size")
	local function X(region) return region.__points[#region.__points][4] end
	local ladyX, azerothX = X(whiteLady), X(azeroth)
	H.Advance(60)
	local ladyDrift, azerothDrift = math.abs(X(whiteLady) - ladyX), math.abs(X(azeroth) - azerothX)
	check(azerothDrift > 0 and ladyDrift > azerothDrift, "the moons drift further than Azeroth")
	check(H.lights and H.lights >= 1, "something flew by within the first minute")

	-- Watch the sky (for up to 40 minutes) until every flyer of an Alliance player has come by in both directions,
	-- each one flapping and facing its way, with a quiet minute or two between flights.
	local flyer = Screen.flyer
	local seen, animations, directions, starts = {}, {}, {}, {}
	local flying, lastX = false, nil
	local function AllSeen()
		return seen[8570] and seen[1149] and seen[3212] and seen[2717] and seen[1267]
	end
	for _ = 1, 9600 do
		H.Advance(0.25, 0.25)
		local flight = Screen.flight
		if flight.active and flight.loaded then
			if not flying then
				flying, lastX = true, nil
				starts[#starts + 1] = H.time
				local display = flyer.__display
				seen[display] = (seen[display] or 0) + 1
				animations[display] = flyer.__animation
				directions[flight.toX > flight.fromX and "right" or "left"] = true
				check(flyer:IsShown() and S.flyers[display][flyer.__animation], "flies with an animation its model has")
				check(math.abs(flyer.__rotation - flight.facing) < 1e-6 and math.abs(math.abs(flight.facing) - math.pi / 2) < 1e-6, "side-on, facing its way")
				check((flight.facing > 0) == (flight.toX > flight.fromX), "faces the way it flies")
				check(flyer.__light and flyer.__light.ambientIntensity >= 0.5 and flyer.__light.diffuseIntensity > 0, "moonlit, not a black shape on a black sky")
			end
			local x = X(flyer)
			if lastX then
				check((x - lastX) * (flight.toX - flight.fromX) >= 0, "keeps flying the same way")
			end
			lastX = x
		elseif flying then
			flying = false
			check(not flyer:IsShown(), "gone after its flight")
			check(Screen.nextFlight >= 40, "the next flyby is a while away")
			if #starts >= 6 and AllSeen() and directions.left and directions.right then
				break
			end
		end
	end
	check(AllSeen(), "Onyxia, gryphon, hippogryph, green dragon and faerie dragon all came by")
	check(#starts >= 6, "watched several flights (" .. #starts .. ")")
	for i = 2, #starts do
		local gap = starts[i] - starts[i - 1]
		check(gap >= 70 and gap <= 150, "a flyby every minute or two (" .. gap .. " s apart)")
	end
	check(not seen[295], "no wind rider for an Alliance character")
	check(animations[8570] == 234 and animations[1149] == 135, "Onyxia flies with FlyRun, classic models with Fly")
	check(directions.left and directions.right, "flights both ways")
	CloseFully()
	Return()
end)

step("flybys can be turned off and never misbehave", function()
	ns:SetOption("dragonFlyby", false)
	SlashCmdList.AFKDELIGHT("test")
	local lightsBefore = H.lights or 0
	H.Advance(200, 0.25)
	check(not Screen.flyer:IsShown() and (H.lights or 0) == lightsBefore, "no flybys when turned off")
	CloseFully()
	ns:SetOption("dragonFlyby", true)

	-- A preview brings the first flyer almost at once; turning flybys off sends it away.
	SlashCmdList.AFKDELIGHT("test")
	H.Advance(3.5)
	check(Screen.flight.active and Screen.flight.loaded and Screen.flyer:IsShown(), "first flyer right away in a preview")
	ns:SetOption("dragonFlyby", false)
	H.Advance(0.25)
	check(not Screen.flight.active and not Screen.flyer:IsShown(), "turning flybys off ends the flight")
	ns:SetOption("dragonFlyby", true)
	CloseFully()

	-- A creature whose model can't fly in this client is left out for good; the others still come.
	S.flyers[8570] = {}
	Screen.flyerFailures, Screen.flyerDeck = {}, nil
	SlashCmdList.AFKDELIGHT("test")
	local seen = {}
	for _ = 1, 4000 do
		H.Advance(0.25, 0.25)
		if Screen.flight.active and Screen.flight.loaded then
			seen[Screen.flyer.__display] = true
		end
	end
	check(not seen[8570] and Screen.flyerFailures[8570] == 2, "no flying animation: never shown sliding across the sky")
	check(seen[1149] and seen[3212] and seen[2717] and seen[1267], "the others still fly")
	CloseFully()

	-- Only a hover animation: it hovers across.
	for display in pairs(S.flyers) do S.flyers[display] = { [193] = true } end
	Screen.flyerFailures, Screen.flyerDeck = {}, nil
	SlashCmdList.AFKDELIGHT("test")
	H.Advance(3.5)
	check(Screen.flight.loaded and Screen.flyer.__animation == 193, "falls back to the hover animation")
	CloseFully()

	-- Nothing can fly at all: flybys stop for good, quietly.
	for display in pairs(S.flyers) do S.flyers[display] = {} end
	Screen.flyerFailures, Screen.flyerDeck = {}, nil
	SlashCmdList.AFKDELIGHT("test")
	H.Advance(60, 0.25)
	check(Screen.flybysUnavailable and not Screen.flyer:IsShown(), "no flying animations anywhere: no flybys")
	CloseFully()

	-- Models that never load get two tries each, then flybys stop.
	S.flyers = H.DefaultFlyers()
	S.flyerLoads = false
	Screen.flyerFailures, Screen.flyerDeck, Screen.flybysUnavailable = {}, nil, nil
	SlashCmdList.AFKDELIGHT("test")
	H.Advance(400, 0.25)
	check(Screen.flybysUnavailable and not Screen.flyer:IsShown(), "missing models given up")
	for _, display in ipairs({ 8570, 1149, 3212, 2717, 1267 }) do
		check(Screen.flyerFailures[display] == 2, "two tries for display " .. display)
	end
	check(Screen.flyerFailures[295] == nil, "the other faction's mount is never tried")
	CloseFully()
	S.flyerLoads = true
	Screen.flyerFailures, Screen.flyerDeck, Screen.flybysUnavailable = {}, nil, nil
	ns:SetOption("background", "GALAXY")
end)

step("flybys cross the galaxy too, but not the plain starfield", function()
	SlashCmdList.AFKDELIGHT("test")
	H.Advance(3.5)
	check(Screen.galaxy:IsShown() and not Screen.sky:IsShown(), "galaxy, no Azeroth")
	check(Screen.flight.active and Screen.flight.loaded and Screen.flyer:IsShown(), "a flyer over the galaxy")
	check(Screen.flyer:GetFrameLevel() > Screen.galaxy:GetFrameLevel(), "in front of the galaxy")
	ns:SetOption("background", "STARFIELD")
	H.Advance(0.25)
	check(not Screen.flight.active and not Screen.flyer:IsShown(), "switching to the starfield ends the flight")
	H.Advance(200, 0.25)
	check(not Screen.flyer:IsShown() and not Screen.flight.active, "and no flybys there")
	CloseFully()
	ns:SetOption("background", "GALAXY")
end)

step("game world background fades the UI and spins the camera", function()
	ns:SetOption("background", "WORLD")
	GoAFK()
	H.Advance(1.25)
	check(UIParent:GetAlpha() < 0.001, "interface faded out")
	check(math.abs(Screen.frame:GetAlpha() - 1) < 1e-6 and Screen.frame.__ignoreParentAlpha, "AFK screen stays visible")
	check(not Screen.starfield:IsShown() and not Screen.galaxy:IsShown() and not Screen.sky:IsShown(), "no space background")
	check(math.abs(Screen.backdrop.__color[4] - 0.4) < 1e-6, "world dimmed by 40%")
	check(H.moveViewStart == 1 and ns.db.cameraSpinActive, "camera spinning")
	Close()
	H.Advance(0.3)
	check(UIParent:GetAlpha() > 0 and UIParent:GetAlpha() < 1, "interface fades back in")
	H.Advance(0.5)
	check(UIParent:GetAlpha() == 1 and not Screen.frame:IsShown(), "interface restored")
	check(H.moveViewStop >= 1 and not ns.db.cameraSpinActive, "camera stopped")
	Return()

	-- The whole UI gets hidden (Alt+Z) while the screen is fading out.
	GoAFK()
	H.Advance(1.25)
	Close()
	H.Advance(0.2)
	UIParent:Hide()
	check(not Screen:IsActive() and UIParent:GetAlpha() == 1, "interrupted fade finished")
	check(not ns.db.cameraSpinActive, "camera stopped when the UI is hidden")
	UIParent:Show()
	check(not Screen.frame:IsShown(), "screen doesn't come back with the UI")
	Return()

	-- The UI gets hidden while the screen is fully up.
	GoAFK()
	H.Advance(1.25)
	UIParent:Hide()
	check(not Screen:IsActive() and ns.session.dismissed, "treated as a dismissal")
	UIParent:Show()
	check(not Screen.frame:IsShown() and UIParent:GetAlpha() == 1, "UI and screen state restored")
	Return()

	-- Switching away from the world background while the screen is up.
	GoAFK()
	H.Advance(1.25)
	ns:SetOption("cameraSpin", false)
	check(not ns.db.cameraSpinActive, "camera stops when spinning is turned off")
	ns:SetOption("background", "STARFIELD")
	check(UIParent:GetAlpha() == 1, "interface restored when leaving the world background")
	Close()
	Return()
	ns:SetOption("cameraSpin", true)
end)

step("starfield and solid backgrounds", function()
	SlashCmdList.AFKDELIGHT("test")
	check(Screen:IsActive() and Screen.preview, "preview open")
	check(Screen.starfield:IsShown() and not Screen.galaxy:IsShown() and not Screen.sky:IsShown(), "starfield only")
	local before = H.lineUpdates
	H.Advance(30, 0.05)
	check(H.lineUpdates > before, "shooting stars drawn")
	SlashCmdList.AFKDELIGHT("test")
	check(not Screen:IsActive(), "preview toggled off")
	ns:SetOption("background", "SOLID")
	SlashCmdList.AFKDELIGHT("preview")
	check(not Screen.starfield:IsShown() and not Screen.galaxy:IsShown() and not Screen.starsAnimating and not Screen.sky:IsShown(), "solid background")
	Close()
	ns:SetOption("background", "GALAXY")
end)

step("preview shows sample messages and doesn't create a session", function()
	SlashCmdList.AFKDELIGHT("test")
	check(Screen.preview and ns.session == nil, "preview without a session")
	check(#lines("WHISPERS") == 1 and #lines("GUILD") == 1 and #lines("GROUP") == 1, "a sample in every tab")
	check(contains(lines("WHISPERS")[1], "Jaina") and contains(lines("GUILD")[1], "Thrall") and contains(lines("GROUP")[1], "Bolvar"), "sample senders")
	check(Screen.selectedTab == "WHISPERS", "opens on whispers")
	check(Screen.hint:GetText() == L.HINT_PREVIEW, "preview hint")
	H.Fire("PLAYER_FLAGS_CHANGED", "player")
	H.Click()
	check(Screen:IsActive(), "flag changes and clicks don't close a preview")
	Close()
	check(not Screen:IsActive(), "escape closes the preview")
end)

step("character animations and facing", function()
	ns:SetOption("animation", "RANDOM")
	SlashCmdList.AFKDELIGHT("test")
	local count = #H.animations
	check(H.animations[count] == 67, "wave")
	H.Advance(3)
	check(H.animations[#H.animations] == 0, "stand after waving")
	H.Advance(2.5)
	check(math.abs(Screen.facing - Screen.facingTarget) < 0.05, "turned towards the configured facing")
	H.Advance(25)
	local emotes = {}
	for i = count + 1, #H.animations do emotes[H.animations[i]] = true end
	local sawEmote = false
	for _, id in ipairs({ 60, 66, 68, 69, 70, 80, 82, 83, 113 }) do sawEmote = sawEmote or emotes[id] end
	check(sawEmote, "random emotes played")
	S.hasAnimation = false
	H.Advance(25)
	S.hasAnimation = true
	ns:SetOption("animation", "DANCE")
	H.Advance(3)
	check(H.animations[#H.animations] == 69, "dance")
	ns:SetOption("introWave", false)
	check(H.animations[#H.animations] == 69, "no wave when disabled")
	local rotation = Screen.model.__rotation
	ns:SetOption("modelSpin", true)
	H.Advance(1)
	check(Screen.model.__rotation ~= rotation, "character turns")
	ns:SetOption("modelSpin", false)
	ns:SetOption("modelFacing", 30)
	H.Advance(3)
	check(math.abs(Screen.model.__rotation - math.rad(30)) < 0.05, "facing setting applied")
	ns:SetOption("modelScale", 150)
	check(math.abs(Screen.model.__width - 900 * 1.5) < 1e-6, "model scale")
	ns:SetOption("showModel", false)
	check(not Screen.model:IsShown(), "model hidden")
	ns:SetOption("showInfo", false)
	check(not Screen.name:IsShown() and not Screen.classIcon:IsShown() and Screen.title:IsShown() and Screen.timer:IsShown(), "character info hidden, AFK timer kept")
	ns:SetOption("showClock", false)
	check(not Screen.clock:IsShown() and not Screen.date:IsShown(), "clock hidden")
	Close()
	ns:ResetSettings()
	check(ns.db.animation == "RANDOM" and ns.db.showModel and ns.db.introWave and ns.db.modelFacing == -110, "reset restores defaults")
end)

step("slash commands", function()
	local before = #H.printed
	SlashCmdList.AFKDELIGHT("off")
	check(ns.db.enabled == false and printedSince(before, L.MSG_DISABLED), "disabled")
	GoAFK()
	check(not Screen:IsActive(), "disabled screen stays hidden")
	SlashCmdList.AFKDELIGHT("on")
	check(ns.db.enabled == true and Screen:IsActive(), "enabling while AFK shows the screen")
	Close()
	SlashCmdList.AFKDELIGHT("toggle")
	check(ns.db.enabled == false, "toggle off")
	SlashCmdList.AFKDELIGHT("toggle")
	check(ns.db.enabled == true, "toggle on")
	Return()
	SlashCmdList.AFKDELIGHT("")
	check(H.opened[#H.opened] == 9001, "options opened")
	SlashCmdList.AFKDELIGHT("  OPTIONS  ")
	check(#H.opened == 2, "options command is case-insensitive")
	before = #H.printed
	SlashCmdList.AFKDELIGHT("status")
	check(printedSince(before, "Version 1.0.0, World of Warcraft (Retail) (interface 120105). Screen enabled. AFK status: No."), "status " .. tostring(H.printed[#H.printed]))
	before = #H.printed
	SlashCmdList.AFKDELIGHT("whatever")
	check(printedSince(before, "/afkd test"), "help")
	S.combat = true
	before = #H.printed
	SlashCmdList.AFKDELIGHT("")
	SlashCmdList.AFKDELIGHT("test")
	check(#H.opened == 2 and not Screen:IsActive() and printedSince(before, L.MSG_COMBAT), "blocked in combat")
	S.combat = false
	before = #H.printed
	SlashCmdList.AFKDELIGHT("reset")
	check(printedSince(before, L.MSG_RESET), "reset message")
end)

step("options panel buttons", function()
	for _, init in ipairs(H.settings.layout.initializers) do
		if init.kind == "button" and init.name == L.OPT_PREVIEW then
			init.onClick()
			check(Screen:IsActive() and Screen.preview, "preview button")
			init.onClick()
			check(not Screen:IsActive(), "preview button toggles")
		elseif init.kind == "button" and init.name == L.OPT_RESET then
			ns.db.delay = 120
			init.onClick()
			check(ns.db.delay == 0, "reset button")
		end
	end
end)

step("addon compartment", function()
	AfkDelight_OnAddonCompartmentClick("AfkDelight", "LeftButton")
	check(#H.opened == 3, "left click opens options")
	AfkDelight_OnAddonCompartmentClick("AfkDelight", "RightButton")
	check(Screen:IsActive() and Screen.preview, "right click previews")
	AfkDelight_OnAddonCompartmentClick("AfkDelight", "RightButton")
	check(not Screen:IsActive(), "right click again closes")
	local button = CreateFrame("Frame", nil, UIParent)
	AfkDelight_OnAddonCompartmentEnter("AfkDelight", button)
	check(GameTooltip:IsShown() and GameTooltip.__owner == button, "tooltip")
	AfkDelight_OnAddonCompartmentLeave("AfkDelight", button)
	check(not GameTooltip:IsShown(), "tooltip hidden")
end)

step("layout survives resolution and scale changes", function()
	ns:SetOption("background", "AZEROTH")
	SlashCmdList.AFKDELIGHT("test")
	UIParent:SetSize(2560, 1080)
	H.Fire("DISPLAY_SIZE_CHANGED")
	H.Fire("UI_SCALE_CHANGED")
	check(Screen.width == 2560 and Screen.height == 1080, "new size used")
	check(math.abs(Screen.bodies[1].__width - 1080 * 0.42) < 1e-6 and math.abs(Screen.bodies[3].__width - 1080 * 0.07) < 1e-6, "Azeroth and her moons resized")
	check(math.abs(Screen.starDust.__texCoord[2] - 2560 / 512) < 1e-6, "star dust re-tiled")
	H.Advance(30)
	Close()
	UIParent:SetSize(1600, 900)
	H.Fire("DISPLAY_SIZE_CHANGED")
	ns:SetOption("background", "GALAXY")
end)

step("player title is shown", function()
	S.titleID = 42
	SlashCmdList.AFKDELIGHT("test")
	check(Screen.subtitle:IsShown() and Screen.subtitle:GetText() == "the Insane", "title " .. tostring(Screen.subtitle:GetText()))
	Close()
	S.titleName = ", Hand of A'dal"
	SlashCmdList.AFKDELIGHT("test")
	check(Screen.subtitle:GetText() == "Hand of A'dal", "comma titles trimmed")
	Close()
	S.titleID, S.titleName = 0, " the Insane"
end)

------------------------------------------------------------------------
elseif scenario == "forever" then
------------------------------------------------------------------------

S.level, S.maxLevel, S.xp, S.xpMax, S.rested, S.resting = 34, 60, 45000, 100000, 120000, false
S.name, S.surname, S.showSurname = "Aldric", "Stormwind", true
S.galaxyLoads = false
S.guild = false

step("load on WoW Forever", function()
	Load()
	check(ns.isForever == true, "detected Forever")
	check(ns.db.background == "AZEROTH", "Forever starts with the night sky of Azeroth")
	check(#H.settings.list > 0, "options registered")
end)

step("Forever character info: surname and leveling", function()
	GoAFK()
	H.Advance(1.25)
	check(Screen.sky:IsShown() and not Screen.galaxy:IsShown(), "moons, no galaxy attempt")
	check(Screen.name:GetText() == "Aldric-Stormwind", "surname shown " .. tostring(Screen.name:GetText()))
	check(not Screen.guild:IsShown(), "no guild line without a guild")
	check(Screen.details:GetText() == "Level 34 Void Elf Frost Mage", "details")
	local progress = Screen.progress:GetText()
	check(Screen.progress:IsShown() and contains(progress, "Level progress 45%") and contains(progress, "Rested XP 120%") and contains(progress, L.NOT_RESTING), "leveling line " .. tostring(progress))
	Close()
	Return()
	S.showSurname = false
	GoAFK()
	check(Screen.name:GetText() == "Aldric", "first name only when surnames are hidden")
	Close()
	Return()
end)

step("choosing the galaxy on Forever falls back to the night sky", function()
	ns:SetOption("background", "GALAXY")
	GoAFK()
	check(Screen.galaxy:IsShown() and not Screen.sky:IsShown(), "galaxy attempted")
	H.Advance(3.25)
	check(Screen.galaxy.__file == 1305790, "second attempt by file ID")
	local before = #H.printed
	H.Advance(3.25)
	check(Screen.galaxyUnavailable and not Screen.galaxy:IsShown(), "galaxy given up")
	check(Screen.sky:IsShown() and Screen.starfield:IsShown(), "night sky shown instead")
	check(printedSince(before, L.MSG_GALAXY_FALLBACK), "user told once")
	Close()
	Return()
	before = #H.printed
	GoAFK()
	H.Advance(7)
	check(Screen.sky:IsShown() and not Screen.galaxy:IsShown() and not printedSince(before, L.MSG_GALAXY_FALLBACK), "no retries or repeated messages")
	Close()
	Return()
end)

step("status reports Forever", function()
	local before = #H.printed
	SlashCmdList.AFKDELIGHT("status")
	check(printedSince(before, "World of Warcraft: Forever (interface 16001)"), "status " .. tostring(H.printed[#H.printed]))
end)

step("flyers follow the player's faction", function()
	local function Deal(count)
		Screen.flyerDeck, Screen.lastFlyer = nil, nil
		local dealt = {}
		for _ = 1, count do
			local flyer = Screen:NextFlyer()
			dealt[flyer.display] = (dealt[flyer.display] or 0) + 1
		end
		return dealt
	end
	S.faction = "Horde"
	local dealt = Deal(10)
	check(dealt[295] == 2 and dealt[1149] == nil, "Horde: the wind rider in every round, no gryphon")
	check(dealt[8570] == 2 and dealt[3212] == 2 and dealt[2717] == 2 and dealt[1267] == 2, "every flyer once per round")
	S.faction = "Neutral"
	dealt = Deal(6)
	check(dealt[295] == 1 and dealt[1149] == 1, "no faction yet: both mounts")
	S.faction = H.SECRET
	dealt = Deal(6)
	check(dealt[295] == 1 and dealt[1149] == 1, "secret faction handled safely")
	S.faction = "Alliance"
	Screen.flyerDeck, Screen.lastFlyer = nil, nil
end)

step("model without OnModelLoaded support still verifies by file ID", function()
	S.onModelLoaded = false
	S.galaxyLoads = true
	Screen.galaxyUnavailable, Screen.galaxyVerified = nil, nil
	GoAFK()
	H.Advance(3.25)
	check(Screen.galaxyVerified and Screen.galaxy:IsShown() and not Screen.sky:IsShown(), "verified through GetModelFileID")
	Close()
	Return()
end)

------------------------------------------------------------------------
elseif scenario == "upgrade" then
------------------------------------------------------------------------

-- Saved variables written by an early test build on the WoW Forever beta (settings version 1).
AfkDelightDB = { dbVersion = 1, enabled = true, background = "GALAXY", dismissOnInput = true, delay = 5, cameraSpinActive = false }

step("early beta settings are upgraded on WoW Forever", function()
	Load()
	check(ns.db.dbVersion == 2, "settings version bumped")
	check(ns.db.dismissOnInput == nil, "close-on-any-key setting removed")
	check(ns.db.background == "AZEROTH", "galaxy switched to the night sky on Forever")
	check(ns.db.delay == 5 and ns.db.dragonFlyby == true, "other settings kept, new ones added")
end)

------------------------------------------------------------------------
elseif scenario == "sanitize" then
------------------------------------------------------------------------

AfkDelightDB = { enabled = "yes", delay = 9999, background = "NEBULA", animation = 5, worldDim = -20, modelFacing = 400, cameraSpinActive = true, extra = "kept" }

step("bad saved variables are repaired", function()
	Load()
	check(ns.db.enabled == true, "wrong type replaced")
	check(ns.db.delay == 300 and ns.db.worldDim == 0 and ns.db.modelFacing == 180, "numbers clamped")
	check(ns.db.background == "GALAXY" and ns.db.animation == "RANDOM", "unknown choices replaced")
	check(ns.db.extra == "kept", "unknown keys left alone")
	check(ns.db.dbVersion == 2, "settings version set")
end)

step("a camera spin left running by a reload is stopped", function()
	check(H.moveViewStop == 1 and ns.db.cameraSpinActive == false, "MoveViewLeftStop at login")
end)

end

return failures, table.concat(results, "\n")
