-- Lint for the client's Lua 5.1; vendored libraries are excluded, as another addon does.
-- `globals` lists the only globals the addon sets; add each game global it reads to `read_globals`.
std = "lua51"
exclude_files = { "Libs/JigBoltgripToolkit", "Libs/AceLocale-3.0", "Libs/AceComm-3.0", "Libs/CallbackHandler-1.0", "Libs/LibStub" } -- the kit is linted in its own repository
globals = { "RecipeVacuumDB", "SlashCmdList", "SLASH_BOLTGRIP1", "BINDING_HEADER_JIGBOLTGRIPTOOLKIT" }
max_line_length = false
ignore = { "21./self", "212" }
read_globals = {
	"NUM_BAG_SLOTS", "C_Container", "IsAnyBagOpen", "C_Bank",
	"SetTextureWithAddressModeOptions",
	"RunNextFrame", "WowStyle1FilterDropdownStateEnabled", "WowStyle1FilterDropdownStateOver", "WowStyle1FilterDropdownStateDown", "WowStyle1FilterDropdownStateDownOver", "SMART_NAV_INPUT_DIRECTION", "SmartNavigation_AddJumpNavigationOverride", "SmartNavigation_ClearJumpNavigationOverridesInDirection", "TextureKitConstants", "PlaySound", "SOUNDKIT", "ITEM_MIN_SKILL", "MAP_PIN", "CUSTOMER_CRAFTING_ORDERS_BROWSE_NO_RESULTS", "TRADESKILL_REAGENT_COUNT", "PROFESSIONS_REAGENT_CONTAINER_LABEL", "RED_FONT_COLOR", "InCombatLockdown", "GetUIPanel", "DIFFICULT_DIFFICULTY_COLOR", "FAIR_DIFFICULTY_COLOR", "EASY_DIFFICULTY_COLOR", "TRIVIAL_DIFFICULTY_COLOR", "GameTooltip_AddBlankLineToTooltip",
	"CaseAccentInsensitiveParse", "Spell", "CUSTOM_GAMEPLAY_SETTINGS_ORDER", "GetBindingName", "CreateKeybindingEntryInitializer", "C_KeyBindings", "TRANSMOG_SOURCE_4", "GetRealZoneText", "CreateVector2D", "GetMinimapZoneText", "GetSubZoneText", "GetZoneText", "GetInstanceInfo", "C_MapExplorationInfo", "ADDONS", "Ambiguate", "BATTLE_PET_SOURCE_1", "BATTLE_PET_SOURCE_2", "BATTLE_PET_SOURCE_3", "BNET_CLIENT_WOW",
	"BNGetNumFriends", "C_AddOns", "C_BattleNet", "C_CVar", "C_ChatInfo", "C_EncodingUtil", "C_FriendList", "C_GossipInfo",
	"C_GuildInfo", "C_Item", "C_Map", "C_MerchantFrame", "C_QuestLog", "C_Spell", "C_SpellBook", "C_SuperTrack", "C_Texture",
	"C_Timer", "C_TooltipInfo", "TooltipDataProcessor", "C_TradeSkillUI", "ChatTypeInfo", "CopyTable", "COSTS_LABEL",
	"CreateAtlasMarkup", "CreateColor", "CreateFrame", "CreateSettingsButtonInitializer",
	"CreateSettingsListSectionHeaderInitializer", "date", "debugprofilestop", "debugstack", "RANK", "DISABLED_FONT_COLOR", "DEFAULT_CHAT_FRAME", "Enum",
	"ERR_CHAT_PLAYER_NOT_FOUND_S", "EventUtil", "FACTION_LABELS_FROM_STRING", "GameTooltip",
	"GameTooltip_AddColoredDoubleLine", "GameTooltip_AddColoredLine", "GameTooltip_AddDisabledLine",
	"GameTooltip_AddNormalLine", "GameTooltip_Hide", "GameTooltip_SetTitle", "GetBuildInfo", "GetLocale",
	"GetLootRollItemLink", "GetLootSlotLink", "GetLootSlotType", "GetLootSourceInfo", "GetMerchantItemID",
	"GetMerchantItemLink", "GetMerchantNumItems", "GetMoneyString", "GetNumGuildMembers", "GetNumLootItems",
	"GetNumQuestChoices", "GetNumQuestRewards", "GetNumTrainerServices", "GetPlayerInfoByGUID", "GetQuestID",
	"GetQuestItemInfo", "GetRealmID", "GetServerTime", "GetTime", "GetTrainerServiceCost",
	"GetTrainerServiceInfo", "GetTrainerServiceSkillReq", "GetTrainerServiceStepIndex",
	"GetTrainerServiceTypeFilter", "GRAY_FONT_COLOR", "GREEN_FONT_COLOR", "HIGHLIGHT_FONT_COLOR", "hooksecurefunc", "IsFishingLoot", "IsInGroup", "IsInGuild",
	"IsInInstance", "IsInRaid", "issecretvalue", "IsTradeskillTrainer", "Item", "LE_PARTY_CATEGORY_HOME",
	"LE_PARTY_CATEGORY_INSTANCE", "LibStub", "MISCELLANEOUS", "NORMAL_FONT_COLOR",
	"OPEN", "Professions", "ProfessionsFrame",
	"QUEST", "RAID_CLASS_COLORS", "REQUIRES_LABEL", "Settings",
	"SetTrainerServiceTypeFilter", "C_AddOnProfiler", "C_GamePad", "GetPhysicalScreenSize", "CONTEXT_ACTION_LABEL_OPEN", "FRIENDS", "KEY_BINDING", "COMBAT", "SOUND", "ScriptErrorsFrame", "GetProfessions", "GetProfessionInfo", "C_Container", "SOURCE", "strcmputf8i", "strjoin", "strsplit",
	"strtrim", "tContains", "TOOLTIP_DEFAULT_BACKGROUND_COLOR", "TOOLTIP_DEFAULT_COLOR", "tDeleteItem", "tostringall", "UiMapPoint",
	"UIParent", "UISpecialFrames", "UnitFactionGroup", "UnitGUID", "UnitInParty",
	"UnitInRaid", "UnitLevel", "UnitName", "UNKNOWN", "wipe", "WOW_PROJECT_ID",
}

-- The offline tests stand in for the client, so they define its globals on purpose.
files["tests"] = { std = "+busted", ignore = { "111", "112", "113", "121", "122", "142", "143", "211" } }
