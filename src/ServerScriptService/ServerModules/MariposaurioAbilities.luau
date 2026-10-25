--[[
	MariposaurioAbilities (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.MariposaurioAbilities

	Registro oficial de habilidades para Mariposaurio en AbilityFramework.

	CONTRATO con AbilityFramework.Execute: `return false, motivo` = la habilidad NO se ejecutó y se
	reembolsan cooldown y recursos. Todas las de esta lista necesitan un objetivo válido, así que si
	no lo hay (fuera de rango, muerto, ya escapó...) no se consume nada.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)
local BotController = require(game:GetService("ServerScriptService"):WaitForChild("BotController"))

local Remotes = ReplicatedStorage.Framework.Remotes
local BlindEffectRemote = Remotes:FindFirstChild("BlindEffect")
local PopUpRemote = Remotes:FindFirstChild("TriggerPopups") -- Para los mensajes crueles en pantalla
local MariposaurioAbilities = {}

local TRACK_RANGE = 60
local TRACK_SECONDS = 5
local GRAB_RANGE = 8
local GRAB_DAMAGE = 20
local GRAB_HOLD_SECONDS = 2.5
local BOO_BEHIND_DISTANCE = 4

-- DeadHope: la descripción habla de "revivir a un Toonflow eliminado", pero la implementación
-- original invocaba una marioneta en cualquier momento. Se conserva ese comportamiento; ponlo en true
-- para exigir un Toonflow muerto (su personaje solo existe unos segundos tras morir, hasta el respawn).
local REQUIRE_DEAD_TOONFLOW = false
local PUPPET_LIFETIME = 30
local MAX_PUPPETS = 2

-- Último Toonflow rastreado por cada Devilish (se usa en Boo!!). Claves débiles: no retiene personajes.
local lastTracked = setmetatable({}, { __mode = "k" })

-- Toonflow vivo, con Stats de partida y que no haya escapado (los escapados son invulnerables).
-- Antes no se comprobaba el rol ni el escape: Boo!! podía teletransportar al Devilish a la zona segura.
local function isValidToonflow(character)
	if not character or not character.Parent or character:GetAttribute("Escaped") then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local role = stats:FindFirstChild("Role")
	local isAlive = stats:FindFirstChild("IsAlive")
	return role ~= nil and role.Value == StatsModule.Role.Toonflow and isAlive ~= nil and isAlive.Value
end

-- Toonflow válido más cercano; maxDistance/minDot opcionales (cono frontal).
local function findClosestToonflow(character, hrp, maxDistance, minDot)
	local best, bestDistance = nil, maxDistance or math.huge
	local forward = hrp.CFrame.LookVector

	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model ~= character and isValidToonflow(model) then
			local targetHrp = model:FindFirstChild("HumanoidRootPart")
			if targetHrp then
				local toTarget = targetHrp.Position - hrp.Position
				local distance = toTarget.Magnitude
				if distance < bestDistance or (distance == bestDistance and best == nil) then
					if not minDot or distance < 0.01 or forward:Dot(toTarget.Unit) > minDot then
						best, bestDistance = model, distance
					end
				end
			end
		end
	end

	return best
end

-- == HABILIDAD 1: HERE COMES (Rastreo + Alucinaciones) ==
AbilityFramework.Register({
	Name = "HereComes",
	Description = "Envía una mariposa que rastrea al Toonflow más cercano, revelando su aura y provocándole alucinaciones.",
	Cooldown = 18,
	CastTime = 0.3,
	Range = 60,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local targetToon = findClosestToonflow(character, hrp, TRACK_RANGE, nil)
		if not targetToon then return false, "NoTarget" end -- nada en rango: no se consume

		-- Efecto visual: Highlight de rastreo (uno por objetivo; antes se apilaban)
		local previous = targetToon:FindFirstChild("MariposaurioTracking")
		if previous then previous:Destroy() end

		local highlight = Instance.new("Highlight")
		highlight.Name = "MariposaurioTracking"
		highlight.FillColor = Color3.fromRGB(255, 100, 200)
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.Parent = targetToon
		Debris:AddItem(highlight, TRACK_SECONDS)

		-- Alucinaciones en pantalla del Toonflow
		local targetPlayer = Players:GetPlayerFromCharacter(targetToon)
		if targetPlayer and BlindEffectRemote then
			BlindEffectRemote:FireClient(targetPlayer, TRACK_SECONDS)
		end

		-- Guardar objetivo rastreado para usar con Boo!!
		lastTracked[character] = targetToon
	end,
})

-- == HABILIDAD 2: A THOUGHT (Tortura Psicológica) ==
AbilityFramework.Register({
	Name = "AThought",
	Description = "Ahorca a un Toonflow cercano infligiendo daño continuo y atormentando su mente con frases crueles.",
	Cooldown = 15,
	CastTime = 0,
	Range = 8,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		-- El Toonflow más cercano frente al Devilish (antes: el primero de workspace:GetChildren())
		local target = findClosestToonflow(character, hrp, GRAB_RANGE, 0.5)
		if not target then return false, "NoTarget" end

		local targetHrp = target:FindFirstChild("HumanoidRootPart")
		if not targetHrp then return false, "NoTarget" end

		local applied, outcome = StatsModule.ApplyDamage(target, GRAB_DAMAGE)
		if not applied then return false, "NoTarget" end

		-- Inmovilizar a la víctima (si no murió con el golpe). Se libera con un token: dos agarres
		-- seguidos ya no se sueltan el uno al otro antes de tiempo.
		if outcome ~= "Dead" then
			targetHrp.Anchored = true
			StatsModule.Stun(target, GRAB_HOLD_SECONDS)

			local holdId = (targetHrp:GetAttribute("HoldId") or 0) + 1
			targetHrp:SetAttribute("HoldId", holdId)
			task.delay(GRAB_HOLD_SECONDS, function()
				if targetHrp.Parent and targetHrp:GetAttribute("HoldId") == holdId then
					targetHrp.Anchored = false
				end
			end)
		end

		-- Frase cruel en la pantalla del agredido
		local cruelQuotes = {
			"Eres una basura...",
			"Tu madre nunca te quiso.",
			"Nadie vendrá a salvarte.",
			"Solo eres una marioneta rota.",
		}
		local targetPlayer = Players:GetPlayerFromCharacter(target)
		if targetPlayer and PopUpRemote then
			PopUpRemote:FireClient(targetPlayer, cruelQuotes[math.random(1, #cruelQuotes)])
		end
	end,
})

-- == HABILIDAD 3: BOO!! (Teleport detrás del Toon) ==
AbilityFramework.Register({
	Name = "Boo",
	Description = "Se teletransporta instantáneamente a la espalda del último Toonflow rastreado o más cercano.",
	Cooldown = 22,
	CastTime = 0.5,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		-- Último rastreado SI sigue siendo un objetivo válido; si no, el más cercano.
		-- (Antes: workspace:FindFirstChild(nombre) sin validar: llevaba al Devilish junto a un Toonflow
		-- muerto o que ya había escapado, es decir, FUERA del mapa, a la zona segura.)
		local targetChar = lastTracked[character]
		if not isValidToonflow(targetChar) then
			targetChar = findClosestToonflow(character, hrp, nil, nil)
		end
		if not targetChar then return false, "NoTarget" end

		local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetHrp then return false, "NoTarget" end

		-- Destino: BOO_BEHIND_DISTANCE studs detrás de la víctima, sin meterse en una pared
		local behind = targetHrp.CFrame * CFrame.new(0, 0, BOO_BEHIND_DISTANCE)
		local destination = behind.Position

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { character, targetChar }
		local blocked = workspace:Raycast(targetHrp.Position, destination - targetHrp.Position, rayParams)
		if blocked then
			destination = blocked.Position + blocked.Normal * 2.5
		end

		-- Conserva la orientación de la víctima (queda mirando su espalda)
		character:PivotTo(CFrame.new(destination) * targetHrp.CFrame.Rotation)
		hrp.AssemblyLinearVelocity = Vector3.zero

		VFXModule.SpawnMeleeHitVFX(destination, Color3.fromRGB(130, 0, 180))
	end,
})

-- == HABILIDAD 4: DEAD HOPE (Marioneta de Toon) ==
AbilityFramework.Register({
	Name = "DeadHope",
	Description = "Revive a un Toonflow eliminado como una marioneta bot para que ataque a sus antiguos aliados.",
	Cooldown = 45,
	CastTime = 2,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		-- Límite de marionetas simultáneas (antes se acumulaban sin límite y no desaparecían)
		local active = character:GetAttribute("ActivePuppets") or 0
		if active >= MAX_PUPPETS then return false, "TooManyPuppets" end

		if REQUIRE_DEAD_TOONFLOW then
			local deadFound = false
			for _, model in ipairs(workspace:GetChildren()) do
				local stats = model:IsA("Model") and StatsModule.GetStats(model)
				local role = stats and stats:FindFirstChild("Role")
				local isAlive = stats and stats:FindFirstChild("IsAlive")
				if role and role.Value == StatsModule.Role.Toonflow and isAlive and not isAlive.Value
					and not model:GetAttribute("PuppetRaised") and not model:GetAttribute("Escaped") then
					model:SetAttribute("PuppetRaised", true) -- cada eliminado se levanta una sola vez
					deadFound = true
					break
				end
			end
			if not deadFound then return false, "NoDeadToonflow" end
		end

		local spawnPos = hrp.CFrame * CFrame.new(0, 0, -5)

		-- Generar la marioneta usando nuestro BotController
		local puppetBot = BotController.SpawnBot(StatsModule.Role.Devilish, spawnPos, "PuppetToon")
		if not puppetBot then return false, "SpawnFailed" end

		character:SetAttribute("ActivePuppets", active + 1)
		puppetBot.Destroying:Connect(function()
			character:SetAttribute("ActivePuppets", math.max(0, (character:GetAttribute("ActivePuppets") or 1) - 1))
		end)
		Debris:AddItem(puppetBot, PUPPET_LIFETIME)

		-- Tinte oscuro / Hilos visuales para el aspecto de marioneta
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(50, 50, 50)
		highlight.OutlineColor = Color3.fromRGB(255, 0, 50)
		highlight.Parent = puppetBot
	end,
})

return MariposaurioAbilities
