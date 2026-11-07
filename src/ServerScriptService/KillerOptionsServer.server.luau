--[[
	KillerOptionsServer (Script)
	Ubicación: ServerScriptService.KillerOptionsServer

	Recibe la opción "poder ser Killer" desde Opciones. El argumento del cliente es hostil: debe ser
	un booleano y el perfil tiene que estar cargado; PlayerData.setKillerOptIn lo valida y lo guarda.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerData = require(ServerScriptService.ServerModules.PlayerData)
local RateLimiter = require(ServerScriptService.ServerModules.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local SetKillerOptInRemote = Remotes:WaitForChild("SetKillerOptIn")

SetKillerOptInRemote.OnServerEvent:Connect(function(player, enabled)
	if not RateLimiter.allow(player, "SetKillerOptIn", 2, 3) then return end
	if typeof(enabled) ~= "boolean" then return end

	PlayerData.setKillerOptIn(player, enabled)
end)
