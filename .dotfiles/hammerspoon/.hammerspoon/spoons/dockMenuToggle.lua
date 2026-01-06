local DockMenuToggle = {}

local function readSetting(domain, key)
    return hs.execute("defaults -currentHost read " .. domain .. " " .. key)
end

local function writeSetting(domain, key, value)
    hs.execute("defaults -currentHost write " .. domain .. " " .. key .. " -int " .. value)
end

local function toggleDock(newState)
    writeSetting("com.apple.dock", "autohide", newState)
    hs.execute([[osascript -e 'tell application "System Events" to tell dock preferences to set autohide to ]] ..
                   (newState == "1" and "true" or "false") .. "'")
end

local function toggleMenuBar(newState)
    writeSetting("NSGlobalDomain", "_HIHideMenuBar", newState)
    hs.execute(
        [[osascript -e 'tell application "System Events" to tell dock preferences to set autohide menu bar to ]] ..
            (newState == "1" and "true" or "false") .. "'")
end

function DockMenuToggle.initialize()
    hs.hotkey.bind({"ctrl", "alt"}, "d", function()
        local currentState = readSetting("com.apple.dock", "autohide")
        local newState = currentState:match("1") and "0" or "1"

        toggleDock(newState)
        toggleMenuBar(newState)
    end)
end

return DockMenuToggle
