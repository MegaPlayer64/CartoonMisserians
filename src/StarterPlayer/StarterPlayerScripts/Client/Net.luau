--!strict
-- Capa de red del cliente. Los remotes los crea el servidor (Net.init del servidor).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared") -- esperar a que replique
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

local folder = ReplicatedStorage:WaitForChild("Remotes")
local cache: { [string]: RemoteEvent } = {}

local function get(name: Remotes.RemoteName): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	local remote = folder:WaitForChild(name)
	if not remote:IsA("RemoteEvent") then
		error(`'{name}' no es un RemoteEvent`)
	end
	cache[name] = remote
	return remote
end

function Net.fire(name: Remotes.RemoteName, ...: any)
	get(name):FireServer(...)
end

function Net.on(name: Remotes.RemoteName, handler: (any) -> ()): RBXScriptConnection
	return get(name).OnClientEvent:Connect(handler)
end

return Net
