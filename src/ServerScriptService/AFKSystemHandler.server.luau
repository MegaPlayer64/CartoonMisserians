--[[
	AFKSystemHandler (Script)
	Ubicacion: ServerScriptService.AFKSystemHandler

	Gestiona el atributo IsAFK en cada Player:
	  - Default: false (Listo para jugar)
	  - Toggle via RemoteEvent ToggleAFK
	  - Notifica al cliente el estado actual
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require(game:GetService("ServerScriptService").ServerModules.RateLimiter)
local Remotes = ReplicatedStorage.Framework.Remotes
local ToggleAFKRemote = Remotes:WaitForChild("ToggleAFK")

local function setAFKState(player, isAFK)
	player:SetAttribute("IsAFK", isAFK)
	print("[AFKSystem] " .. player.Name .. " -> " .. (isAFK and "AFK (en lobby)" or "LISTO"))
end

-- Inicializar atributo en nuevos jugadores
Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("IsAFK", false)
end)

-- Inicializar jugadores ya presentes
for _, player in ipairs(Players:GetPlayers()) do
	player:SetAttribute("IsAFK", false)
end

-- Manejar toggle del cliente
ToggleAFKRemote.OnServerEvent:Connect(function(player)
	if not RateLimiter.allow(player, "ToggleAFK", 2, 3) then return end
	local current = player:GetAttribute("IsAFK") or false
	setAFKState(player, not current)
end)

print("[AFKSystem] Sistema AFK inicializado correctamente.")