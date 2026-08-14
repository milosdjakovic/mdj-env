-- Turning a list of plugin directories into loaded, initialized modules, keyed by identity.
--
-- The live root wired every plugin the same way, one dofile, one assignment, and for three
-- plugins out of twenty four, one extra init call written in by hand because that plugin
-- happened to need it. This file is the mechanical collapse of that whole block into one
-- pass. It calls init uniformly on whatever loaded, so the parity gap closes by construction
-- rather than by the composition root naming three exceptions again in a new place.
--
-- This module names no plugin, reads no manifest, and holds no roster. Everything about
-- which directories exist and what to call the result of loading each one arrives as plain
-- arguments from the composition root, which is the only file allowed to know any of that.
-- Adding, removing, or renaming a plugin never touches this file.
--
-- This module also never calls configure, never calls start, and never binds a key. It runs
-- after the shared atoms are configured and before the plan is resolved, since resolving a
-- plan checks a sibling capability against the real module here, not against a manifest.

local obj = {}

--- obj.modules(configdir, dirs, names, identityOf, log)
--- Walks every entry of names, dofiles that plugin's init.lua, calls init on whatever loaded
--- when there is one to call, and hands back the result keyed by identity.
---
--- configdir is the base path every plugin directory hangs off, the same root the live root
--- passed as hs.configdir. dirs maps each entry of names to the base it lives under, since
--- some plugins sit under plugins and some sit under host, and this module has no opinion
--- about which, it only concatenates what it is given. identityOf turns a directory name into
--- the name a plugin answers to everywhere outside its own directory, or answers nothing when
--- the two already agree, in which case the directory name itself is the key. log is used for
--- one line per failure and is never required to be present.
---
--- Returns two tables. The first is every module that loaded, keyed by identity. The second is
--- every failure, keyed by directory name, holding the error string, whether the failure was
--- the file not loading at all or its init raising once it did.
function obj.modules(configdir, dirs, names, identityOf, log)
  local modules = {}
  local failures = {}

  for _, name in ipairs(names or {}) do
    local base = dirs and dirs[name]

    -- A name with no matching entry in dirs has nowhere to be found, so this is a failure
    -- in its own right rather than a guess at a base, since a guess could just as easily
    -- load the wrong file with no error to show for it.
    if base == nil then
      local reason = "no directory entry for '" .. tostring(name) .. "'"
      failures[name] = reason
      if log then
        log.e("plugin '" .. tostring(name) .. "' has no directory entry, its init.lua cannot be found")
      end
    else
      local path = configdir .. base .. name .. "/init.lua"
      local ok, mod = pcall(dofile, path)

      if not ok then
        failures[name] = mod
        if log then
          log.e("plugin '" .. tostring(name) .. "' failed to load, " .. tostring(mod))
        end
      else
        local key = identityOf and identityOf(name)
        if key == nil or key == "" then
          key = name
        end
        modules[key] = mod

        -- Every init in this tree is written with a colon, so it is called the same way here
        -- for whatever loaded, rather than only for the few plugins the live root remembered
        -- to call it on by hand. A raised init is caught and recorded rather than let through,
        -- since one plugin's init raising must not stop every plugin after it from loading.
        if type(mod) == "table" and type(mod.init) == "function" then
          local okInit, err = pcall(mod.init, mod)
          if not okInit then
            failures[name] = err
            if log then
              log.e("plugin '" .. tostring(name) .. "' raised in init, " .. tostring(err))
            end
          end
        end
      end
    end
  end

  return modules, failures
end

--- obj.mirror(modules, globals)
--- A compatibility shim for the one runtime reader of a spoon global left in this tree, the
--- BrowserTabs test harness. Given a map from a modules key to the global name it should
--- appear under, this writes each named module onto the running spoon table. Given no map,
--- which is the default, this does nothing at all, since mirroring is a named opt in for the
--- one caller that still needs it rather than a rule every module is held to.
function obj.mirror(modules, globals)
  if not globals then
    return
  end
  for key, globalName in pairs(globals) do
    if modules[key] ~= nil then
      spoon[globalName] = modules[key]
    end
  end
end

return obj
