-- AceLocale-3.0: the key is the English text, and `true` means "the key as written". Only player text is
-- here (docs/development.md, "Translations").
local addonName = ...
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true)

-- The voiced line (Voice.lua): noise, then the report.
L["whirs and rattles"] = true
L["Intake complete! %d recipe from %s!"] = true
L["Intake complete! %d recipes from %s!"] = true
L["%d recipe seen!"] = true
L["%d recipes seen!"] = true
L["Map pin set! %s marked on your map!"] = true

-- Panel (Panel.lua)
L["Skill %d to %d"] = true
L["[%d]"] = true
L["%d / %d discovered"] = true
L["%d discovered"] = true
L["Recipes you have found and can still learn in this profession."] = true
L["Recipes found out of all the ones you can still learn in this profession."] = true
L["Reagents"] = true
L["Press to mark this place on your map."] = true
L["dev"] = true

-- Options (Settings.lua)
L["Recipe Sources"] = true
L["Tracks only recipes you see for yourself."] = true
L["Also tracks recipes people link in chat."] = true
L["Share My Finds"] = true
L["Send what you find to party, guild and friends who use Recipe Vacuum."] = true
L["Sends your trainers, vendors, quests and drops to friends who use Recipe Vacuum. Nothing else is sent."] = true
L["Personal Finds"] = true
L["Track Personal Finds"] = true
L["Remembers the trainers, vendors, quests and loot you see, on every character."] = true
L["Announce New Finds"] = true
L["Print a message in chat after visits and windows with new recipes."] = true

-- Commands (Settings.lua)
L["Open the options"] = true
L["Copy the recipe sources you found"] = true
L["Opens a window of every recipe source you found, ready to copy."] = true

-- Tooltips (Sources.lua)
L["Trainer"] = true
L["Zone Drop"] = true
L["Seen %d time"] = true
L["Seen %d times"] = true
L["from %d creature"] = true
L["from %d creatures"] = true
L["in %d zone"] = true
L["in %d zones"] = true
L["and %d more"] = true

-- The rank mark's tooltip (Ranks.lua)
L["Click to pin the first of %d places."] = true

-- Chat (Core.lua)
L["Saved data is from a newer version of Recipe Vacuum; it was left unchanged."] = true
