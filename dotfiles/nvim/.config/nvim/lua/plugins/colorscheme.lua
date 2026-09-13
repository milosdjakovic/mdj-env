-- Aura, for both appearances.
--
-- The colours and the highlight work live in colors/aura.lua and lua/aura/, so this file is
-- only the plugin wiring. That split is deliberate. A colorscheme has to be loadable by name
-- from Neovim's own :colorscheme machinery, which is what lets the appearance switch work
-- without a watcher, and a lazy.nvim spec cannot be loaded that way.
return {
  {
    "daltonmenezes/aura-theme",
    lazy = false,
    priority = 1000,
    -- The Lua modules sit under packages/neovim rather than at the repository root, so the
    -- runtimepath needs the subdirectory before anything can require them. This runs in init
    -- rather than config because lazy.nvim runs every init before any config, and LazyVim
    -- sets the colorscheme from its own config at priority 10000.
    init = function(plugin)
      vim.opt.rtp:append(plugin.dir .. "/packages/neovim")
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aura",
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    -- Registered in init so it exists from startup. lazy.nvim runs every init eagerly, where
    -- LazyVim's own autocmds file waits for VeryLazy, which never arrives without a UI.
    -- Calling lualine.setup from inside the colorscheme itself is the other thing that does
    -- not work, since it makes lazy.nvim resolve this plugin's opts, and LazyVim's lualine
    -- config reaches for Snacks before it exists that early in startup.
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "aura",
        callback = function()
          -- package.loaded rather than pcall(require). Requiring a module from a lazy
          -- plugin asks lazy.nvim to load that plugin, which is the very thing that has to
          -- be avoided here, since this fires once during startup while the colorscheme is
          -- first applied and LazyVim's lualine config is not ready to run yet. If lualine
          -- is not up, there is nothing to retheme and the spec's opts has it covered.
          if not package.loaded["lualine"] then
            return
          end
          local live = require("lualine.config").get_config()
          live.options.theme = require("aura.lualine")(require("aura.palette").current())
          require("lualine").setup(live)
        end,
      })
    end,
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.theme = require("aura.lualine")(require("aura.palette").current())
      return opts
    end,
  },
}
