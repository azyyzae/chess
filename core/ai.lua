local M = {}

function M.start(modules)
    local config = modules.config
    local state = modules.state

    -- Start new instance
    state.aiLoaded = true
    state.aiRunning = true
    state.gameConnected = false

    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Sunfish = localPlayer:WaitForChild("PlayerScripts").AI:WaitForChild("Sunfish")
    local ChessLocalUI = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("ChessLocalUI")

    local function getGameType(clockText)
        return config.CLOCK_NAME_MAPPING[clockText] or "unknown"
    end

    local function getSmartWait(clockText, moveCount)
        local configRange = config.CLOCK_WAIT_MAPPING[clockText]
        if not configRange then 
            configRange = config.CLOCK_WAIT_MAPPING["bullet"] -- temporary fix
        end
    
        local baseWait = math.random(math.random(0, configRange.min), math.random(configRange.min, configRange.max))
        local gameType = getGameType(clockText)
    
        if moveCount < math.random(7, 12) then
            return baseWait * 0.5 -- opening
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
                if typeof(f) == "function" and debug.getinfo(f).name == funcName then
                    if string.sub(debug.getinfo(f).source, -#moduleName) == moduleName then
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
            warn("Failed to find " .. funcName .. " after 10 retries.")
        end
        return func
    end

    local function initializeFunctions()
        local GetBestMove = getFunction("GetBestMove", "Sunfish")
        local PlayMove = getFunction("PlayMove", "ChessLocalUI")
    
        return GetBestMove, PlayMove
    end

    --[[ get ai bestmove function in Sunfish module script from garbage collector
    local GetBestMove = nil
    for _, f in ipairs(getgc(true)) do
        if typeof(f) == "function" and debug.getinfo(f).name == "GetBestMove" then
            if(string.sub(debug.getinfo(f).source, -7)=="Sunfish") then
                GetBestMove = f
            end
        end
    end

    -- get playmove function in ChessLocalUI from garbage collector
    local PlayMove = nil
    for _, f in ipairs(getgc(true)) do
        if typeof(f) == "function" and debug.getinfo(f).name == "PlayMove" then
            PlayMove = f
        end
    end]]

    -- Main part
    local function startGameHandler(board)
        local GetBestMove, PlayMove = initializeFunctions()
        local lastFen = nil
        local moveCount = 0
        local boardLoaded = false
        local Fen = nil
        local move = nil
        local gameEnded = false
        local nbMoves = 0
        local randWaitFromGameType = 0
        local clockText = nil

        local isLocalWhite = localPlayer.Name == board.WhitePlayer.Value
        local clockLabel = board:WaitForChild("Clock")
            :WaitForChild("MainBody")
            :WaitForChild("SurfaceGui")
            :WaitForChild(isLocalWhite and "WhiteTime" or "BlackTime")

        -- wait for clock to initialize
        task.wait(0.1)
        clockText = clockLabel.ContentText
        randWaitFromGameType = getSmartWait(clockText, nbMoves)
        boardLoaded = true

        -- speaks for itself
        local function isLocalPlayersTurn()
            local isLocalWhite = localPlayer.Name == board.WhitePlayer.Value
            return isLocalWhite == board.WhiteToPlay.Value
        end

        -- Calculate best move using Sunfish engine
        local function calculateMove(fen)
            if GetBestMove then
                return GetBestMove(fen)
            end
            warn("GetBestMove function not found")
            return nil
        end

    -- Check for playable moves until game ends
        local function gameLoop()
            task.wait(2) -- Reduced initial wait

            while not gameEnded do
                if boardLoaded and board then
                    local currentFen = board.FEN.Value
                    
                    if currentFen ~= lastFen and isLocalPlayersTurn() and state.aiRunning then
                        local move = calculateMove(currentFen)
                        if move then
                            local waitTime = getSmartWait(clockText, moveCount)
                            task.wait(waitTime)
                            PlayMove(move)
                            moveCount = moveCount + 1
                            lastFen = currentFen
                        end
                    end
                end
                task.wait(0.1) -- Reduced loop wait
            end
            
            -- Cleanup
            state.moveCache = {}
            state.gameConnected = false
        end

        state.aiThread = coroutine.create(gameLoop)
        coroutine.resume(state.aiThread)

        ReplicatedStorage.Chess:WaitForChild("EndGameEvent").OnClientEvent:Once(function(board)
                gameEnded = true
                state.gameConnected = false
                print("[LOG]: Game ended.")
        end)
    end

    -- Listener to get the board object
    if not state.gameConnected then
        ReplicatedStorage.Chess:WaitForChild("StartGameEvent").OnClientEvent:Connect(function(board)
            if board then
                if localPlayer.Name == board.WhitePlayer.Value or localPlayer.Name == board.BlackPlayer.Value then
                    print("[LOG]: New game started.")
                    startGameHandler(board)
                end
            else
                warn("Invalid board, try restarting a chess game.")
            end
        end)
        state.gameConnected = true
    else
        warn("Game instance already existing, restart chess club")
    end
end

return M
