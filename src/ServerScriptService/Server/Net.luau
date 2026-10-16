--!strict
-- Capa de red del servidor: crea todos los remotes desde la lista compartida y
-- aplica rate limit (token bucket por jugador y remote) antes de cada handler.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

type Bucket = { tokens: number, last: number }

local remotes: { [string]: RemoteEvent } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}

local function allow(player: Player, key: string, ratePerSec: number, burst: number): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { tokens = burst, last = now }
		playerBuckets[key] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * ratePerSec)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

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

	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
end

function Net.fire(player: Player, name: Remotes.RemoteName, ...: any)
	remotes[name]:FireClient(player, ...)
end

-- El handler recibe argumentos hostiles: debe validar tipo → rango → permiso.
function Net.on(name: Remotes.RemoteName, ratePerSec: number, burst: number, handler: (player: Player, ...any) -> ())
	local remote = remotes[name]
	assert(remote, `Remote '{name}' no está en Remotes.luau o Net.init() no se ha ejecutado`)
	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not allow(player, name, ratePerSec, burst) then
			return
		end
		handler(player, ...)
	end)
end

return Net
