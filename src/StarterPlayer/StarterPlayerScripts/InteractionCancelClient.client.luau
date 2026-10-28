--[[
	InteractionCancelClient (LocalScript)
	Ubicación: StarterPlayer.StarterPlayerScripts.InteractionCancelClient

	El servidor (TaskManager.Interrupt) avisa con CancelInteraction cuando un efecto del Devilish
	-como el grito de Shed.mov- cancela lo que el jugador esté manteniendo pulsado. Una barra de
	ProximityPrompt solo se puede cerrar desde el cliente: se desactiva el servicio un instante
	(cancela el "mantener" en curso) y se reactiva. La autoridad real es el servidor, que además
	rechaza la tarea durante la interrupción.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local CancelInteractionRemote = Remotes:WaitForChild("CancelInteraction")

local CANCEL_SECONDS = 0.4
local token = 0

CancelInteractionRemote.OnClientEvent:Connect(function()
	token += 1
	local myToken = token

	ProximityPromptService.Enabled = false
	task.delay(CANCEL_SECONDS, function()
		-- Si llegó otra cancelación, esa se encarga de reactivarlo
		if myToken == token then
			ProximityPromptService.Enabled = true
		end
	end)
end)
