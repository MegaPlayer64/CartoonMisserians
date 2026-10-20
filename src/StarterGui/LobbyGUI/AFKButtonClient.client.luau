--[[
	AFKButtonClient (LocalScript)
	Ubicacion: StarterGui.LobbyGUI.AFKButtonClient

	Maneja el toggle visual del boton AFK:
	  - LISTO  -> verde, texto 'ESTADO: LISTO'
	  - AFK    -> rojo, texto 'ESTADO: AFK (EN LOBBY)'
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local ToggleAFKRemote = Remotes:WaitForChild("ToggleAFK")

local lobbyGUI = script.Parent
local afkButton = lobbyGUI:WaitForChild("LeftListButtons"):WaitForChild("AFKButton")
local buttonText = afkButton:WaitForChild("ButtonText")
local stroke = afkButton:FindFirstChild("UIStroke")

local COLOR_READY = Color3.fromRGB(40, 180, 70)
local COLOR_READY_STROKE = Color3.fromRGB(20, 100, 40)
local COLOR_AFK = Color3.fromRGB(200, 60, 60)
local COLOR_AFK_STROKE = Color3.fromRGB(120, 20, 20)

local function updateButtonVisual(isAFK)
	if isAFK then
		afkButton.BackgroundColor3 = COLOR_AFK
		buttonText.Text = "ESTADO: AFK (EN LOBBY)"
		if stroke then stroke.Color = COLOR_AFK_STROKE end
	else
		afkButton.BackgroundColor3 = COLOR_READY
		buttonText.Text = "ESTADO: LISTO"
		if stroke then stroke.Color = COLOR_READY_STROKE end
	end
end

-- Actualizar cuando el atributo cambia
player:GetAttributeChangedSignal("IsAFK"):Connect(function()
	local isAFK = player:GetAttribute("IsAFK") or false
	updateButtonVisual(isAFK)
end)

-- Estado inicial
updateButtonVisual(player:GetAttribute("IsAFK") or false)

-- Click toggle
afkButton.Activated:Connect(function()
	ToggleAFKRemote:FireServer()
end)