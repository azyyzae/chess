local M = {}

local state
local config
local connections = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")

local Sunfish = require(playerScripts.AI:WaitForChild("Sunfish"))
local ChessLocalUI = require(playerScripts:WaitForChild("ChessLocalUI"))

local GetBestMove = Sunfish.GetBestMove
local PlayMove = ChessLocalUI.PlayMove

local function getGameType(clockText)
    return config.CLOCK_NAME_MAPPING[clockText] or "unknown"
end

local function getSmartWait(clockText, moveCount)
    local configRange = config.CLOCK_WAIT_MAPPING[clockText] or config.CLOCK_WAIT_MAPPING["bullet"]
    local baseWait = math.random() * (configRange.max - configRange.min) + configRange.min
    local gameType = getGameType(clockText)

    if moveCount < 10 then
        return baseWait * 0.5
    elseif moveCount < 35 and gameType ~= "bullet" then
        return baseWait * 3.0
    else
        return baseWait * 1.2
    end
end

local function makeMove(board, clockText, moveCount)
    if not state.aiRunning then return end

    local fen = board.FEN.Value
    if not fen then return end

    local move = GetBestMove(nil, fen, 5000)
    if move then
        local waitTime = getSmartWait(clockText, moveCount.Value)
        task.wait(waitTime)
        if state.aiRunning then 
            PlayMove(move)
            moveCount.Value += 1
        end
    end
end

local function cleanupConnections()
    for _, connection in ipairs(connections) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(connections)
end

local function startGameHandler(board)
    cleanupConnections()
    state.gameConnected = true

    local moveCount = Instance.new("IntValue")
    moveCount.Value = 0

    local isLocalWhite = localPlayer.Name == board.WhitePlayer.Value
    local clockLabel = board:WaitForChild("Clock"):WaitForChild("MainBody"):WaitForChild("SurfaceGui"):WaitForChild(isLocalWhite and "WhiteTime" or "BlackTime")
    
    local clockText = clockLabel.ContentText

    local function isOurTurn()
        return isLocalWhite == board.WhiteToPlay.Value
    end

    local turnChangedConn = board.WhiteToPlay.Changed:Connect(function()
        if isOurTurn() and state.aiRunning then
            state.aiThread = task.spawn(makeMove, board, clockText, moveCount)
        end
    end)
    table.insert(connections, turnChangedConn)

    local endGameConn = ReplicatedStorage.Chess.EndGameEvent.OnClientEvent:Connect(function()
        cleanupConnections()
        if state.aiThread then
            task.cancel(state.aiThread)
            state.aiThread = nil
        end
        state.gameConnected = false
        print("[LOG]: Game ended.")
    end)
    table.insert(connections, endGameConn)

    if isOurTurn() then
        state.aiThread = task.spawn(makeMove, board, clockText, moveCount)
    end
end

function M.start(modules)
    config = modules.config
    state = modules.state

    state.aiLoaded = true
    state.aiRunning = true

    if not state.gameConnected then
        local startGameConn = ReplicatedStorage.Chess.StartGameEvent.OnClientEvent:Connect(function(board)
            if board and (localPlayer.Name == board.WhitePlayer.Value or localPlayer.Name == board.BlackPlayer.Value) then
                print("[LOG]: New game started.")
                startGameHandler(board)
            else
                warn("Invalid board or not a player.")
            end
        end)
        table.insert(connections, startGameConn)
    end
end

function M.stop()
    cleanupConnections()
    state.gameConnected = false
    print("[LOG]: AI listeners stopped.")
end

return M
