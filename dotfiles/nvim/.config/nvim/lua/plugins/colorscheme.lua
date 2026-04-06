local aura_lualine = {
  normal = {
    a = { bg = "#a277ff", fg = "#15141b", gui = "bold" },
    b = { bg = "#29263c", fg = "#edecee" },
    c = { bg = "#1c1b22", fg = "#6d6d6d" },
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
    a = { bg = "#1c1b22", fg = "#6d6d6d" },
    b = { bg = "#1c1b22", fg = "#6d6d6d" },
    c = { bg = "#1c1b22", fg = "#6d6d6d" },
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
