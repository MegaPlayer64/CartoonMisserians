--!strict
-- Capa de red del servidor: crea todos los remotes desde la lista compartida y
-- aplica rate limit (token bucket por jugador y remote) antes de cada handler.
-- El token bucket vive en ServerModules.RateLimiter (compartido con los remotes
-- "legacy" de Framework.Remotes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.ServerModules.RateLimiter)

local Net = {}

local remotes: { [string]: RemoteEvent } = {}

-- Llamar UNA vez, antes de iniciar los sistemas.
function Net.init()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in Remotes do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	-- Se parenta al final: el cliente ve la carpeta ya completa.
	folder.Parent = ReplicatedStorage
end

function Net.fire(player: Player, name: Remotes.RemoteName, ...: any)
	remotes[name]:FireClient(player, ...)
end

-- El handler recibe argumentos hostiles: debe validar tipo → rango → permiso.
function Net.on(name: Remotes.RemoteName, ratePerSec: number, burst: number, handler: (player: Player, ...any) -> ())
	local remote = remotes[name]
	assert(remote, `Remote '{name}' no está en Remotes.luau o Net.init() no se ha ejecutado`)
	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not RateLimiter.allow(player, name, ratePerSec, burst) then
			return
		end
		handler(player, ...)
	end)
end

return Net
