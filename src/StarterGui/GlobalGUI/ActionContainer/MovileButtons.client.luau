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
	-- Estos botones antiguos (M1Button / SprintButton) no tenían ninguna lógica conectada: se veían
	-- en móvil pero no hacían nada. Los controles táctiles reales los construye MobileControls
	-- (StarterPlayerScripts); se ocultan para no duplicar botones inertes.
	mobileControls.Visible = false
end