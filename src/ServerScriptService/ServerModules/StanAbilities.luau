--[[
	StanAbilities (ModuleScript)
	Ubicacion: ServerScriptService.ServerModules.StanAbilities

	Define las 4 habilidades del personaje DEVILISH "Stan.oma.png":
	  Slot1 "RayoCorrupto"    -> Rayo que daña 30 + lanza Pop-ups corruptos al Toonflow. CD: 18s
	  Slot2 "BetterCallStan"  -> Invoca 2 clones que persiguen y envenenan. CD: 40s
	  Slot3 "CorrupcionGrave" -> Rastro de veneno ampliado + reduce velocidad. CD: 30s
	  Slot4 "CambioArma"      -> Alterna entre M1 melee y M1 láser (Taser). CD: 10s

	PASIVA: "Corrupcion Inminente"
	  - Cada 20s deja rastros de veneno por 5s al moverse.

	M1 ADAPTATIVO:
	  - Modo melee: golpe directo 22 dmg, 30% prob de Burn 1s.
	  - Modo láser: raycast 15 dmg + efecto aleatorio 1s (Slowness/Burn/Corruption).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local AbilityFramework = require(game:GetService("ServerScriptService").ServerModules.AbilityFramework)
local StatsModule = require(game:GetService("ServerScriptService").ServerModules.StatsModule)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)

local Remotes = ReplicatedStorage.Framework.Remotes
local PopupRemote = Remotes:FindFirstChild("TriggerPopups")

local BotController
local function getBotController()
	if not BotController then
		local module = ServerScriptService:FindFirstChild("BotController")
		if module then
			BotController = require(module)
		end
	end
	return BotController
end

local StanAbilities = {}

-- == COLOR TEMA DE STAN ==
local STAN_COLOR = Color3.fromRGB(80, 0, 100)

-- Personaje vivo, con Stats de partida y rol Toonflow que no haya escapado (los escapados son invulnerables)
local function isValidToonflow(character)
	if not character or not character.Parent or character:GetAttribute("Escaped") then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local role = stats:FindFirstChild("Role")
	local isAlive = stats:FindFirstChild("IsAlive")
	return role ~= nil and role.Value == StatsModule.Role.Toonflow and isAlive ~= nil and isAlive.Value
end

-- ¿Sigue Stan en condiciones de actuar? (vivo y sin aturdir/derribar). Se usa tras las cargas
-- con espera: antes un Stan aturdido o muerto durante la carga disparaba igualmente.
local function canStillAct(character)
	if not (character and character.Parent) then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local isAlive = stats:FindFirstChild("IsAlive")
	local state = stats:FindFirstChild("State")
	if not (isAlive and isAlive.Value) then return false end
	return state == nil or state.Value == StatsModule.CharacterState.Normal
end

---------------------------------------------------------
-- HELPER: APLICAR ESTADO ALTERADO INLINE
---------------------------------------------------------

-- Daño por tiempo SIN apilar: si el efecto ya está activo solo se amplía su duración.
-- Antes cada contacto con el rastro (Touched se dispara muchas veces por segundo) lanzaba otro
-- hilo de veneno y el daño se multiplicaba por el número de toques.
local activeDots = setmetatable({}, { __mode = "k" })

local function applyDot(targetChar, effectName, duration, damagePerTick)
	local effects = activeDots[targetChar]
	if not effects then
		effects = {}
		activeDots[targetChar] = effects
	end

	local endsAt = os.clock() + duration
	if effects[effectName] then
		effects[effectName] = math.max(effects[effectName], endsAt)
		return
	end
	effects[effectName] = endsAt

	task.spawn(function()
		while targetChar.Parent and effects[effectName] and os.clock() < effects[effectName] do
			task.wait(0.5)
			-- ApplyDamage devuelve false si el objetivo murió o escapó: el efecto termina
			if not StatsModule.ApplyDamage(targetChar, damagePerTick) then break end
		end
		effects[effectName] = nil
	end)
end

local function applyStatusEffect(targetChar, effectName, duration)
	if not (targetChar and targetChar.Parent) then return end
	duration = duration or 3

	if effectName == "Poison" then
		applyDot(targetChar, "Poison", duration, 2)
	elseif effectName == "Burn" then
		applyDot(targetChar, "Burn", duration, 3)
	elseif effectName == "Slowness" then
		-- No pisar un aturdimiento/derribo con una ralentización (SetSpeedMultiplier(0.5) lo anulaba)
		local stats = StatsModule.GetStats(targetChar)
		local state = stats and stats:FindFirstChild("State")
		if not stats or (state and state.Value ~= StatsModule.CharacterState.Normal) then return end

		-- Token: una ralentización más reciente no se cancela cuando caduca la anterior
		local slowId = (targetChar:GetAttribute("SlowId") or 0) + 1
		targetChar:SetAttribute("SlowId", slowId)
		StatsModule.SetSpeedMultiplier(targetChar, 0.5)
		task.delay(duration, function()
			if targetChar.Parent and targetChar:GetAttribute("SlowId") == slowId then
				StatsModule.ResetSpeedMultiplier(targetChar)
			end
		end)
	elseif effectName == "Corruption" then
		local previous = targetChar:FindFirstChild("CorruptionEffect")
		if previous then previous:Destroy() end

		local hl = Instance.new("Highlight")
		hl.Name = "CorruptionEffect"
		hl.FillColor = STAN_COLOR
		hl.OutlineColor = Color3.fromRGB(120, 0, 150)
		hl.FillTransparency = 0.4
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = targetChar
		Debris:AddItem(hl, duration)
	end
end

---------------------------------------------------------
-- HELPER: REVELAR AURA
---------------------------------------------------------
local function revealAura(targetChar, devilishChar, duration)
	if targetChar and targetChar.Parent then
		VFXModule.SpawnRevealVFX(targetChar, duration)
	end
end

---------------------------------------------------------
-- PASIVA: CORRUPCION INMINENTE
-- (MatchManager la inicia al asignar a Stan; antes nadie la llamaba)
---------------------------------------------------------
function StanAbilities.StartPassiveTrail(character)
	-- Identificador de ejecución: un hilo antiguo (personaje reutilizado entre partidas) se detiene
	-- solo en cuanto se inicia uno nuevo, y todos paran al morir Stan o terminar la partida.
	local runId = (character:GetAttribute("StanPassiveId") or 0) + 1
	character:SetAttribute("StanPassiveId", runId)

	local function stillActive()
		if not (character and character.Parent) then return false end
		if character:GetAttribute("StanPassiveId") ~= runId then return false end
		local stats = StatsModule.GetStats(character)
		local isAlive = stats and stats:FindFirstChild("IsAlive")
		return isAlive ~= nil and isAlive.Value
	end

	task.spawn(function()
		while true do
			for _ = 1, 20 do -- cada 20 segundos
				if not stillActive() then return end
				task.wait(1)
			end

			local startTime = os.clock()
			while os.clock() - startTime < 5 do -- dura 5 segundos soltando rastro
				if not stillActive() then return end
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then
					StanAbilities.SpawnTrailPart(hrp.CFrame - Vector3.new(0, 2.5, 0), Vector3.new(3, 0.2, 3), 3)
				end
				task.wait(0.4)
			end
		end
	end)
end

function StanAbilities.SpawnTrailPart(cframe, size, poisonDuration)
	local part = Instance.new("Part")
	part.Name = "CorruptionTrail"
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(40, 0, 50)
	part.Transparency = 0.3
	part.Parent = workspace

	part.Touched:Connect(function(otherPart)
		-- Ancestro Model (no Parent): un accesorio o parte anidada no debe librarse del veneno
		local toonChar = otherPart:FindFirstAncestorOfClass("Model")
		if toonChar and isValidToonflow(toonChar) then
			applyDot(toonChar, "Poison", poisonDuration or 3, 2)
		end
	end)

	Debris:AddItem(part, 6)
end

---------------------------------------------------------
-- M1 ADAPTATIVO (Cuerpo a Cuerpo / Taser Laser)
-- CombatServer llama aquí cuando Stan tiene el modo láser activo (CambioArma).
---------------------------------------------------------
function StanAbilities.ExecuteM1(character, targetCFrame)
	local isLaserMode = character:GetAttribute("LaserModeActive") or false

	if isLaserMode then
		task.wait(1) -- 1 segundo de carga/retraso

		-- Revalidar tras la carga: aturdido, derribado o muerto => el láser no sale
		if not canStillAct(character) then return end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local rayOrigin = hrp.Position
		local rayDirection = hrp.CFrame.LookVector * 60
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = { character }
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		local hitChar = result and result.Instance:FindFirstAncestorOfClass("Model")
		if hitChar and isValidToonflow(hitChar) then
			local origin = hrp.Position + Vector3.new(0, 1, 0)
			VFXModule.SpawnProjectileVFX(origin, result.Position, STAN_COLOR)

			if StatsModule.ApplyDamage(hitChar, 15) then
				local effects = { "Slowness", "Burn", "Corruption" }
				applyStatusEffect(hitChar, effects[math.random(1, #effects)], 1)
			end
		end
	else
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local forward = hrp.CFrame.LookVector
		for _, target in ipairs(workspace:GetChildren()) do
			if target ~= character and isValidToonflow(target) then
				local targetHrp = target:FindFirstChild("HumanoidRootPart")
				if targetHrp then
					local toTarget = targetHrp.Position - hrp.Position
					local dist = toTarget.Magnitude
					-- Solo hacia delante (antes golpeaba a todos los que estuvieran a 7 studs, incluso a la espalda)
					if dist <= 7 and (dist < 0.01 or forward:Dot(toTarget.Unit) > 0) then
						if StatsModule.ApplyDamage(target, 22) then
							VFXModule.SpawnMeleeHitVFX(targetHrp.Position, STAN_COLOR)
							if math.random() <= 0.3 then
								applyStatusEffect(target, "Burn", 1)
							end
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------
-- HABILIDAD 1: RAYO CORRUPTO
---------------------------------------------------------
AbilityFramework.Register({
	Name = "RayoCorrupto",
	Description = "Stan dispara un rayo corrupto. 30 dmg + lanza Pop-ups en la pantalla del Toonflow por 5s.",
	MaxCharges = 1,
	Cooldown = 18,
	CostType = nil,
	CostAmount = 0,
	CastTime = 1,
	Range = 80,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		local targetData = params.TargetData
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		-- La carga de 1 s va en otro hilo: antes Execute esperaba ese segundo y la respuesta al
		-- cliente (y el cooldown en el HUD) llegaba con retraso.
		task.spawn(function()
			task.wait(1)

			-- Interrumpido (aturdido, derribado, muerto): el rayo no sale y la carga se consume
			if not canStillAct(character) then return end
			local currentHrp = character:FindFirstChild("HumanoidRootPart")
			if not currentHrp then return end

			local targetPosition
			if typeof(targetData) == "Vector3" then
				targetPosition = targetData
			else
				targetPosition = currentHrp.Position + currentHrp.CFrame.LookVector * 80
			end

			local offset = targetPosition - currentHrp.Position
			local direction = offset.Magnitude > 0.1 and offset.Unit or currentHrp.CFrame.LookVector

			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = { character }
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude

			local result = workspace:Raycast(currentHrp.Position, direction * 80, raycastParams)

			local endPoint = result and result.Position or (currentHrp.Position + direction * 80)
			local origin = currentHrp.Position + Vector3.new(0, 1, 0)
			VFXModule.SpawnProjectileVFX(origin, endPoint, STAN_COLOR)
			VFXModule.PlaySound3D(currentHrp, VFXModule.Sounds.Plasma, 0.6)

			local toonChar = result and result.Instance:FindFirstAncestorOfClass("Model")
			local targetPlayer = toonChar and Players:GetPlayerFromCharacter(toonChar)

			-- Solo si el daño se aplicó (un Toonflow que ya escapó no recibe ni el impacto ni los pop-ups)
			if toonChar and targetPlayer and isValidToonflow(toonChar) and StatsModule.ApplyDamage(toonChar, 30) then
				VFXModule.SpawnMeleeHitVFX(result.Position, STAN_COLOR)
				if PopupRemote then
					PopupRemote:FireClient(targetPlayer, 5)
				end
			end
		end)
	end,
})

---------------------------------------------------------
-- HABILIDAD 2: BETTER CALL STAN
---------------------------------------------------------
AbilityFramework.Register({
	Name = "BetterCallStan",
	Description = "Stan invoca 2 clones que persiguen y envenenan Toonflows. CD: 40s",
	MaxCharges = 1,
	Cooldown = 40,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local bc = getBotController()
		if not bc then
			warn("[Stan] BotController no encontrado, no se pueden invocar clones.")
			return false, "NoBotController" -- antes devolvía nil: se consumía el cooldown sin invocar nada
		end

		local spawned = 0
		for i = 1, 2 do
			local offset = Vector3.new((i == 1 and 4 or -4), 0, 2)
			local cloneCFrame = hrp.CFrame * CFrame.new(offset)

			local cloneBot = bc.SpawnBot(StatsModule.Role.Devilish, cloneCFrame, "StanClone_" .. i)
			if cloneBot then
				spawned += 1
				cloneBot:SetAttribute("IsClone", true)

				local hl = Instance.new("Highlight")
				hl.Name = "CloneHighlight"
				hl.FillColor = STAN_COLOR
				hl.OutlineColor = Color3.fromRGB(120, 0, 150)
				hl.FillTransparency = 0.3
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = cloneBot

				local cloneHrp = cloneBot:FindFirstChild("HumanoidRootPart")
				if cloneHrp then
					local hitDebounce = false
					cloneHrp.Touched:Connect(function(hit)
						if hitDebounce then return end
						local toonChar = hit:FindFirstAncestorOfClass("Model")
						if not (toonChar and isValidToonflow(toonChar)) then return end

						hitDebounce = true
						if StatsModule.ApplyDamage(toonChar, 17) then
							applyStatusEffect(toonChar, "Poison", 5)
							revealAura(toonChar, character, 4)

							local hitHrp = toonChar:FindFirstChild("HumanoidRootPart")
							if hitHrp then
								VFXModule.SpawnMeleeHitVFX(hitHrp.Position, STAN_COLOR)
							end
						end

						-- Destroy (no Parent = nil): el clon se elimina de verdad tras el golpe
						task.delay(0.1, function()
							if cloneBot.Parent then cloneBot:Destroy() end
						end)
					end)
				end

				Debris:AddItem(cloneBot, 15)
			end
		end

		if spawned == 0 then return false, "SpawnFailed" end
	end,
})

---------------------------------------------------------
-- HABILIDAD 3: CORRUPCION GRAVE DE CARTUCHO (TRAMPA)
---------------------------------------------------------
AbilityFramework.Register({
	Name = "CorrupcionGrave",
	Description = "Stan reduce su velocidad y deja un rastro de veneno ampliado por 8s. CD: 30s",
	MaxCharges = 1,
	Cooldown = 30,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		StatsModule.SetSpeedMultiplier(character, 0.5)

		VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.6)
		local hl = Instance.new("Highlight")
		hl.Name = "CorrupcionGraveVFX"
		hl.FillColor = STAN_COLOR
		hl.OutlineColor = Color3.fromRGB(120, 0, 150)
		hl.FillTransparency = 0.3
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = character
		Debris:AddItem(hl, 8)

		local duration = 8
		local elapsed = 0

		task.spawn(function()
			while elapsed < duration and character and character.Parent do
				local currentHrp = character:FindFirstChild("HumanoidRootPart")
				if currentHrp then
					StanAbilities.SpawnTrailPart(currentHrp.CFrame - Vector3.new(0, 2, 0), Vector3.new(6, 0.2, 6), 5)
				end
				task.wait(0.3)
				elapsed = elapsed + 0.3
			end

			-- ResetSpeedMultiplier respeta un aturdimiento activo (no lo anula)
			if character and character.Parent then
				StatsModule.ResetSpeedMultiplier(character)
			end
		end)
	end,
})

---------------------------------------------------------
-- HABILIDAD 4: CAMBIO (MODO ARMA LASER)
-- LaserModeActive lo lee CombatServer: en modo láser el M1 es StanAbilities.ExecuteM1.
---------------------------------------------------------
AbilityFramework.Register({
	Name = "CambioArma",
	Description = "Stan alterna entre M1 melee y M1 laser (Taser). CD: 10s",
	MaxCharges = 1,
	Cooldown = 10,
	CostType = nil,
	CostAmount = 0,
	CastTime = 0,
	Range = 0,

	Execute = function(params)
		local character = params.Character
		local player = params.Player
		if not (character and player) then return false, "NoCharacter" end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		local currentMode = character:GetAttribute("LaserModeActive") or false
		local newMode = not currentMode
		character:SetAttribute("LaserModeActive", newMode)

		VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.5)
		local previous = character:FindFirstChild("CambioArmaVFX")
		if previous then previous:Destroy() end

		local hl = Instance.new("Highlight")
		hl.Name = "CambioArmaVFX"
		hl.FillColor = newMode and Color3.fromRGB(255, 0, 0) or STAN_COLOR
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hl.FillTransparency = 0.3
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = character
		Debris:AddItem(hl, 1.5)
	end,
})

return StanAbilities
