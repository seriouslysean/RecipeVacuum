local _, ns = ...

-- The listening level as three cards on the options page, laid out like the game's ruleset choice.
local LEVEL = ns.LEVEL
local TEMPLATE = "RecipeVacuumLevelCardsTemplate" -- LevelCards.xml sets the row height
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = 184, 198, 12
local LEFT_INSET = 37 -- where Blizzard's own controls start
local TITLE_TOP, ICON_TOP, ICON_SIZE = -14, -40, 48
local TEXT_TOP, TEXT_INSET = -100, 12
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- Blizzard's round portrait mask

local CARDS = {
	{ level = LEVEL.SELF, icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
	{ level = LEVEL.FRIENDS, icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
	{ level = LEVEL.PUBLIC, icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
}
-- The chosen card is lit and ticked, the others dimmed.
local UNCHOSEN_ALPHA = 0.55
local CHECK_TEXTURE, CHECK_SIZE, CHECK_INSET = "Interface\\Buttons\\UI-CheckBox-Check", 28, 4
local CHOSEN_BACKGROUND = CreateColor(0.16, 0.13, 0.05)

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
	text:SetPoint("TOPRIGHT", -TEXT_INSET, TEXT_TOP) -- both anchors on one line: the width is set, the height free to wrap
	text:SetJustifyH("CENTER")
	text:SetJustifyV("TOP")
	text:SetText(ns.levelText[info.level])

	local check = card:CreateTexture(nil, "OVERLAY")
	check:SetSize(CHECK_SIZE, CHECK_SIZE)
	check:SetPoint("TOPRIGHT", -CHECK_INSET, -CHECK_INSET)
	check:SetTexture(CHECK_TEXTURE)
	card.Title, card.Icon, card.Check = title, icon, check
	card:SetScript("OnEnter", function() card:SetAlpha(1) end)
	card:SetScript("OnLeave", function() card:SetAlpha(card.chosen and 1 or UNCHOSEN_ALPHA) end)

	card:SetScript("OnClick", function()
		setting:SetValue(info.level)
	end)
	return card
end

local function ShowChoice(frame, level)
	for _, card in ipairs(frame.cards) do
		local chosen = card.level == level
		card:SetBackdropBorderColor((chosen and NORMAL_FONT_COLOR or TOOLTIP_DEFAULT_COLOR):GetRGB())
		card:SetBackdropColor((chosen and CHOSEN_BACKGROUND or TOOLTIP_DEFAULT_BACKGROUND_COLOR):GetRGB())
		card.Title:SetTextColor((chosen and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
		card.Icon:SetDesaturated(not chosen)
		card.Check:SetShown(chosen)
		card.chosen = chosen
		card:SetAlpha((chosen or card:IsMouseOver()) and 1 or UNCHOSEN_ALPHA)
	end
end

-- Binds the cards to the level setting.
function ns.AddLevelCards(layout, setting)
	local initializer = Settings.CreateElementInitializer(TEMPLATE, {})
	local shown -- the frame while on screen
-- The list builds the frame when it scrolls into view; cards are made once per frame.
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
