--[[
	BotController (ModuleScript)
	Ubicación: ServerScriptService.BotController

	Sistema de Bots para Devilish y Toonflows.
	- Clona personajes reales desde ReplicatedStorage.Characters o utiliza DummyModel.
	- IA adaptativa:
		* Devilish: Persigue Toonflows (jugadores/bots) y ejecuta ataques melee.
		* Toonflow: Detecta al Devilish y huye en dirección opuesta.
	- Métodos de integración para MatchManager (Teletransporte y Registro).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)

local BotController = {}
local activeBots = {}

-- == CONFIGURACIÓN DE IA ==
local ATTACK_RANGE = 5         -- studs para ataque melee
local ATTACK_COOLDOWN = 1.2    -- segundos entre ataques
local ATTACK_DAMAGE = 25       -- daño por ataque del Devilish
local DETECTION_RANGE = 70    -- studs para detectar objetivos
local PATROL_RANGE = 30        -- studs de rango de patrulla
local UPDATE_INTERVAL = 0.25   -- segundos entre ticks de IA

--[[
	Busca la plantilla del personaje en ReplicatedStorage.Characters.
]]
local function getCharacterTemplate(characterName)
	local charsFolder = ReplicatedStorage:FindFirstChild("Characters")
	if charsFolder then
		local charModel = charsFolder:FindFirstChild(characterName)
		if charModel then return charModel end
		return charsFolder:FindFirstChild("DummyModel")
	end
	return nil
end

--[[
	Encuentra el enemigo más cercano (jugador o bot) según el rol opuesto.
]]
local function findNearestOpponent(botModel, botRole)
	local botHRP = botModel:FindFirstChild("HumanoidRootPart")
	if not botHRP then return nil, math.huge end

	local nearestTarget = nil
	local nearestDist = math.huge
	local botPos = botHRP.Position

	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model ~= botModel then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")

			if hum and hum.Health > 0 and hrp then
				local targetRole = model:GetAttribute("Role")

				-- Si no tiene atributo, buscar en StatsModule
				if not targetRole then
					local stats = StatsModule.GetStats(model)
					if stats and stats:FindFirstChild("Role") then
						targetRole = stats.Role.Value
					end
				end

				-- Determinar si es un objetivo válido segun el rol opuesto
				local isValidOpponent = false
				if botRole == "Devilish" or botRole == StatsModule.Role.Devilish then
					if targetRole == "Toonflow" or targetRole == StatsModule.Role.Toonflow or not targetRole then
						isValidOpponent = true
					end
				elseif botRole == "Toonflow" or botRole == StatsModule.Role.Toonflow then
					if targetRole == "Devilish" or targetRole == StatsModule.Role.Devilish or model:GetAttribute("IsDevilish") then
						isValidOpponent = true
					end
				end

				if isValidOpponent then
					local dist = (hrp.Position - botPos).Magnitude
					if dist < nearestDist and dist <= DETECTION_RANGE then
						nearestDist = dist
						nearestTarget = model
					end
				end
			end
		end
	end

	return nearestTarget, nearestDist
end

--[[
	Genera un Bot con el rol especificado.
]]
function BotController.SpawnBot(role, spawnCFrame, characterName)
	local isDevilish = (role == "Devilish" or role == StatsModule.Role.Devilish)
	local roleString = isDevilish and "Devilish" or "Toonflow"

	characterName = characterName or (isDevilish and "Mariposaurio" or "Brothercat")

	-- Intentar clonar modelo real o dummy
	local template = getCharacterTemplate(characterName)
	local botModel

	if template then
		botModel = template:Clone()
		botModel.Name = "BOT_" .. characterName
	else
		botModel = Instance.new("Model")
		botModel.Name = "BOT_" .. characterName

		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Size = Vector3.new(2, 2, 1)
		hrp.Transparency = 1
		hrp.CanCollide = true
		hrp.Parent = botModel
		botModel.PrimaryPart = hrp

		local humanoid = Instance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.MaxHealth = 100
		humanoid.Health = 100
		humanoid.Parent = botModel
	end

	-- Desanclar partes para física y movimiento
	for _, part in ipairs(botModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	-- Posicionar
	local hrp = botModel:FindFirstChild("HumanoidRootPart") or botModel.PrimaryPart
	if hrp then
		botModel.PrimaryPart = hrp
		botModel:PivotTo(spawnCFrame)
	end

	botModel.Parent = workspace

	-- Highlight visual
	local highlight = botModel:FindFirstChild("BotHighlight") or Instance.new("Highlight")
	highlight.Name = "BotHighlight"
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.FillColor = isDevilish and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(50, 200, 255)
	highlight.Parent = botModel

	-- Atributos y Stats
	botModel:SetAttribute("CharacterName", characterName)
	botModel:SetAttribute("Role", roleString)
	botModel:SetAttribute("IsBot", true)
	if isDevilish then botModel:SetAttribute("IsDevilish", true) end

	local config = {
		MaxHealth = isDevilish and 200 or 100,
		WalkSpeed = isDevilish and 18 or 16,
		RunSpeed = isDevilish and 23 or 22,
	}

	StatsModule.InitializeStats(botModel, roleString, config)

	-- == BUCLE DE IA ADAPTATIVA ==
	local aiThread = task.spawn(function()
		local humanoid = botModel:FindFirstChildOfClass("Humanoid")
		local botHRP = botModel:FindFirstChild("HumanoidRootPart")
		if not (humanoid and botHRP) then return end

		local origin = spawnCFrame.Position
		local patrolDirection = 1
		local lastAttackTime = 0
		local patrolTarget = origin + (spawnCFrame.LookVector * PATROL_RANGE)

		while botModel and botModel.Parent do
			if not humanoid or humanoid.Health <= 0 then break end

			local opponent, dist = findNearestOpponent(botModel, roleString)

			if opponent then
				local targetHRP = opponent:FindFirstChild("HumanoidRootPart")

				if isDevilish then
					-- LÓGICA DEVILISH: Perseguir y atacar
					if targetHRP then
						if dist <= ATTACK_RANGE then
							humanoid:MoveTo(botHRP.Position)
							local now = tick()

							if now - lastAttackTime >= ATTACK_COOLDOWN then
								lastAttackTime = now
								StatsModule.ApplyDamage(opponent, ATTACK_DAMAGE)
								print(string.format("[BotController] %s atacó a %s (%d daño)", botModel.Name, opponent.Name, ATTACK_DAMAGE))
							end
						else
							humanoid:MoveTo(targetHRP.Position)
						end
					end
				else
					-- LÓGICA TOONFLOW: Huir del Devilish
					if targetHRP then
						local fleeDirection = (botHRP.Position - targetHRP.Position).Unit
						local fleePosition = botHRP.Position + fleeDirection * 25
						humanoid.WalkSpeed = config.RunSpeed
						humanoid:MoveTo(fleePosition)
					end
				end
			else
				-- MODO PATRULLA
				humanoid.WalkSpeed = config.WalkSpeed
				local currentPos = botHRP.Position
				if (currentPos - patrolTarget).Magnitude < 4 then
					patrolDirection = patrolDirection * -1
					patrolTarget = origin + (spawnCFrame.LookVector * (PATROL_RANGE * patrolDirection))
				end
				humanoid:MoveTo(patrolTarget)
			end

			task.wait(UPDATE_INTERVAL)
		end

		print("[BotController] IA finalizada para " .. botModel.Name)
	end)

	local botData = {
		Model = botModel,
		Role = roleString,
		Thread = aiThread
	}
	table.insert(activeBots, botData)

	print("[BotController] Bot generado: " .. botModel.Name .. " | Rol: " .. roleString)
	return botModel
end

--[[
	Teletransporta todos los bots vivos a sus spawns correspondientes del mapa.
	Acepta tanto tablas de partes como carpetas/modelos (Instances) directamente.
]]
function BotController.TeleportBotsToSpawns(toonSpawns, devilishSpawns)
	-- Convertir a tabla si se pasó una Folder/Model (Instance)
	local toonList = (typeof(toonSpawns) == "Instance") and toonSpawns:GetChildren() or (toonSpawns or {})
	local devilishList = (typeof(devilishSpawns) == "Instance") and devilishSpawns:GetChildren() or (devilishSpawns or {})

	for _, botData in ipairs(activeBots) do
		local model = botData.Model
		if model and model.Parent then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local spawnList = (botData.Role == "Devilish") and devilishList or toonList

				if #spawnList > 0 then
					local selectedSpawn = spawnList[math.random(1, #spawnList)]
					if selectedSpawn:IsA("BasePart") then
						model:PivotTo(selectedSpawn.CFrame * CFrame.new(0, 3, 0))
					else
						model:PivotTo(selectedSpawn:GetPivot() * CFrame.new(0, 3, 0))
					end
					print("[BotController] Teletransportado " .. model.Name .. " a " .. selectedSpawn.Name)
				else
					warn("[BotController] No se encontraron spawns para el rol: " .. tostring(botData.Role))
				end
			end
		end
	end
end

--[[
	Devuelve la lista de bots vivos en la partida.
]]
function BotController.GetAliveBots()
	local alive = {}
	for _, botData in ipairs(activeBots) do
		local model = botData.Model
		if model and model.Parent then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(alive, model)
			end
		end
	end
	return alive
end

--[[
	Elimina todos los bots activos del servidor.
]]
function BotController.ClearAllBots()
	for _, botData in ipairs(activeBots) do
		if botData.Thread then task.cancel(botData.Thread) end
		if botData.Model and botData.Model.Parent then
			botData.Model:Destroy()
		end
	end
	activeBots = {}
	print("[BotController] Todos los bots han sido eliminados.")
end

return BotController