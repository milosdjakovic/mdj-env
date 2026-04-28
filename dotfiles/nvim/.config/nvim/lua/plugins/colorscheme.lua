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
      -- Override aura's #6d6d6d gray with #949494 for better contrast.
      -- Upstream aura applies palette.gray to these groups via guifg, so
      -- we re-set them after the colorscheme finishes loading. Also apply
      -- immediately in case aura-dark is already active when this runs.
      local function apply_gray_override()
        local gray = "#949494"
        vim.api.nvim_set_hl(0, "Comment", { fg = gray, italic = true })
        vim.api.nvim_set_hl(0, "Folded", { fg = gray, italic = true })
        vim.api.nvim_set_hl(0, "FoldColumn", { fg = gray, bg = "#15141b" })
        vim.api.nvim_set_hl(0, "TabLine", { fg = gray, bg = "#15141b" })
        vim.api.nvim_set_hl(0, "Gray", { fg = gray })
      end
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "aura-dark",
        callback = apply_gray_override,
      })
      if vim.g.colors_name == "aura-dark" then
        apply_gray_override()
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
