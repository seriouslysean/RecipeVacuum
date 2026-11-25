local addonName, ns = ...

local LEVEL = ns.LEVEL

-- Player commands; Troubleshooting.lua adds diagnostics. One table drives the chat help and the Commands rows.
ns.commands = ns.commands or {}
table.insert(ns.commands, 1, { action = "", description = "Open the options", run = function()
	Settings.OpenToCategory(ns.module.category:GetID())
end })
table.insert(ns.commands, 2, { action = "export", description = "Copy your recorded sources to send to the author",
	note = "Opens a window with everything you have recorded yourself, as text, ready to copy and send to the author.", run = function()
	ns.ExportFinds()
end })

-- Called once saved variables load. Sections follow Blizzard's pages; labels are capitalized as Blizzard's are.
function ns.InitSettings()
	local toolkit = LibStub("JigBoltgripToolkit-1.0")
	local module = toolkit:RegisterModule(addonName, ns.device.class)
	ns.module = module
	toolkit:BuildOptions(module, ns.db, {
		{ heading = "Recipe Sources", place = "sources", rows = {
			{ kind = "cards", key = "sourceLevel", label = "Recipe Sources", default = LEVEL.FRIENDS,
				values = toolkit:SourceCards(ns.levelText),
				onChange = function()
					ns.SetSharing(ns.SharingWanted())
					ns.SourcesChanged()
				end },
			{ kind = "checkbox", key = "shareFinds", label = "Share My Finds", default = true,
				tooltip = "Send what you find to party, guild and friends who use Recipe Vacuum.",
				note = "Sends the trainers, vendors, quests and drops you find to your party, guild and friends who "
					.. "also use Recipe Vacuum. Nothing else is sent. Which of their finds you see is set by the cards above.",
				onChange = function() ns.SetSharing(ns.SharingWanted()) end },
		} },
		{ heading = "Personal Finds", place = "features", rows = {
			{ kind = "checkbox", key = "selfFound", label = "Record Personal Finds", default = true,
				tooltip = "Remember recipe sources from the trainers, vendors, quests and loot you see, even on characters without that profession." },
			{ kind = "checkbox", key = "announceNewFinds", label = "Announce New Finds", default = true, under = "selfFound",
				tooltip = "Print one message in your chat window after a visit with new recipe sources." },
		} },
	})
	toolkit:RegisterCommands(module, "recipevacuum", ns.commands)
	toolkit:FinishModule(module)
end
