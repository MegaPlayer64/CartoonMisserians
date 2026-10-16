--[[
	AFKNotificationClient (LocalScript)
	Ubicacion: StarterGui.AFKNotification.AFKNotificationClient

	Muestra/oculta la notificacion visual cuando:
	  - El jugador esta en modo AFK
	  - La partida esta en curso (no Intermission)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage.Framework.Remotes
local MatchStateRemote = Remotes:WaitForChild("MatchState")

local gui = script.Parent
local container = gui:WaitForChild("Container")

local matchState = "Intermission"

local function updateVisibility()
	local isAFK = player:GetAttribute("IsAFK") or false
	if isAFK and matchState ~= "Intermission" then
		container.Visible = true
	else
		container.Visible = false
	end
end

-- Escuchar cambios de estado de partida
MatchStateRemote.OnClientEvent:Connect(function(state, data)
	matchState = state
	updateVisibility()
end)

-- Escuchar cambios de atributo IsAFK
player:GetAttributeChangedSignal("IsAFK"):Connect(updateVisibility)

-- Estado inicial
updateVisibility()