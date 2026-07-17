--- The web provider, a thin adapter turning the Chooser contract into a Surface
--- searchable list, so the webview backend is swappable with the native one. It
--- is a builder that closes over the injected Surface spoon, keeping the facade
--- ignorant of how a list is constructed. A Surface list already exposes the full
--- Chooser contract, so this adds nothing but the wiring.
return function(surface)
  return {
    new = function(config)
      return surface:newList(config)
    end,
  }
end
