local M = {}

function M.start(modules)
    local config = modules.config
    local state = modules.state

    state.aiLoaded = true
    state.aiRunning = true
    state.gameConnected = false
    state.activeConnections = {}

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local localPlayer = Players.LocalPlayer

    local function getGameType(clockText)
        return config.CLOCK_NAME_MAPPING[clockText] or "unknown"
    end

    local function getSmartWait(clockText, moveCount)
        local configRange = config.CLOCK_WAIT_MAPPING[clockText]
        if not configRange then
            configRange = config.CLOCK_WAIT_MAPPING["bullet"]
        end

        local baseWait = math.random() * (configRange.max - configRange.min) + configRange.min
        local gameType = getGameType(clockText)

        if moveCount < math.random(7, 12) then
            return baseWait * 0.5
        elseif moveCount < math.random(12, 40) then
            return (gameType ~= "bullet") and baseWait * 4.0 or baseWait * 2.0
        else
            return baseWait * 1.2
        end
    end

    local function getFunction(funcName, moduleName)
        local retryCount = 0
        local func = nil

        -- Define the expected source pattern more robustly
        local expectedSourcePattern = ".." .. moduleName -- Matches the end of the source string

        while retryCount < 10 and not func do
            for _, f in ipairs(getgc(true)) do
                if typeof(f) == "function" then
                    local info = debug.getinfo(f)
                    -- Check function name and ensure it comes from the correct script module
                    if info and info.name == funcName and info.source and string.find(info.source, expectedSourcePattern, -#expectedSourcePattern, true) then
                        func = f
                        break
                    end
                end
            end
            if not func then
                retryCount = retryCount + 1
                task.wait(0.1)
            end
        end

        if not func then
            warn("Failed to find " .. funcName .. " in " .. moduleName .. " after 10 retries. Source pattern: " .. expectedSourcePattern)
        end
        return func
    end

    local function initializeFunctions()
        local GetBestMove = getFunction("GetBestMove", "Sunfish")
        local PlayMove = getFunction("PlayMove", "ChessLocalUI")
        return GetBestMove, PlayMove
    end

    local function disconnectAllConnections()
        for _, connection in ipairs(state.activeConnections) do
            if connection then
                connection:Disconnect()
            end
        end
        table.clear(state.activeConnections)
    end

    local function startGameHandler(board)
        disconnectAllConnections()

        local GetBestMove, PlayMove = initializeFunctions()
        if not GetBestMove or not PlayMove then
            warn("Failed to initialize core AI functions. Aborting game handler.")
            return
        end

        local moveCount = 0
        local isLocalWhite = localPlayer.Name == board.WhitePlayer.Value

        local clockLabel = board:WaitForChild("Clock"):WaitForChild("MainBody"):WaitForChild("SurfaceGui"):WaitForChild(isLocalWhite and "WhiteTime" or "BlackTime")
        local clockText = clockLabel.ContentText

        local function isLocalPlayersTurn()
            -- Ensure board and its parent exist before accessing properties
            return board and board.Parent and isLocalWhite == board.WhiteToPlay.Value
        end

        local function processTurn()
            if not isLocalPlayersTurn() or not state.aiRunning then
                return
            end

            local currentFen = board.FEN.Value
            
            -- Strict check for string type and non-emptiness
            if type(currentFen) ~= "string" or currentFen == "" then
                -- If FEN is not ready or invalid, wait for the next turn.
                -- You might want to log this if it happens frequently.
                -- warn("FEN not ready or invalid. Waiting for next turn. FEN: ", currentFen)
                return
            end

            local move = GetBestMove(currentFen)

            if move then
                local waitTime = getSmartWait(clockText, moveCount)
                task.delay(waitTime, function()
                    -- Re-check conditions before playing the move, as state might have changed
                    if isLocalPlayersTurn() and state.aiRunning then
                        PlayMove(move)
                        moveCount = moveCount + 1
                    end
                end)
            end
        end

        -- Connect to the FEN value change to trigger processing, as the turn might not always change
        -- if the AI is making a move. This ensures we react to a new FEN state.
        local fenChangedConnection = board.FEN.Changed:Connect(function()
            if isLocalPlayersTurn() then -- Only process if it's our turn
                processTurn()
            end
        end)
        table.insert(state.activeConnections, fenChangedConnection)

        -- Also keep the turn change connection to handle initial turns and other events
        local turnChangedConnection = board.WhiteToPlay.Changed:Connect(processTurn)
        table.insert(state.activeConnections, turnChangedConnection)

        local endGameConnection = ReplicatedStorage.Chess.EndGameEvent.OnClientEvent:Connect(function(endedBoard)
            if endedBoard == board then
                disconnectAllConnections()
                state.gameConnected = false
            end
        end)
        table.insert(state.activeConnections, endGameConnection)

        -- Process the initial state when the game starts
        task.wait(0.5) -- Give the game a moment to fully initialize the board and FEN
        processTurn()
    end

    if not state.gameConnected then
        state.gameConnected = true
        local startGameConnection = ReplicatedStorage.Chess:WaitForChild("StartGameEvent").OnClientEvent:Connect(function(board)
            if board and (localPlayer.Name == board.WhitePlayer.Value or localPlayer.Name == board.BlackPlayer.Value) then
                print("[LOG] New game started. Handling game.")
                startGameHandler(board)
            else
                warn("Board invalid or player not in game. AI will not start.")
            end
        end)
        table.insert(state.activeConnections, startGameConnection)
    else
        warn("Game instance connection is already active. Attempting to reconnect if necessary.")
        -- If gameConnected is true but no active connections, might indicate a state issue.
        -- For now, we'll just warn and assume the previous connection handler is still managing things.
    end
end

return M
