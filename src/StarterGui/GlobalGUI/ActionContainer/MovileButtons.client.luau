local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gameGUI = playerGui:WaitForChild("GameGUI")

-- Detecta si el dispositivo tiene pantalla táctil (Móvil / Tablet)
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Referencia a tus botones
local mobileControls = script.Parent-- O los botones individuales M1Button / SprintButton

if mobileControls then
	mobileControls.Visible = isMobile
end