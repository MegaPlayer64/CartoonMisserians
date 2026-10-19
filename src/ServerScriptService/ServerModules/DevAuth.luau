--!strict
--[[
	DevAuth (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.DevAuth

	Única puerta de autorización para herramientas de desarrollo/QA
	(comandos de chat de TestModeManager y remotes Cheat_* de CheatCommands).

	- En Roblox Studio: todos los jugadores están autorizados.
	- En servidores reales: SOLO los UserIds de DEV_USER_IDS.

	Este módulo vive en ServerScriptService, así que el cliente no puede leerlo.
]]

local RunService = game:GetService("RunService")

-- Añade aquí tu UserId para poder usar los comandos en servidores reales.
local DEV_USER_IDS: { [number]: boolean } = {
	-- [12345678] = true,
}

local DevAuth = {}

function DevAuth.isAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return DEV_USER_IDS[player.UserId] == true
end

return DevAuth
