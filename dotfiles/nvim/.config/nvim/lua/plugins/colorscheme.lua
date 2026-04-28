local aura_lualine = {
  normal = {
    a = { bg = "#a277ff", fg = "#15141b", gui = "bold" },
    b = { bg = "#29263c", fg = "#edecee" },
    c = { bg = "#1c1b22", fg = "#949494" },
  },
  insert = {
    a = { bg = "#61ffca", fg = "#15141b", gui = "bold" },
    b = { bg = "#29263c", fg = "#edecee" },
  },
  visual = {
    a = { bg = "#ffca85", fg = "#15141b", gui = "bold" },
    b = { bg = "#29263c", fg = "#edecee" },
  },
  replace = {
    a = { bg = "#ff6767", fg = "#15141b", gui = "bold" },
    b = { bg = "#29263c", fg = "#edecee" },
  },
  command = {
    a = { bg = "#a277ff", fg = "#15141b", gui = "bold" },
    b = { bg = "#29263c", fg = "#edecee" },
  },
  inactive = {
    a = { bg = "#1c1b22", fg = "#949494" },
    b = { bg = "#1c1b22", fg = "#949494" },
    c = { bg = "#1c1b22", fg = "#949494" },
  },
}

return {
  {
    "daltonmenezes/aura-theme",
    lazy = false,
    priority = 1000,
    init = function(plugin)
      vim.opt.rtp:append(plugin.dir .. "/packages/neovim")
    end,
    config = function()
      -- aura ships several highlight groups with gui = "inverse", which swaps
      -- fg and bg at render time. For Visual the result is a near white bar
      -- because Normal.fg (#edecee) becomes the rendered bg. Substitute uses
      -- bg = white directly. Both feel out of place against the otherwise
      -- muted aura look, so we replace them with solid backgrounds and
      -- readable foregrounds drawn from the aura palette.
      --
      -- We also override aura's #6d6d6d gray with #949494 for better contrast,
      -- and unify mini.icons colors so the file tree stops looking like a
      -- rainbow.
      local function apply_aura_overrides()
        local gray = "#949494"
        local black = "#15141b"
        local white = "#edecee"
        local selection = "#3d375e" -- aura purple_faded with alpha stripped
        local green = "#61ffca"
        local blue = "#82e2ff"
        local red = "#ff6767"
        local orange = "#ffca85"

        vim.api.nvim_set_hl(0, "Comment", { fg = gray, italic = true })
        vim.api.nvim_set_hl(0, "Folded", { fg = gray, italic = true })
        vim.api.nvim_set_hl(0, "FoldColumn", { fg = gray, bg = black })
        vim.api.nvim_set_hl(0, "TabLine", { fg = gray, bg = black })
        vim.api.nvim_set_hl(0, "Gray", { fg = gray })

        vim.api.nvim_set_hl(0, "Visual", { bg = selection, fg = white })
        vim.api.nvim_set_hl(0, "VisualNOS", { bg = selection, fg = white })
        vim.api.nvim_set_hl(0, "Search", { bg = selection, fg = orange })
        vim.api.nvim_set_hl(0, "IncSearch", { bg = orange, fg = black })
        vim.api.nvim_set_hl(0, "Substitute", { bg = selection, fg = red })
        vim.api.nvim_set_hl(0, "TabLineSel", { bg = selection, fg = green, bold = true })
        vim.api.nvim_set_hl(0, "DiffAdd", { bg = selection, fg = green })
        vim.api.nvim_set_hl(0, "DiffChange", { bg = selection, fg = blue })
        vim.api.nvim_set_hl(0, "DiffDelete", { bg = selection, fg = red })
        vim.api.nvim_set_hl(0, "DiffText", { bg = selection, fg = orange })

        for _, name in ipairs({
          "MiniIconsAzure",
          "MiniIconsBlue",
          "MiniIconsCyan",
          "MiniIconsGreen",
          "MiniIconsGrey",
          "MiniIconsOrange",
          "MiniIconsPurple",
          "MiniIconsRed",
          "MiniIconsYellow",
        }) do
          vim.api.nvim_set_hl(0, name, { fg = gray })
        end
      end
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "aura-dark",
        callback = apply_aura_overrides,
      })
      -- LazyVim sets the colorscheme during its priority 10000 setup, which
      -- runs before this plugin's config. By the time our autocmd is
      -- registered the ColorScheme event has already fired and we missed it,
      -- so re-apply on User VeryLazy. Mini.icons is also lazy = true, so
      -- VeryLazy is when its highlights are reliably available.
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = apply_aura_overrides,
      })
      if vim.g.colors_name == "aura-dark" then
        apply_aura_overrides()
      end
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aura-dark",
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        theme = aura_lualine,
      },
    },
  },
}
