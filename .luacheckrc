-- Lint on the client's Lua (5.1); vendored libraries are not ours (another addon excludes its Libs
-- the same way). The only globals the addon sets are its saved variables and slash commands
-- (`globals`). Every game global it reads is listed in `read_globals`, so a misspelled API name is
-- reported; add a name here when the code starts using one.
std = "lua51"
exclude_files = { "Libs/AceComm-3.0", "Libs/CallbackHandler-1.0", "Libs/LibStub" }
globals = { "RecipeVacuumDB", "SlashCmdList", "SLASH_BOLTGRIP1", "BINDING_HEADER_JIGBOLTGRIPTOOLKIT" }
max_line_length = false
ignore = { "21./self", "212" }
read_globals = {
	"ADDONS", "Ambiguate", "BATTLE_PET_SOURCE_1", "BATTLE_PET_SOURCE_2", "BATTLE_PET_SOURCE_3", "BNET_CLIENT_WOW",
	"BNGetNumFriends", "C_AddOns", "C_BattleNet", "C_ChatInfo", "C_EncodingUtil", "C_FriendList", "C_GossipInfo",
	"C_GuildInfo", "C_Item", "C_Map", "C_MerchantFrame", "C_QuestLog", "C_Spell", "C_SuperTrack", "C_Texture",
	"C_Timer", "C_TooltipInfo", "C_TradeSkillUI", "ChatTypeInfo", "CHECK_ALL", "CopyTable", "COSTS_LABEL",
	"CreateAtlasMarkup", "CreateFrame", "CreateSettingsButtonInitializer",
	"CreateSettingsListSectionHeaderInitializer", "date", "debugprofilestop", "DEFAULT_CHAT_FRAME", "Enum",
	"ERR_CHAT_PLAYER_NOT_FOUND_S", "EventRegistry", "EventUtil", "FACTION_LABELS_FROM_STRING", "GameTooltip",
	"GameTooltip_AddColoredDoubleLine", "GameTooltip_AddColoredLine", "GameTooltip_AddDisabledLine",
	"GameTooltip_AddNormalLine", "GameTooltip_Hide", "GameTooltip_SetTitle", "GetBuildInfo", "GetLocale",
	"GetLootRollItemLink", "GetLootSlotLink", "GetLootSlotType", "GetLootSourceInfo", "GetMerchantItemID",
	"GetMerchantItemLink", "GetMerchantNumItems", "GetMoneyString", "GetNumGuildMembers", "GetNumLootItems",
	"GetNumQuestChoices", "GetNumQuestRewards", "GetNumTrainerServices", "GetPlayerInfoByGUID", "GetQuestID",
	"GetQuestItemInfo", "GetRealmID", "GetServerTime", "GetTime", "GetTrainerServiceCost",
	"GetTrainerServiceInfo", "GetTrainerServiceSkillReq", "GetTrainerServiceStepIndex",
	"GetTrainerServiceTypeFilter", "GRAY_FONT_COLOR", "HandleModifiedItemClick", "HelpTip",
	"HIGHLIGHT_FONT_COLOR", "hooksecurefunc", "InCombatLockdown", "IsFishingLoot", "IsInGroup", "IsInGuild",
	"IsInInstance", "IsInRaid", "issecretvalue", "IsTradeskillTrainer", "Item", "LE_PARTY_CATEGORY_HOME",
	"LE_PARTY_CATEGORY_INSTANCE", "LibStub", "Menu", "MenuResponse", "MISCELLANEOUS", "NORMAL_FONT_COLOR",
	"OPEN", "OpenMapToUserWaypoint", "PROFESSION_RECIPES_SHOW_UNLEARNED", "Professions", "ProfessionsFrame",
	"ProfessionsUtil", "QUEST", "REQUIRES_LABEL", "ScrollBoxConstants", "ScrollUtil", "Settings",
	"SetTrainerServiceTypeFilter", "SHOW_MAP", "SOURCE", "SOURCES", "strcmputf8i", "strjoin", "strsplit",
	"strtrim", "tContains", "tDeleteItem", "tostringall", "TRADESKILL_UNLEARNED_RECIPE_HEADER", "UiMapPoint",
	"UIParent", "UISpecialFrames", "UNAVAILABLE", "UNCHECK_ALL", "UnitFactionGroup", "UnitGUID", "UnitInParty",
	"UnitInRaid", "UnitLevel", "UnitName", "UNKNOWN", "wipe", "WOW_PROJECT_ID",
}

-- The offline tests stand in for the client, so they define its globals on purpose.
files["tests"] = { ignore = { "111", "112", "113", "121", "122", "142", "143", "211" } }
