--- Retention policies, the eviction side of the store engine.
---
--- Each builder returns a policy, a table with one method reap(ctx), where ctx carries
--- the live history list and the optional media layer. A store runs its whole policy
--- list after every add, so the policies combine as an or, an entry leaves when any one
--- of them evicts it. The policies are not uniform on purpose. Count and age drop whole
--- oldest entries, while bytes does not delete at all, it asks the media layer to demote
--- the oldest frozen bytes. That is why a text only store safely takes count with no
--- media, and only a store with a media layer takes bytes.
---
--- Adding a policy is a new builder here plus one line in the composition root.

local R = {}

-- Release an entry's media, when the store has a media layer, as it leaves.
local function drop(ctx, e)
  if ctx.media then ctx.media.release(e) end
end

--- R.count(max) - keep at most max entries, dropping the oldest whole entries. History
--- is newest first, so the tail is the oldest.
function R.count(max)
  return { reap = function(ctx)
    while #ctx.history > max do
      drop(ctx, table.remove(ctx.history))
    end
  end }
end

--- R.age(seconds) - drop entries older than seconds. Available but unused by the
--- clipboard, which keeps entries as long as they exist regardless of age.
function R.age(seconds)
  return { reap = function(ctx)
    local cutoff = os.time() - seconds
    for i = #ctx.history, 1, -1 do
      if (ctx.history[i].ts or 0) < cutoff then
        drop(ctx, table.remove(ctx.history, i))
      end
    end
  end }
end

--- R.bytes(cap) - keep total frozen media bytes under cap. This one demotes rather than
--- deletes, so the real work lives in the media layer, a file losing its frozen copy but
--- keeping its link and an image being removed whole. A store with no media layer has no
--- frozen bytes, so the policy is a no-op there.
function R.bytes(cap)
  return { reap = function(ctx)
    if ctx.media then ctx.media.enforceBudget(ctx.history, cap) end
  end }
end

return R
