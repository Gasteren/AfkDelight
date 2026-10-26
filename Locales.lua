--[[
	AfkDelight - Locales.lua
	By Frost-Lightbringer
	License: http://creativecommons.org/licenses/by-nc-sa/2.5

	English strings live here. Wherever the game already ships a translated string
	(Blizzard "global strings"), that string is used, so many labels are localized
	automatically. To translate the rest, add a block like the deDE example at the
	bottom of this file.
]]

local _, ns = ...

-- Missing keys fall back to the key itself, so a typo never causes a Lua error.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

local G = _G

-- AFK screen
L.AWAY_TITLE = G.DEFAULT_AFK_MESSAGE or "Away from Keyboard"
L.AWAY_FOR = "Away for %s"
L.PREVIEW = "Preview"
L.HINT_CLOSE = "Press Escape or click Close to return"
L.HINT_PREVIEW = "Preview - press Escape or click Close"
L.CLOSE = G.CLOSE or "Close"
L.CHAT_HEADER = "While you were away"
L.CHAT_HELP = "Mouse wheel or Page Up/Down to scroll, Tab to switch"
L.TAB_FORMAT = "%s (%d)"
L.TAB_WHISPERS = "Whispers"
L.TAB_GUILD = G.GUILD or "Guild"
L.TAB_GROUP = G.GROUP or "Group"
L.EMPTY_WHISPERS = "No missed whispers."
L.EMPTY_GUILD = "No missed guild messages."
L.EMPTY_GROUP = "No missed party or raid messages."
L.LEVEL = G.LEVEL or "Level"
L.ITEM_LEVEL = G.STAT_AVERAGE_ITEM_LEVEL or "Item Level"
L.XP_LINE = "Level progress %d%%"
L.RESTED_LINE = "Rested XP %d%%"
L.RESTED_GAIN = "+%d%% while away"
L.NOT_RESTING = "not in a rested area"
L.SAMPLE_NAME_1 = "Jaina"
L.SAMPLE_NAME_2 = "Thrall"
L.SAMPLE_NAME_3 = "Bolvar"
L.SAMPLE_WHISPER = "Are you around? We start in 10 minutes!"
L.SAMPLE_GUILD = "Anyone up for a dungeon later?"
L.SAMPLE_GROUP = "Ready check in 5, grab your consumables!"

-- Chat output
L.SUMMARY = "Welcome back! You were away for %s."
L.SUMMARY_MISSED = "Missed: %s."
L.MISSED_WHISPERS = "%d |4whisper:whispers;"
L.MISSED_GUILD = "%d guild |4message:messages;"
L.MISSED_GROUP = "%d group |4message:messages;"
L.SUMMARY_MONEY = "Money: %s."
L.SUMMARY_RESTED = "Rested XP: +%d%% of a level."
L.MSG_ENABLED = "AFK screen enabled."
L.MSG_DISABLED = "AFK screen disabled."
L.MSG_RESET = "All settings were reset to their defaults."
L.MSG_COMBAT = "That isn't available during combat."
L.MSG_NO_SETTINGS = "The options panel isn't available. Type /afkd help for commands."
L.HELP_HEADER = "Commands:"
L.HELP_OPTIONS = "%s - open the options"
L.HELP_TEST = "%s test - preview the AFK screen"
L.HELP_TOGGLE = "%s on | off - enable or disable the AFK screen"
L.HELP_RESET = "%s reset - restore the default settings"
L.HELP_STATUS = "%s status - show version and state"
L.STATUS_LINE = "Version %s, %s (interface %s). Screen %s. AFK status: %s."
L.STATUS_ENABLED = "enabled"
L.STATUS_DISABLED = "disabled"
L.STATUS_HIDDEN = "hidden by the game here"
L.FLAVOR_RETAIL = "World of Warcraft (Retail)"
L.FLAVOR_FOREVER = "World of Warcraft: Forever"
L.YES = G.YES or "Yes"
L.NO = G.NO or "No"
L.COMPARTMENT_LEFT = "|cffffd100Left-click:|r open options"
L.COMPARTMENT_RIGHT = "|cffffd100Right-click:|r preview the AFK screen"

-- Options panel
L.OPT_GENERAL = G.GENERAL or "General"
L.OPT_ENABLED = "Enable AFK screen"
L.OPT_ENABLED_TT = "Show the AfkDelight screen while you are flagged as Away from Keyboard (/afk or idle)."
L.OPT_DELAY = "Delay before showing"
L.OPT_DELAY_TT = "Wait this long after you go AFK before the screen appears."
L.OPT_INSTANT = "Instant"
L.OPT_SECONDS = "%d sec"
L.OPT_NO_INSTANCES = "Don't show inside instances"
L.OPT_NO_INSTANCES_TT = "Never show the screen inside instances such as delves, scenarios and battlegrounds.\n\nNote: inside dungeons, raids, Mythic+ and rated PvP the game hides your AFK status from addons, so the screen can't appear there in any case."
L.OPT_DISMISS_POPUPS = "Close for important events"
L.OPT_DISMISS_POPUPS_TT = "Close the screen for ready checks, queue pops, role checks, group invites, summons, resurrections, duels, trades and logout warnings, so they are never hidden behind it."
L.OPT_SUMMARY = "Show a summary when you return"
L.OPT_SUMMARY_TT = "Print how long you were away, how many whispers you received and what changed in your chat window when you come back."

