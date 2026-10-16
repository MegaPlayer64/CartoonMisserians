--[[
	LobbyPadsHandler (Script)
	ServerScriptService.LobbyPadsHandler

	Gestiona la interaccion con los 4 pads de tienda en el Lobby.
	Al activar un ProximityPrompt, dispara OpenShopTab al cliente
	con la pestaña correspondiente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local OpenShopTabRemote = Remotes:FindFirstChild("OpenShopTab")
if not OpenShopTabRemote then
	OpenShopTabRemote = Instance.new("RemoteEvent")
	OpenShopTabRemote.Name = "OpenShopTab"
	OpenShopTabRemote.Parent = Remotes
end

-- == CONFIGURACION DE PADS ==
local PAD_CONFIGS = {
	["EmotesPad"] = "Emotes",
	["DancesPad"] = "Bailes",
	["CharactersPad"] = "Personajes",
	["SkinsPad"] = "Skins",
}

-- == BUSCAR Y CONECTAR PADS ==
local function setupPad(pad)
	local tabName = pad:GetAttribute("TabName") or PAD_CONFIGS[pad.Name]
	if not tabName then return end

	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad
	end

	-- Texto dinámico según el tipo de tienda
	local labelText = "Abrir Tienda de " .. tabName
	prompt.ActionText = labelText

	prompt.Triggered:Connect(function(player)
		OpenShopTabRemote:FireClient(player, tabName)
	end)
end

-- == INICIALIZACION ==
local function findAndSetupPads()
	local lobby = game.Workspace:FindFirstChild("Maps")
	if not lobby then return end
	lobby = lobby:FindFirstChild("Lobby")
	if not lobby then return end

	local shopPads = lobby:FindFirstChild("ShopPads")
	if not shopPads then return end

	for _, pad in ipairs(shopPads:GetChildren()) do
		if pad:IsA("BasePart") then
			setupPad(pad)
		end
	end
end

-- Configurar pads existentes
findAndSetupPads()

-- Monitorear pads que se agreguen en el futuro
game.Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BasePart") and descendant.Parent and descendant.Parent.Name == "ShopPads" then
		task.wait(0.1)
		setupPad(descendant)
	end
end)

print("[LobbyPadsHandler] Handler de pads de tienda activo.")