-- Neovim follows the terminal's appearance after startup, which by itself it does not do.
--
-- 'background' is documented as something the TUI "sets on startup if it can detect the
-- background color", and nothing ever re-runs that detection. So Ghostty switches, herdr
-- switches, the status line switches, and Neovim alone stays on whichever half it was born
-- into. This is the piece that closes that gap.
--
-- The question is asked of the terminal rather than of macOS. OSC 11 is the same query
-- Neovim itself uses at startup, it survives the trip through herdr, and it keeps the rule
-- the whole stack rests on, that Ghostty owns the palette and every layer above inherits it.
-- Reading AppleInterfaceStyle from here would work today and would be wrong the moment a
-- terminal theme is set by hand. The Claude status line reads that setting only because it
-- is not inside a terminal it can ask.
--
-- nvim_ui_send writes the sequence and TermResponse carries the answer back. That pairing is
-- Neovim's own, spelled out in the TermResponse docs and used by the built in OSC 52
-- clipboard provider, so it is a supported path rather than a trick.
--
-- Polling, because there is no subscription to take. Terminals announce a scheme change
-- through DEC mode 2031, and that announcement arrives as a CSI sequence while TermResponse
-- carries only DA1, OSC, DCS and APC, so there is nothing in Neovim to receive it. A query a
-- second is seven bytes out and about twenty five back, which is nothing even through a
-- multiplexer.

local M = {}

local QUERY = "\027]11;?\027\\"
local INTERVAL = 1000

-- An OSC 11 answer is rgb: with one to four hex digits per component, so each is scaled by
-- its own width rather than assumed to be eight bit. Ghostty answers in four.
local function luminance(answer)
  local r, g, b = answer:match("rgb:(%x+)/(%x+)/(%x+)")
  if not r then
    return nil
  end
  local function channel(hex)
    return tonumber(hex, 16) / (16 ^ #hex - 1)
  end
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

local timer

function M.start()
  if timer then
    return
  end

  vim.api.nvim_create_autocmd("TermResponse", {
    group = vim.api.nvim_create_augroup("aura_appearance", { clear = true }),
    callback = function(ev)
      local sequence = ev.data and ev.data.sequence
      if type(sequence) ~= "string" or not sequence:find("\027]11;", 1, true) then
        return
      end
      local value = luminance(sequence)
      if not value then
        return
      end
      local wanted = value > 0.5 and "light" or "dark"
      -- Scheduled rather than immediate. Setting 'background' reloads the colorscheme, and
      -- TermResponse is documented as able to fire in the middle of file I/O or a shell
      -- command, which is not a place to repaint 357 highlight groups from.
      if vim.o.background ~= wanted then
        vim.schedule(function()
          if vim.o.background ~= wanted then
            vim.o.background = wanted
          end
        end)
      end
    end,
  })

  timer = vim.uv.new_timer()
  timer:start(
    INTERVAL,
    INTERVAL,
    vim.schedule_wrap(function()
      -- Headless has no host to ask, and a UI can still attach later, so this is checked per
      -- tick rather than used to decide whether to start at all.
      if #vim.api.nvim_list_uis() > 0 then
        vim.api.nvim_ui_send(QUERY)
      end
    end)
  )
end

return M
