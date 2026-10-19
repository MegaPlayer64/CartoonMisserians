--!strict
--[[
	RateLimiter (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.RateLimiter

	Token bucket por jugador y por clave (normalmente el nombre del remote).
	Uso, como PRIMERA línea de cada handler de remote:

		if not RateLimiter.allow(player, "UseAbility", 10, 15) then return end

	ratePerSec = tokens que se recuperan por segundo, burst = máximo acumulable.
	Superar el límite solo descarta la petición; no castigues ni banees por esto
	(el lag móvil y los reintentos generan falsos positivos).
]]

local Players = game:GetService("Players")

type Bucket = { tokens: number, last: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

local RateLimiter = {}

function RateLimiter.allow(player: Player, key: string, ratePerSec: number, burst: number): boolean
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

Players.PlayerRemoving:Connect(function(player: Player)
	buckets[player] = nil
end)

return RateLimiter
