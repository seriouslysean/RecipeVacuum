-- AceLocale-3.0: the key is the English text, and `true` means "the key as written". Only player text is
-- here (docs/development.md, "Translations").
local addonName = ...
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true)

-- The voiced line (Voice.lua): noise, then the report.
L["whirs and rattles"] = true
L["Intake complete! %d recipe from %s!"] = true
L["Intake complete! %d recipes from %s!"] = true

-- Options (Settings.lua)
L["Recipe Sources"] = true
L["recipes"] = true -- what the sources cards track
L["recipes people link in chat"] = true
L["Share My Finds"] = true
L["Send what you find to party, guild and friends who use Recipe Vacuum."] = true
L["Sends your trainers, vendors, quests and drops to friends who use Recipe Vacuum. Nothing else is sent."] = true
L["Personal Finds"] = true
L["Track Personal Finds"] = true
L["Remembers the trainers, vendors, quests and loot you see, on every character."] = true
L["Announce New Finds"] = true
L["Print one message in your chat window after a visit with new recipe sources."] = true

-- Commands (Settings.lua)
L["Open the options"] = true
L["Copy the recipe sources you found"] = true
L["Opens a window of every recipe source you found, ready to copy."] = true

-- Tooltips and the recipe pane (Sources.lua, RecipePanel.lua)
L["Trainer"] = true
L["Zone Drop"] = true
L["Seen %d time"] = true
L["Seen %d times"] = true
L["from %d creature"] = true
L["from %d creatures"] = true
L["in %d zone"] = true
L["in %d zones"] = true
L["and %d more"] = true

-- The first-run tip (Heard.lua); the argument is one of the three below.
L["Your Recipe Vacuum is humming! Recipes you come across land in this list. Right now it listens to %s. You can change that in Options."] = true
L["only you"] = true
L["you and your friends"] = true
L["you, your friends and recipes people link in chat"] = true

-- Chat (Core.lua)
L["Saved data is from a newer version of Recipe Vacuum; it was left unchanged."] = true
