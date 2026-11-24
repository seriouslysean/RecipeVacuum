local _, ns = ...

-- The listening level as three cards on the options page, laid out as the game shows a choice of
-- ruleset: a title, a round picture, a description. The chosen card has a gold border.
local LEVEL = ns.LEVEL
local TEMPLATE = "RecipeVacuumLevelCardsTemplate" -- LevelCards.xml; its height is the row's height
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = 184, 198, 12
local LEFT_INSET = 37        -- where Blizzard's own controls start on the page
local TITLE_TOP, ICON_TOP, ICON_SIZE = -14, -40, 48
local TEXT_TOP, TEXT_INSET = -100, 12
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- Blizzard's round portrait mask

local CARDS = {
	{ level = LEVEL.SELF, icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		text = "Only what you see yourself: trainers, vendors, quests and loot. Sharing is paused." },
	{ level = LEVEL.FRIENDS, icon = "Interface\\Icons\\INV_Misc_GroupLooking",
		text = "Also what your party, raid, guild and friends see, link or share." },
	{ level = LEVEL.PUBLIC, icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
		text = "Also recipes linked in public chat." },
}

local function CreateCard(parent, index, info, setting)
	local card = CreateFrame("Button", nil, parent, "TooltipBackdropTemplate")
	card:SetSize(CARD_WIDTH, CARD_HEIGHT)
	card:SetPoint("TOPLEFT", LEFT_INSET + (index - 1) * (CARD_WIDTH + CARD_GAP), 0)
	card.level = info.level

	local title = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, TITLE_TOP)
	title:SetText(ns.levelNames[info.level])

	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("TOP", 0, ICON_TOP)
	icon:SetTexture(info.icon)
	local mask = card:CreateMaskTexture()
	mask:SetAllPoints(icon)
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	icon:AddMaskTexture(mask)

	local text = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", TEXT_INSET, TEXT_TOP)
	text:SetPoint("RIGHT", -TEXT_INSET, 0)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("TOP")
	text:SetText(info.text)

	card:SetScript("OnClick", function()
		setting:SetValue(info.level)
	end)
	return card
end

-- Gold border on the chosen card, the tooltip's own gray on the others.
local function ShowChoice(frame, level)
	for _, card in ipairs(frame.cards) do
		local color = card.level == level and NORMAL_FONT_COLOR or TOOLTIP_DEFAULT_COLOR
		card:SetBackdropBorderColor(color:GetRGB())
	end
end

-- Adds the cards to an options layout, bound to the level setting.
function ns.AddLevelCards(layout, setting)
	local initializer = Settings.CreateElementInitializer(TEMPLATE, {})
	local shown -- the list's frame for this element while it is on screen
	-- The list builds the frame when it scrolls into view; the cards are made once per frame.
	function initializer:InitFrame(frame)
		if not frame.cards then
			frame.cards = {}
			for index, info in ipairs(CARDS) do
				frame.cards[index] = CreateCard(frame, index, info, setting)
			end
		end
		shown = frame
		ShowChoice(frame, setting:GetValue())
	end
	function initializer:Resetter()
		shown = nil
	end
	layout:AddInitializer(initializer)
	return function(level)
		if shown then
			ShowChoice(shown, level)
		end
	end
end
