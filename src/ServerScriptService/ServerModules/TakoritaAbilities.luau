--[[
	TakoritaAbilities (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.TakoritaAbilities

	Define las 3 habilidades del personaje TOONFLOW "Takorita" (Toonflow Support):
	  1. "EmergenciaSevera"   -> Canalizacion 1.7s: cura 20-36 HP a un Toonflow aliado cercano (Cooldown: 32s)
	  2. "AnnouncerAttack"    -> Onda sonora: stun 2s al Devilish + speed boost 1.3x por 3s (Cooldown: 39s)
	  3. "CuracionAumentante" -> Botiquin en suelo: pulso cada 0.7s cura 1-7 HP por 50s (Cooldown: 45s)

	Las animaciones definitivas se vincularan cuando los Rigs esten listos.
	Por ahora se usan placeholders visuales/sonoros via VFXModule.

	Dependencias:
	  - ServerScriptService.ServerModules.AbilityFramework
	  - ServerScriptService.ServerModules.StatsModule
	  - ReplicatedStorage.Framework.VFXModule
]]

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(game.ReplicatedStorage.Framework.VFXModule)

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local TakoritaAbilities = {}

-- == HABILIDAD 1: EMERGENCIA SEVERA (Curacion canalizada a aliado) ==
-- Tipo: Channeled Heal
-- Rol: Toonflow (Takorita)
-- Cooldown: 32 segundos
-- Mecanica: Takorita se canaliza inmovil (SpeedMultiplier = 0) durante 1.7s.
--   Al completar, busca el Toonflow aliado mas cercano en direccion del cursor
--   y le cura entre 20 y 36 HP.
--   Si Takorita recibe dano del Devilish durante la canalizacion, se cancela.
-- Placeholder Visual: Anillo/cruz verde sobre el objetivo durante el cast.
AbilityFramework.Register({
	Name = "EmergenciaSevera",
	Description = "Takorita canaliza 1.7s para curar a un aliado Toonflow cercano entre 20 y 36 HP. Interrumpible.",
	MaxCharges = 1,
	Cooldown = 32,
	CostType = nil,
	CostAmount = 0,
	CastTime = 1.7,
	Range = 40,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- Inmovilizar a Takorita durante la canalizacion
		StatsModule.SetSpeedMultiplier(character, 0.0)

		-- VFX de canalizacion en Takorita
		VFXModule.SpawnChannelVFX(character, 1.7)

		-- == DETECCION DE INTERRUPCION ==
		-- Si Takorita recibe dano (Health baja) durante los 1.7s, cancelar.
		local stats = StatsModule.GetStats(character)
		local healthValue = stats and stats:FindFirstChild("Health")
		local initialHealth = healthValue and healthValue.Value or 100
		local interrupted = false

		local healthConn
		if healthValue then
			healthConn = healthValue.Changed:Connect(function(newVal)
				if newVal < initialHealth then
					interrupted = true
					healthConn:Disconnect()
				end
			end)
		end

		-- Esperar los 1.7 segundos de canalizacion
		task.delay(1.7, function()
			-- Limpiar conexion de interrupcion
			if healthConn then healthConn:Disconnect() end

			if not (character and character.Parent) then return end

			-- Restaurar velocidad de Takorita
			StatsModule.ResetSpeedMultiplier(character)

			if interrupted then
				-- Canalizacion interrumpida: no se aplica la curacion
				VFXModule.SpawnStunVFX(hrp.Position, 0.4)
				print("[Takorita] EmergenciaSevera INTERRUMPIDA por dano recibido.")
				return
			end

			-- == BUSCAR TOONFLOW ALIADO MAS CERCANO EN DIRECCION DEL CURSOR ==
			local cursorPosition
			if typeof(targetData) == "Vector3" then
				cursorPosition = targetData
			else
				cursorPosition = hrp.Position + hrp.CFrame.LookVector * 20
			end

			local maxRange = params.AbilityDef.Range
			local bestTarget = nil
			local bestScore = math.huge  -- Menor score = mejor candidato

			for _, otherPlayer in ipairs(Players:GetPlayers()) do
				local otherChar = otherPlayer.Character
				if otherChar and otherChar ~= character then
					local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
					local otherStats = StatsModule.GetStats(otherChar)
					if otherHrp and otherStats then
						local otherRole = otherStats:FindFirstChild("Role")
						local otherAlive = otherStats:FindFirstChild("IsAlive")
						if otherRole and otherRole.Value == StatsModule.Role.Toonflow
							and otherAlive and otherAlive.Value then
							local distance = (otherHrp.Position - hrp.Position).Magnitude
							if distance <= maxRange then
								-- Score basado en cercania al cursor y a Takorita
								local cursorDist = (otherHrp.Position - cursorPosition).Magnitude
								local score = cursorDist + distance * 0.3
								if score < bestScore then
									bestScore = score
									bestTarget = otherChar
								end
							end
						end
					end
				end
			end

			if bestTarget then
				-- Calcular curacion aleatoria entre 20 y 36 HP
				local healAmount = math.random(20, 36)
				StatsModule.ApplyHeal(bestTarget, healAmount)

				-- VFX: Anillo/cruz verde sobre el objetivo
				VFXModule.SpawnHealPulseVFX(bestTarget, 1.5)

				print("[Takorita] EmergenciaSevera curó " .. healAmount .. " HP a " .. bestTarget.Name)
			else
				-- No se encontro aliado objetivo
				VFXModule.SpawnStunVFX(hrp.Position, 0.3)
				print("[Takorita] EmergenciaSevera: no se encontro aliado Toonflow en rango.")
			end
		end)

		print("[Takorita] EmergenciaSevera canalizando por " .. player.Name)
	end,
})

-- == HABILIDAD 2: ANNOUNCER ATTACK (Stun sonoro + Speed boost) ==
-- Tipo: Area Disruption
-- Rol: Toonflow (Takorita)
-- Cooldown: 39 segundos
-- Mecanica: Announcer emite un estruendo sonoro en area circular alrededor de Takorita.
--   Si el Devilish esta en el area: Stun 2s.
--   Takorita recibe SpeedMultiplier 1.3 por 3s.
-- Placeholder Visual: Onda expansiva (esfera expandible) + sonido de distorsion.
AbilityFramework.Register({
	Name = "AnnouncerAttack",
	Description = "Announcer emite un estruendo sonoro: stunea al Devilish 2s y da speed boost 1.3x por 3s a Takorita.",
	MaxCharges = 1,
	Cooldown = 39,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 25,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local radius = params.AbilityDef.Range

		-- VFX: Onda expansiva sonora
		VFXModule.SpawnSoundWaveVFX(character, radius, 1.0)

		-- == BUSCAR DEVILISH EN EL AREA ==
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			local otherChar = otherPlayer.Character
			if otherChar and otherChar ~= character then
				local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
				local otherStats = StatsModule.GetStats(otherChar)
				if otherHrp and otherStats then
					local otherRole = otherStats:FindFirstChild("Role")
					if otherRole and otherRole.Value == StatsModule.Role.Devilish then
						local distance = (otherHrp.Position - hrp.Position).Magnitude
						if distance <= radius then
							-- Stun al Devilish por 2s
							StatsModule.SetState(otherChar, StatsModule.CharacterState.Stunned)

							-- VFX de stun en el Devilish
							VFXModule.SpawnStunVFX(otherHrp.Position, 0.5)

							task.delay(2, function()
								if otherChar and otherChar.Parent then
									StatsModule.SetState(otherChar, StatsModule.CharacterState.Normal)
								end
							end)

							print("[Takorita] AnnouncerAttack stuneó a Devilish: " .. otherChar.Name)
						end
					end
				end
			end
		end

		-- == SPEED BOOST A TAKORITA (1.3x por 3s) ==
		StatsModule.SetSpeedMultiplier(character, 1.3)
		VFXModule.SpawnSpeedBuffVFX(character, 3)

		task.delay(3, function()
			if character and character.Parent then
				StatsModule.ResetSpeedMultiplier(character)
			end
		end)

		print("[Takorita] AnnouncerAttack activado por " .. player.Name)
	end,
})

-- == HABILIDAD 3: CURACION AUMENTANTE (Botiquin en suelo) ==
-- Tipo: Ground Object / Area Heal
-- Rol: Toonflow (Takorita)
-- Cooldown: 45 segundos
-- Mecanica: Takorita despliega un botiquin en su posicion actual.
--   Permanece activo 50 segundos. Pulsa cada 0.7s.
--   Todos los Toonflows en el radio reciben 1-7 HP por pulso.
-- Placeholder Visual: Part de botiquin + cilindro verde transparente marcando el radio.
AbilityFramework.Register({
	Name = "CuracionAumentante",
	Description = "Takorita despliega un botiquin que cura 1-7 HP cada 0.7s a Toonflows cercanos durante 50s.",
	MaxCharges = 1,
	Cooldown = 45,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local placePosition = hrp.Position
		local healRadius = 15
		local duration = 50
		local pulseInterval = 0.7

		-- VFX: Crear el botiquin visual + area cilindrica
		local medkitModel = VFXModule.SpawnMedkitVFX(placePosition, healRadius, duration)

		-- Sonido de despliegue
		VFXModule.PlaySound3D(medkitModel, VFXModule.Sounds.Buff, 0.5)

		-- == LOOP DE PULSOS DE CURACION ==
		local elapsed = 0

		task.spawn(function()
			while medkitModel and medkitModel.Parent and elapsed < duration do
				task.wait(pulseInterval)
				elapsed = elapsed + pulseInterval

				if not (medkitModel and medkitModel.Parent) then break end

				-- VFX de pulso en cada tick
				local pulsePart = medkitModel:FindFirstChild("HealPulseVFX")
				if pulsePart then
					-- Flash del cilindro verde
					local flashTween = TweenService:Create(pulsePart, TweenInfo.new(0.3), {
						Transparency = 0.2,
					})
					flashTween:Play()
					flashTween.Completed:Connect(function()
						local fadeTween = TweenService:Create(pulsePart, TweenInfo.new(0.4), {
							Transparency = 0.6,
						})
						fadeTween:Play()
					end)
				end

				-- Curar a todos los Toonflows en el radio
				for _, otherPlayer in ipairs(Players:GetPlayers()) do
					local otherChar = otherPlayer.Character
					if otherChar then
						local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
						local otherStats = StatsModule.GetStats(otherChar)
						if otherHrp and otherStats then
							local otherRole = otherStats:FindFirstChild("Role")
							local otherAlive = otherStats:FindFirstChild("IsAlive")
							if otherRole and otherRole.Value == StatsModule.Role.Toonflow
								and otherAlive and otherAlive.Value then
								local distance = (otherHrp.Position - placePosition).Magnitude
								if distance <= healRadius then
									local healAmount = math.random(1, 7)
									StatsModule.ApplyHeal(otherChar, healAmount)
								end
							end
						end
					end
				end
			end

			-- Destruir el botiquin al terminar
			if medkitModel and medkitModel.Parent then
				-- Desvanecer antes de destruir
				for _, child in ipairs(medkitModel:GetDescendants()) do
					if child:IsA("BasePart") then
						TweenService:Create(child, TweenInfo.new(0.5), { Transparency = 1 }):Play()
					end
				end
				Debris:AddItem(medkitModel, 1)
			end
		end)

		print("[Takorita] CuracionAumentante desplegada por " .. player.Name)
	end,
})

return TakoritaAbilities