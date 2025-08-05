local modules = {}

if _G.__CHESS_AI_LOADED__FULL then
    warn("Script already loaded.")
    return
end
_G.__CHESS_AI_LOADED__FULL = true

modules.config = loadstring(game:HttpGet("https://raw.githubusercontent.com/Azyyzae/chessBot/main/config.lua"))()
modules.state = loadstring(game:HttpGet("https://raw.githubusercontent.com/Azyyzae/chessBot/main/core/state.lua"))()
modules.ai = loadstring(game:HttpGet("https://raw.githubusercontent.com/Azyyzae/chessBot/main/core/ai.lua"))()
modules.gui = loadstring(game:HttpGet("https://raw.githubusercontent.com/Azyyzae/chessBot/main/core/gui.lua"))()

modules.gui.init(modules)
