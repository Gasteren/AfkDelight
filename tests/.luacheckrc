std = "lua51"
max_line_length = false
self = false
unused_args = false

-- Globals the addon defines.
globals = {
	"AfkDelightDB",
	"SLASH_AFKDELIGHT1",
	"SLASH_AFKDELIGHT2",
	"AfkDelight_OnAddonCompartmentClick",
	"AfkDelight_OnAddonCompartmentEnter",
	"AfkDelight_OnAddonCompartmentLeave",
	SlashCmdList = { other_fields = true },
}

-- WoW API used directly (each one verified against the live 12.1.5 and forever 1.60.1 UI source).
read_globals = {
	"Ambiguate", "C_AddOns", "C_ChatInfo", "C_ClassColor", "C_EventUtils", "C_PetBattles", "C_PlayerInfo",
	"C_Texture", "C_Timer", "CreateColor", "CreateFrame", "CreateSettingsButtonInitializer",
	"CreateSettingsListSectionHeaderInitializer", "FlashClientIcon", "GameTooltip", "GetAverageItemLevel",
	"GetBattlefieldStatus", "GetBindingByKey", "GetBuildInfo", "GetCurrentTitle", "GetGuildInfo", "GetLocale",
	"GetMaxLevelForPlayerExpansion", "GetMoney", "GetPlayerInfoByGUID", "GetRealZoneText", "GetSpecialization",
	"GetSpecializationInfo", "GetSubZoneText", "GetTime", "IsShiftKeyDown", "GetTitleName", "GetXPExhaustion", "GetZoneText",
	"InCombatLockdown", "IsInGuild", "IsInInstance", "IsResting", "IsXPUserDisabled",
	"MinimalSliderWithSteppersMixin", "Settings", "UIParent", "UnitAffectingCombat", "UnitCastingInfo",
	"UnitChannelInfo", "UnitClass", "UnitIsAFK", "UnitLevel", "UnitName", "UnitRace", "UnitXP", "UnitXPMax",
	"date", "geterrorhandler", "strtrim",
}
