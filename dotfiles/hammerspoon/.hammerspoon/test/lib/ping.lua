-- A minimal readiness probe. The runner dofiles this before it dofiles any case, so the
-- first Lua that ever crosses into the hs command line tool is a dofile call carrying a
-- path, never inline source, exactly the same shape every case after it takes. A plain
-- literal handed straight to hs would be safe on its own, but the rule this repository
-- follows is that no Lua source ever crosses that boundary except through dofile, so this
-- file exists purely to keep the readiness check inside that same rule.
print("pong")
