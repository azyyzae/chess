local state = {
    aiLoaded = false,
    aiRunning = false,
    gameConnected = false,
    thread = nil,
    moveCache = {}, -- Cache for calculated moves
    settings = {
        depth = 5, -- Search depth
        cacheSize = 1000, -- Maximum cached positions
        useCache = true
    }
}

return state