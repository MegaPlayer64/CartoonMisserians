--[[
	MariposaurioAbilities (ModuleScript)
	Registro oficial de habilidades para Mariposaurio en AbilityFramework.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local AbilityFramework = require(ReplicatedStorage.Framework.AbilityFramework)
local StatsModule = require(ReplicatedStorage.Framework.StatsModule)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)
local BotController = require(game:GetService("ServerScriptService"):WaitForChild("BotController"))

local Remotes = ReplicatedStorage.Framework.Remotes
local BlindEffectRemote = Remotes:FindFirstChild("BlindEffect")
local PopUpRemote = Remotes:FindFirstChild("TriggerPopups") -- Para los mensajes crueles en pantalla
local MariposaurioAbilities = {}

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
		if not hrp then return end

		-- Buscar al Toonflow más cercano
		local targetToon = nil
		local shortestDist = 60

		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if c and c ~= character then
				local targetHrp = c:FindFirstChild("HumanoidRootPart")
				local stats = StatsModule.GetStats(c)
				local isAlive = stats and stats:FindFirstChild("IsAlive") and stats.IsAlive.Value

				if isAlive and targetHrp then
					local dist = (targetHrp.Position - hrp.Position).Magnitude
					if dist < shortestDist then
						shortestDist = dist
						targetToon = c
					end
				end
			end
		end

		if targetToon then
			local targetHrp = targetToon:FindFirstChild("HumanoidRootPart")

			-- Efecto visual: Highlight de rastreo
			local highlight = Instance.new("Highlight")
			highlight.Name = "MariposaurioTracking"
			highlight.FillColor = Color3.fromRGB(255, 100, 200)
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.Parent = targetToon

			-- Alucinaciones en pantalla del Toonflow por 5 segundos
			local targetPlayer = Players:GetPlayerFromCharacter(targetToon)
			if targetPlayer and BlindEffectRemote then
				BlindEffectRemote:FireClient(targetPlayer, 5)
			end

			-- Guardar objetivo rastreado en el atributo para usar con Boo!!
			character:SetAttribute("LastTrackedToon", targetToon.Name)

			task.delay(5, function()
				if highlight then highlight:Destroy() end
			end)
			print("[Mariposaurio] Mariposa enviada a " .. targetToon.Name)
		end
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
		if not hrp then return end

		-- Detectar objetivo en frente
		local origin = hrp.Position
		local forward = hrp.CFrame.LookVector

		for _, target in ipairs(workspace:GetChildren()) do
			local targetHrp = target:FindFirstChild("HumanoidRootPart")
			local targetHum = target:FindFirstChildOfClass("Humanoid")
			local targetStats = StatsModule.GetStats(target)
			local targetRole = targetStats and targetStats:FindFirstChild("Role")

			-- Solo objetivos Toonflow vivos
			if target ~= character and targetHrp and targetHum and targetHum.Health > 0
				and targetRole and targetRole.Value == StatsModule.Role.Toonflow then
				local toTarget = (targetHrp.Position - origin)
				if toTarget.Magnitude <= 8 and forward:Dot(toTarget.Unit) > 0.5 then

					-- Inmovilizar a la víctima brevemente
					targetHrp.Anchored = true
					StatsModule.ApplyDamage(target, 20)

					-- Lista de frases crueles psicológicas
					local cruelQuotes = {
						"Eres una basura...",
						"Tu madre nunca te quiso.",
						"Nadie vendrá a salvarte.",
						"Solo eres una marioneta rota."
					}
					local chosenQuote = cruelQuotes[math.random(1, #cruelQuotes)]

					-- Desplegar mensaje flotante en la pantalla del agredido
					local targetPlayer = Players:GetPlayerFromCharacter(target)
					if targetPlayer and PopUpRemote then
						PopUpRemote:FireClient(targetPlayer, chosenQuote)
					end

					task.delay(2.5, function()
						if targetHrp then targetHrp.Anchored = false end
					end)

					print("[Mariposaurio] Tortura aplicada a " .. target.Name)
					break
				end
			end
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
		if not hrp then return end

		local targetName = character:GetAttribute("LastTrackedToon")
		local targetChar = targetName and workspace:FindFirstChild(targetName)

		-- Si no hay objetivo rastreado previo, busca al Toonflow más cercano
		if not targetChar then
			local shortestDist = math.huge
			for _, p in ipairs(Players:GetPlayers()) do
				local c = p.Character
				if c and c ~= character then
					local cHrp = c:FindFirstChild("HumanoidRootPart")
					local cStats = StatsModule.GetStats(c)
					local cRole = cStats and cStats:FindFirstChild("Role")
					local cAlive = cStats and cStats:FindFirstChild("IsAlive") and cStats.IsAlive.Value
					if cHrp and cAlive and cRole and cRole.Value == StatsModule.Role.Toonflow then
						local dist = (cHrp.Position - hrp.Position).Magnitude
						if dist < shortestDist then
							shortestDist = dist
							targetChar = c
						end
					end
				end
			end
		end

		if targetChar then
			local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
			if targetHrp then
				-- Teleport a 4 studs DETRÁS de la víctima
				local backCFrame = targetHrp.CFrame * CFrame.new(0, 0, 4)
				character:PivotTo(backCFrame)

				-- Sonido/VFX de aparición espeluznante
				VFXModule.SpawnMeleeHitVFX(backCFrame.Position, Color3.fromRGB(130, 0, 180))
				print("[Mariposaurio] ¡Boo!! Apareció detrás de " .. targetChar.Name)
			end
		end
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
		if not hrp then return end

		-- Buscar Toonflow caído cerca
		local spawnPos = hrp.CFrame * CFrame.new(0, 0, -5)

		-- Generar la marioneta usando nuestro BotController
		local puppetBot = BotController.SpawnBot(StatsModule.Role.Devilish, spawnPos, "PuppetToon")
		if puppetBot then
			-- Tinte oscuro / Hilos visuales para el aspecto de marioneta
			local highlight = Instance.new("Highlight")
			highlight.FillColor = Color3.fromRGB(50, 50, 50)
			highlight.OutlineColor = Color3.fromRGB(255, 0, 50)
			highlight.Parent = puppetBot

			print("[Mariposaurio] Marioneta levantada con 'dead hope'.")
		end
	end,
})

return MariposaurioAbilities