L.OPT_APPEARANCE = G.APPEARANCE_LABEL or "Appearance"
L.OPT_BACKGROUND = "Background"
L.OPT_BACKGROUND_TT = "Choose what is shown behind your character."
L.BG_AZEROTH = "Azeroth"
L.BG_AZEROTH_TT = "Azeroth slowly spinning over a twinkling starfield, painted with the game's own sky texture."
L.BG_STARFIELD = "Animated starfield"
L.BG_STARFIELD_TT = "Twinkling stars and the odd shooting star."
L.BG_WORLD = "Game world"
L.BG_WORLD_TT = "Fades out your interface and shows the game world, optionally with a slowly spinning camera."
L.BG_SOLID = "Solid black"
L.BG_SOLID_TT = "A plain dark background."
L.OPT_WORLD_DIM = "Darken game world"
L.OPT_WORLD_DIM_TT = "How much to darken the game world when the Game world background is used."
L.OPT_CAMERA_SPIN = "Spin the camera"
L.OPT_CAMERA_SPIN_TT = "Slowly rotate the camera around your character when the Game world background is used."
L.OPT_SHOW_MODEL = "Show your character"
L.OPT_SHOW_MODEL_TT = "Show a large model of your character, including your transmog."
L.OPT_ANIMATION = "Character animation"
L.OPT_ANIMATION_TT = "What your character does while you are away."
L.ANIM_RANDOM = "Random emotes"
L.ANIM_STAND = "Stand"
L.ANIM_DANCE = "Dance"
L.ANIM_TALK = "Talk"
L.OPT_INTRO_WAVE = "Wave when the screen appears"
L.OPT_INTRO_WAVE_TT = "Your character turns to you and waves before going back to the chosen animation."
L.OPT_FACING = "Character facing"
L.OPT_FACING_TT = "The direction your character looks. -110 is the classic AfkDelight pose, gazing at Azeroth."
L.OPT_DEGREES = "%d°"
L.OPT_MODEL_SPIN = "Slowly turn your character"
L.OPT_MODEL_SPIN_TT = "Continuously rotate the character model like a display stand."
L.OPT_MODEL_SCALE = "Character size"
L.OPT_MODEL_SCALE_TT = "Size of the character model, relative to the screen height."
L.OPT_PERCENT = "%d%%"

L.OPT_INFO = "Information"
L.OPT_SHOW_INFO = "Show character information"
L.OPT_SHOW_INFO_TT = "Show your name, title, level, specialization, guild, item level, zone and leveling progress."
L.OPT_SHOW_CLOCK = "Show clock"
L.OPT_SHOW_CLOCK_TT = "Show the time and date. Follows the local/realm time and 24-hour settings of the game clock."
L.OPT_SHOW_CHAT = "Show messages received while away"
L.OPT_SHOW_CHAT_TT = "List the whispers (and optionally guild and group chat) you receive while away, each in its own tab. Scroll with the mouse wheel or Page Up/Down, and switch tabs with Tab."
L.OPT_CHAT_GUILD = "Guild tab"
L.OPT_CHAT_GUILD_TT = "Also collect guild and officer chat, in its own tab."
L.OPT_CHAT_GROUP = "Group tab"
L.OPT_CHAT_GROUP_TT = "Also collect party, raid and instance chat, in its own tab."
L.OPT_FLASH = "Flash the taskbar on whispers"
L.OPT_FLASH_TT = "Flash the game's taskbar icon when someone whispers you while you are away."

L.OPT_TOOLS = "Tools"
L.OPT_PREVIEW = "Preview the AFK screen"
L.OPT_PREVIEW_BUTTON = "Preview"
L.OPT_PREVIEW_TT = "Show the screen right now. Press Escape or click Close to close it."
L.OPT_RESET = "Reset all settings"
L.OPT_RESET_BUTTON = G.RESET or "Reset"
L.OPT_RESET_TT = "Restore every AfkDelight setting to its default value."

--[[ Example translation block:
if GetLocale() == "deDE" then
	L.AWAY_FOR = "Abwesend seit %s"
	L.HINT_CLOSE = "Escape drücken oder auf Schließen klicken, um zurückzukehren"
end
]]
