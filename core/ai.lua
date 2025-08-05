-- core/ai.lua

local M = {}

function M.start(modules)
    local config = modules.config
    local state = modules.state

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

        while retryCount < 10 and not func do
            for _, f in ipairs(getgc(true)) do
                if typeof(f) == "function" then
                    local info = debug.getinfo(f)
                    if info.name == funcName and string.sub(info.source, -#moduleName) == moduleName then
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
            warn("Failed to find " .. funcName .. " in " .. moduleName .. " after 10 retries.")
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
            return board and board.Parent and isLocalWhite == board.WhiteToPlay.Value
        end

        local function processTurn()
            if not isLocalPlayersTurn() or not state.aiRunning then
                return
            end

            local currentFen = board.FEN.Value
            if type(currentFen) ~= "string" or currentFen == "" then
                return
            end

            local move = GetBestMove(currentFen)

            if move then
                local waitTime = getSmartWait(clockText, moveCount)
                task.delay(waitTime, function()
                    if isLocalPlayersTurn() and state.aiRunning then
                        PlayMove(move)
                        moveCount = moveCount + 1
                    end
                end)
            end
        end

        local turnChangedConnection = board.WhiteToPlay.Changed:Connect(processTurn)
        table.insert(state.activeConnections, turnChangedConnection)

        local endGameConnection = ReplicatedStorage.Chess.EndGameEvent.OnClientEvent:Connect(function(endedBoard)
            if endedBoard == board then
                disconnectAllConnections()
                state.gameConnected = false
                print("[LOG]: Game ended.")
            end
        end)
        table.insert(state.activeConnections, endGameConnection)

        print("[LOG]: AI handler attached to board.")
        state.gameConnected = true
        task.wait(0.5)
        processTurn()
    end

    -- NEW: Function to find a game already in progress
    local function findAndStartActiveGame()
        local chessBoardsFolder = workspace:FindFirstChild("ChessBoards")
        if not chessBoardsFolder then return false end

        for _, board in ipairs(chessBoardsFolder:GetChildren()) do
            if board:IsA("Model") and board:FindFirstChild("WhitePlayer") and board:FindFirstChild("BlackPlayer") then
                if localPlayer.Name == board.WhitePlayer.Value or localPlayer.Name == board.BlackPlayer.Value then
                    print("[LOG]: Found active game in progress. Attaching handler...")
                    startGameHandler(board)
                    return true -- Signal that a game was found and handled
                end
            end
        end
        return false -- No active game found for the player
    end

    -- MODIFIED: Main startup logic
    -- First, try to find an active game.
    if not findAndStartActiveGame() then
        -- If no active game is found, then listen for a new one.
        print("[LOG]: No active game found. Listening for StartGameEvent...")
        local startGameConnection = ReplicatedStorage.Chess:WaitForChild("StartGameEvent").OnClientEvent:Connect(function(board)
            if board and (localPlayer.Name == board.WhitePlayer.Value or localPlayer.Name == board.BlackPlayer.Value) then
                if not state.gameConnected then
                    print("[LOG]: New game started.")
                    startGameHandler(board)
                end
            end
        end)
        table.insert(state.activeConnections, startGameConnection)
    end
end

return M
