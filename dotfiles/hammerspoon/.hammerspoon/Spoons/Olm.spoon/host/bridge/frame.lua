-- The bridge's framing, step 2.2 of docs/PLAN-STANDALONE.md, docs/PROTOCOL-BRIDGE.md's Transport
-- and framing. One message is its length in bytes as decimal digits, a newline, then exactly that
-- many bytes of JSON, so a reader takes the short length line and then reads a known count, which
-- 2.1 measured in step with size where reading up to a newline was not. Pure, no hs.

local M = {}

-- The most a message may hold, `limits.message`.
M.MAX = 8 * 1024 * 1024

--- frame.encode(text) -> the message as it goes on the wire
function M.encode(text)
  return #text .. "\n" .. text
end

--- frame.length(line) -> the count the length line announces, or nil and why
--- The line arrives with its newline, as a read up to one hands it over. Anything but digits, or a
--- count past the limit, closes the connection.
function M.length(line)
  local digits = type(line) == "string" and line:match("^(%d+)\r?\n$")
  if not digits or #digits > 9 then return nil, "the length line is not a number" end
  local n = tonumber(digits)
  if n > M.MAX then return nil, "a message of " .. n .. " bytes is past the limit" end
  return n
end

--- frame.clean(text) -> valid UTF-8, and true when anything was replaced
--- Each invalid sequence becomes U+FFFD, since one bad byte in a row must not fail a whole answer,
--- the protocol's Bytes that are not UTF-8.
function M.clean(text)
  if type(text) ~= "string" then return text, false end
  if utf8.len(text) then return text, false end
  local out, i, n = {}, 1, #text
  while i <= n do
    local ok, bad = utf8.len(text, i)
    if ok then
      out[#out + 1] = text:sub(i)
      break
    end
    out[#out + 1] = text:sub(i, bad - 1)
    out[#out + 1] = "\u{FFFD}"
    i = bad + 1
  end
  return table.concat(out), true
end

return M
