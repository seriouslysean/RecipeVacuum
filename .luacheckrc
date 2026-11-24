-- Lint on the client's Lua (5.1); vendored libraries are not ours (another addon excludes its Libs
-- the same way). Reading WoW's API globals is not reported (113: there are thousands); writing
-- a global is, so nothing leaks into the shared global table by accident. The only globals
-- the addon sets are its saved variables and slash commands, listed here.
std = "lua51"
exclude_files = { "Libs/AceComm-3.0", "Libs/CallbackHandler-1.0", "Libs/LibStub" }
globals = { "RecipeVacuumDB", "SlashCmdList", "SLASH_BOLTGRIP1", "BINDING_HEADER_JIGBOLTGRIPTOOLKIT" }
max_line_length = false
ignore = { "113", "21./self", "212" }

-- The offline tests stand in for the client, so they define its globals on purpose.
files["tests"] = { ignore = { "111", "112", "121", "122", "142", "143", "211" } }
