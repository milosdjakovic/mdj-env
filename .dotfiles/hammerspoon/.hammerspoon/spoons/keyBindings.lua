local AppIdentifiers = require("spoons.appIdentifiers")

local HYPER = { "shift", "ctrl", "alt", "cmd" }

-- Define window management bindings
local windowBindings = {
	{ description = "Maximize", modifiers = { "ctrl", "alt" }, key = "return" },
	{ description = "Center", modifiers = { "ctrl", "alt" }, key = "C" },
	{ description = "Full Height Reasonable Width", modifiers = { "ctrl", "alt" }, key = "up" },
	{ description = "Almost maximize", modifiers = { "ctrl", "alt" }, key = "down" },
	{ description = "Left half", modifiers = { "ctrl", "alt" }, key = "left" },
	{ description = "Right half", modifiers = { "ctrl", "alt" }, key = "right" },
	{ description = "Reasonable size", modifiers = { "ctrl", "alt" }, key = "X" },
	{ description = "Small size", modifiers = { "ctrl", "alt" }, key = "Z" },
	{ description = "Increase size", modifiers = { "ctrl", "alt" }, key = "=" },
	{ description = "Decrease size", modifiers = { "ctrl", "alt" }, key = "-" },
	{ description = "Next display", modifiers = { "ctrl", "alt", "cmd" }, key = "right" },
	{ description = "Previous display", modifiers = { "ctrl", "alt", "cmd" }, key = "left" },
	{ description = "Hide all except focused", modifiers = { "ctrl", "alt" }, key = "H" },
	{ description = "Screen recording", modifiers = { "ctrl", "alt" }, key = "R" },
	{ description = "Move left", modifiers = { "ctrl", "alt", "shift" }, key = "left" },
	{ description = "Move right", modifiers = { "ctrl", "alt", "shift" }, key = "right" },
	{ description = "Move up", modifiers = { "ctrl", "alt", "shift" }, key = "up" },
	{ description = "Move down", modifiers = { "ctrl", "alt", "shift" }, key = "down" },
}

-- Define app toggles
local appToggles = {
	-- First character:
	{
		description = "Books",
		appIdentifier = AppIdentifiers.Books,
		modifiers = HYPER,
		key = "B",
	},
	{
		description = "Google Chrome",
		appIdentifier = AppIdentifiers.GoogleChrome,
		modifiers = HYPER,
		key = "C",
	},
	{
		description = "Docker",
		appIdentifier = AppIdentifiers.Docker,
		modifiers = HYPER,
		key = "D",
	},
	{
		description = "Finder",
		appIdentifier = AppIdentifiers.Finder,
		modifiers = HYPER,
		key = "F",
	},
	{
		description = "Mail",
		appIdentifier = AppIdentifiers.Mail,
		modifiers = HYPER,
		key = "M",
	},
	{
		description = "Obsidian",
		appIdentifier = AppIdentifiers.Obsidian,
		modifiers = HYPER,
		key = "O",
	},
	{
		description = "Safari",
		appIdentifier = AppIdentifiers.Safari,
		modifiers = HYPER,
		key = "S",
	},
	{
		description = "Visual Studio Code",
		appIdentifier = AppIdentifiers.VisualStudioCode,
		modifiers = HYPER,
		key = "V",
	},
	{
		description = "PyCharm",
		appIdentifier = AppIdentifiers.PyCharm,
		modifiers = HYPER,
		key = "P",
	},
	{
		description = "Notes",
		appIdentifier = AppIdentifiers.Notes,
		modifiers = HYPER,
		key = "N",
	},
	{
		description = "iPhone Mirroring",
		appIdentifier = AppIdentifiers.iPhoneMirroring,
		modifiers = HYPER,
		key = "I",
	},
	{
		description = "Zed",
		appIdentifier = AppIdentifiers.Zed,
		modifiers = HYPER,
		key = "Z",
	},
	-- Second character:
	{
		description = "Bruno",
		appIdentifier = AppIdentifiers.Bruno,
		modifiers = HYPER,
		key = "R",
	},
	{
		description = "Stickies",
		appIdentifier = AppIdentifiers.Stickies,
		modifiers = HYPER,
		key = "T",
	},
	{
		description = "Slack",
		appIdentifier = AppIdentifiers.Slack,
		modifiers = HYPER,
		key = "L",
	},
	{
		description = "Cursor",
		appIdentifier = AppIdentifiers.Cursor,
		modifiers = HYPER,
		key = "U",
	},
	{
		description = "ChatGPT",
		appIdentifier = AppIdentifiers.ChatGPT,
		modifiers = HYPER,
		key = "H",
	},
	-- Third character:
	{
		description = "Claude",
		appIdentifier = AppIdentifiers.Claude,
		modifiers = HYPER,
		key = "A",
	},
	-- Disabled:
	-- { description = "ChatGPT Atlas",      appIdentifier = AppIdentifiers.ChatGPTAtlas,     modifiers = HYPER, key = "A" },
	-- { description = "Android Studio",     appIdentifier = AppIdentifiers.AndroidStudio,    modifiers = HYPER, key = "A" },
	-- { description = "Hammerspoon",        appIdentifier = AppIdentifiers.Hammerspoon,      modifiers = HYPER, key = "H" },
	-- { description = "TablePlus",          appIdentifier = AppIdentifiers.TablePlus,        modifiers = HYPER, key = "P" },
	-- { description = "Xcode",              appIdentifier = AppIdentifiers.Xcode,            modifiers = HYPER, key = "X" },
}

local stageManager = {
	description = "Toggle Stage Manager",
	modifiers = { "ctrl", "alt" },
	key = "M",
}

local terminalHandlerBindings = {
	description = "Toggle Terminal",
	modifiers = { "alt" },
	key = "`",
}

return {
	windowBindings = windowBindings,
	appToggles = appToggles,
	stageManager = stageManager,
	terminalHandlerBindings = terminalHandlerBindings,
}
