--[[
	MapSelection (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.MapSelection

	Gestiona el voto de mapa EXCLUSIVO del Devilish.
	Tras la seleccion de personajes, el Devilish recibe 3 mapas aleatorios
	filtrados por categoria (Pequeño, Mediano, Grande) y elige en un maximo
	de 15 segundos. La eleccion se notifica a todos via RemoteEvent 'MapChosen'.

	Dependencias:
	  - ReplicatedStorage.Framework.MatchConfig
	  - ReplicatedStorage.Framework.Remotes.MapVoteRequest (RemoteEvent)
	  - ReplicatedStorage.Framework.Remotes.MapVoteResponse (RemoteEvent)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Framework.MatchConfig)
local RateLimiter = require(game:GetService("ServerScriptService").ServerModules.RateLimiter)

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MapVoteRequestRemote = Remotes:WaitForChild("MapVoteRequest")
local MapVoteResponseRemote = Remotes:WaitForChild("MapVoteResponse")

local MapSelection = {}

-- Lo que ve el Devilish de cada mapa (copia: no se expone la tabla de configuración tal cual)
local function toOption(map)
	return {
		Name = map.Name,
		DisplayName = map.DisplayName,
		Category = map.Category,
		RecommendedKillers = map.RecommendedKillers or {},
		ExitCount = MatchConfig.ExitsByCategory[map.Category] or 1,
	}
end

--[[
	Genera una lista de opciones de mapa (por defecto 3), tomando un mapa
	aleatorio de cada categoria (Pequeño, Mediano, Grande). Si alguna categoria
	no tiene mapas, se rellena con mapas aleatorios restantes.
]]
function MapSelection.GetVoteOptions(count)
	count = count or 3
	local options = {}
	local used = {}

	-- Un mapa por categoria
	for _, category in ipairs({ MatchConfig.MapCategories.Pequeno, MatchConfig.MapCategories.Mediano, MatchConfig.MapCategories.Grande }) do
		local categoryMaps = {}
		for _, map in ipairs(MatchConfig.AvailableMaps) do
			if map.Category == category then
				table.insert(categoryMaps, map)
			end
		end
		if #categoryMaps > 0 then
			local chosen = categoryMaps[math.random(1, #categoryMaps)]
			if not used[chosen.Name] then
				table.insert(options, toOption(chosen))
				used[chosen.Name] = true
			end
		end
	end

	-- Rellenar con mapas restantes si faltan opciones
	local remaining = {}
	for _, map in ipairs(MatchConfig.AvailableMaps) do
		if not used[map.Name] then
			table.insert(remaining, map)
		end
	end
	while #options < count and #remaining > 0 do
		local idx = math.random(1, #remaining)
		table.insert(options, toOption(remaining[idx]))
		table.remove(remaining, idx)
	end

	return options
end

--[[
	Selecciona un mapa aleatorio de la lista disponible.
]]
function MapSelection.PickRandomMap()
	local maps = MatchConfig.AvailableMaps
	if #maps == 0 then return nil end
	return maps[math.random(1, #maps)].Name
end

--[[
	Ejecuta el voto del Devilish.
	Envia las opciones al cliente del Devilish y espera su respuesta hasta
	'duracion' segundos. Retorna el nombre del mapa elegido o nil si no voto.
]]
function MapSelection.RunVote(devilishPlayer, options, duration)
	local chosen = nil
	local done = false
	local connection = nil

	connection = MapVoteResponseRemote.OnServerEvent:Connect(function(player, mapName)
		if player ~= devilishPlayer or done then return end
		if not RateLimiter.allow(player, "MapVote", 3, 5) then return end
		if typeof(mapName) ~= "string" then return end

		-- Validar que el mapa elegido este entre las opciones ofrecidas
		for _, opt in ipairs(options) do
			if opt.Name == mapName then
				chosen = mapName
				done = true
				break
			end
		end
	end)

	MapVoteRequestRemote:FireClient(devilishPlayer, {
		options = options,
		duration = duration,
	})

	local elapsed = 0
	while elapsed < duration and not done do
		task.wait(1)
		elapsed = elapsed + 1
	end

	connection:Disconnect()
	return chosen
end

return MapSelection