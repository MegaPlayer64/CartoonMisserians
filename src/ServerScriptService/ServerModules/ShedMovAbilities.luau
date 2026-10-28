--[[
	ShedMovAbilities (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.ShedMovAbilities

	Devilish: Shed.mov (CharacterDatabase.Name = "Shedmov").

	  Pasiva  "Mantente fuera"          -> StartPassive (la inicia MatchManager)
	  Slot 1  CargaMotosierra            (24 s)
	  Slot 2  FueraDeMiCobertizo         (30 s)
	  Slot 3  BienvenidaAPonyville       (90 s, ultimate)

	Todo el balance está en las constantes de abajo.

	CONTRATO con AbilityFramework.Execute: `return false, motivo` = no se ejecutó y se reembolsa.
	Las tres son habilidades de "área/movimiento": fallar al aire sigue consumiendo el cooldown (whiffing).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local AbilityFramework = require(ServerScriptService.ServerModules.AbilityFramework)
local StatsModule = require(ServerScriptService.ServerModules.StatsModule)
local TaskManager = require(ServerScriptService.ServerModules.TaskManager)
local VFXModule = require(ReplicatedStorage.Framework.VFXModule)

local ShedMovAbilities = {}

-- == COLOR TEMA ==
local SHED_COLOR = Color3.fromRGB(57, 216, 110)
local BLOOD_COLOR = Color3.fromRGB(170, 0, 20)

-- == PASIVA: MANTENTE FUERA ==
local TERROR_RADIUS_PASSIVE = 0.5 -- Modo Pasiva: radio de terror al 50% fuera de persecución
local CHASE_ENTER_RADIUS = 25 -- studs; igual que la capa de persecución de la música (MusicManagerClient)
local CHASE_LOSE_SECONDS = 3 -- sin ver a nadie este tiempo => sale de persecución
local CHASE_SPEED_MULTIPLIER = 1.10 -- Modo Agresiva: +10% de velocidad
local PASSIVE_TICK_SECONDS = 0.25
-- Ruido continuo de la motosierra en persecución. PENDIENTE: pon aquí el asset ("rbxassetid://...").
-- Mientras esté vacío no se crea el sonido (la pasiva funciona igual).
local CHAINSAW_SOUND_ID = ""
local CHAINSAW_SOUND_VOLUME = 0.8
local CHAINSAW_SOUND_MAX_DISTANCE = 90

-- == HABILIDAD 1: CARGA DE MOTOSIERRA ==
local CHARGE_SPEED = 48 -- studs/s
local CHARGE_DURATION = 1.75 -- s (unos 85 studs)
local CHARGE_HIT_RADIUS = 4.5
local CHARGE_WALL_CHECK = 3
local CHARGE_DAMAGE = 30
local BLEED_DURATION = 6
local BLEED_TICK_DAMAGE = 3
local BLEED_TICK_SECONDS = 1
local CHARGE_RECOVERY_SECONDS = 1.2 -- recuperación si falla (aturdimiento propio)

-- == HABILIDAD 2: ¡FUERA DE MI COBERTIZO! ==
local SCREAM_RADIUS = 45
local SCREAM_SLOW_MULTIPLIER = 0.5 -- Lentitud I: velocidad al 50%
local SCREAM_SLOW_SECONDS = 3
local SCREAM_REVEAL_SECONDS = 6
local SCREAM_INTERRUPT_SECONDS = 1.0 -- tiempo que no pueden retomar tareas/reanimaciones

-- == HABILIDAD 3 (ULTIMATE): BIENVENIDA A PONYVILLE ==
local BERSERK_SECONDS = 15
local BERSERK_SPEED_MULTIPLIER = 1.20 -- +20% de velocidad
local BERSERK_ATTACK_SPEED = 1.50 -- +50% de velocidad de ataque

---------------------------------------------------------
-- AUXILIARES
---------------------------------------------------------

-- Toonflow vivo, con Stats de partida y que no haya escapado (los escapados son invulnerables).
local function isValidToonflow(character)
	if not character or not character.Parent or character:GetAttribute("Escaped") then return false end
	local stats = StatsModule.GetStats(character)
	if not stats then return false end
	local role = stats:FindFirstChild("Role")
	local isAlive = stats:FindFirstChild("IsAlive")
	return role ~= nil and role.Value == StatsModule.Role.Toonflow and isAlive ~= nil and isAlive.Value
end

local function isStanding(character)
	return not character:GetAttribute("IsDowned")
end

local function isAlive(character)
	local stats = StatsModule.GetStats(character)
	local alive = stats and stats:FindFirstChild("IsAlive")
	return alive ~= nil and alive.Value
end

local function isStunned(character)
	local stats = StatsModule.GetStats(character)
	local state = stats and stats:FindFirstChild("State")
	return state ~= nil and state.Value == StatsModule.CharacterState.Stunned
end

-- Sangrado: daño por tiempo SIN apilar. Un nuevo impacto solo renueva la duración.
-- Se corta si el objetivo cae derribado (el desangrado ya tiene su propio temporizador) o muere.
local activeBleeds = setmetatable({}, { __mode = "k" })

local function applyBleed(target)
	local endsAt = os.clock() + BLEED_DURATION
	if activeBleeds[target] then
		activeBleeds[target] = endsAt
		return
	end
	activeBleeds[target] = endsAt
	target:SetAttribute("Bleeding", true)

	task.spawn(function()
		while target.Parent and activeBleeds[target] and os.clock() < activeBleeds[target] do
			task.wait(BLEED_TICK_SECONDS)
			if target:GetAttribute("IsDowned") then break end
			if not StatsModule.ApplyDamage(target, BLEED_TICK_DAMAGE) then break end
		end
		activeBleeds[target] = nil
		if target.Parent then
			target:SetAttribute("Bleeding", nil)
		end
	end)
end

-- Revelar posición: Highlight visible a través de las paredes (AlwaysOnTop). Uno por objetivo.
local function revealPosition(target)
	local previous = target:FindFirstChild("ShedRevealHighlight")
	if previous then previous:Destroy() end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ShedRevealHighlight"
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = target
	Debris:AddItem(highlight, SCREAM_REVEAL_SECONDS)

	-- Atributo por si la UI o otros sistemas quieren leer "Revealed"; el token evita que un
	-- grito antiguo apague la revelación de uno más reciente
	local revealId = (target:GetAttribute("RevealId") or 0) + 1
	target:SetAttribute("RevealId", revealId)
	target:SetAttribute("Revealed", true)
	task.delay(SCREAM_REVEAL_SECONDS, function()
		if target.Parent and target:GetAttribute("RevealId") == revealId then
			target:SetAttribute("Revealed", false)
		end
	end)
end

---------------------------------------------------------
-- PASIVA: MANTENTE FUERA
---------------------------------------------------------

local function setChainsawNoise(character, enabled)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local sound = hrp:FindFirstChild("ChainsawNoise")

	if not enabled then
		if sound then sound:Stop() end
		return
	end

	if CHAINSAW_SOUND_ID == "" then return end -- sin asset todavía
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "ChainsawNoise"
		sound.SoundId = CHAINSAW_SOUND_ID
		sound.Looped = true
		sound.Volume = CHAINSAW_SOUND_VOLUME
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = CHAINSAW_SOUND_MAX_DISTANCE
		sound.Parent = hrp
	end
	if not sound.IsPlaying then sound:Play() end
end

-- Modo Agresiva (persecución): +10% de velocidad, radio de terror completo y ruido de motosierra.
-- Modo Pasiva: radio de terror al 50%, sin bono ni ruido.
local function setChaseMode(character, chasing)
	if chasing then
		StatsModule.ApplySpeedMultiplier(character, "ShedChase", CHASE_SPEED_MULTIPLIER)
		character:SetAttribute("TerrorRadiusMultiplier", 1)
	else
		StatsModule.RemoveSpeedMultiplier(character, "ShedChase")
		character:SetAttribute("TerrorRadiusMultiplier", TERROR_RADIUS_PASSIVE)
	end
	character:SetAttribute("ShedChasing", chasing)
	setChainsawNoise(character, chasing)
end

-- Persecución = un Toonflow en pie, a menos de CHASE_ENTER_RADIUS y con línea de visión directa
local function hasChaseTarget(character, hrp)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local origin = hrp.Position + Vector3.new(0, 1.5, 0)

	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model ~= character and isValidToonflow(model) and isStanding(model) then
			local targetHrp = model:FindFirstChild("HumanoidRootPart")
			if targetHrp then
				local offset = targetHrp.Position - origin
				if offset.Magnitude <= CHASE_ENTER_RADIUS then
					rayParams.FilterDescendantsInstances = { character, model }
					if not workspace:Raycast(origin, offset, rayParams) then
						return true
					end
				end
			end
		end
	end
	return false
end

-- La inicia MatchManager al asignar a Shed.mov. Un identificador evita hilos duplicados si el personaje
-- se reutiliza entre partidas, y el hilo termina solo al morir o acabar la partida.
function ShedMovAbilities.StartPassive(character)
	local runId = (character:GetAttribute("ShedPassiveId") or 0) + 1
	character:SetAttribute("ShedPassiveId", runId)

	local function stillActive()
		return character.Parent ~= nil
			and character:GetAttribute("ShedPassiveId") == runId
			and isAlive(character)
	end

	setChaseMode(character, false) -- empieza en modo Pasiva

	task.spawn(function()
		local chasing = false
		local lastSeen = 0

		while stillActive() do
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local now = os.clock()
				if hasChaseTarget(character, hrp) then
					lastSeen = now
					if not chasing then
						chasing = true
						setChaseMode(character, true)
					end
				elseif chasing and now - lastSeen > CHASE_LOSE_SECONDS then
					chasing = false
					setChaseMode(character, false)
				end
			end
			task.wait(PASSIVE_TICK_SECONDS)
		end

		-- Limpieza: sin bono ni ruido, ni radio de terror modificado
		if character.Parent then
			StatsModule.RemoveSpeedMultiplier(character, "ShedChase")
			setChainsawNoise(character, false)
			character:SetAttribute("ShedChasing", nil)
			if character:GetAttribute("ShedPassiveId") == runId then
				character:SetAttribute("TerrorRadiusMultiplier", nil)
			end
		end
	end)
end

---------------------------------------------------------
-- HABILIDAD 1: CARGA DE MOTOSIERRA
---------------------------------------------------------
AbilityFramework.Register({
	Name = "CargaMotosierra",
	Description = "Embestida rápida en línea recta. Al impactar a un Toonflow causa daño y Sangrado; si falla, Shed.mov queda en recuperación.",
	Cooldown = 24,
	CastTime = 0,
	Range = 85,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		-- Dirección: hacia el punto apuntado (TargetData ya viene saneado por AbilityServer);
		-- sin objetivo, hacia donde mira el personaje. Siempre horizontal.
		local direction = hrp.CFrame.LookVector
		local aim = params.TargetData
		if typeof(aim) == "Vector3" then
			local flat = Vector3.new(aim.X - hrp.Position.X, 0, aim.Z - hrp.Position.Z)
			if flat.Magnitude > 0.1 then
				direction = flat
			end
		end
		direction = Vector3.new(direction.X, 0, direction.Z)
		if direction.Magnitude < 0.01 then return false, "NoDirection" end
		direction = direction.Unit

		-- Mirar hacia donde carga
		character:PivotTo(CFrame.lookAt(hrp.Position, hrp.Position + direction))

		local attachment = Instance.new("Attachment")
		attachment.Name = "ChainsawAttachment"
		attachment.Parent = hrp

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name = "ChainsawSprintForce"
		linearVelocity.MaxForce = 100000
		linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.VectorVelocity = direction * CHARGE_SPEED
		linearVelocity.Attachment0 = attachment
		linearVelocity.Parent = hrp

		-- Red de seguridad: pase lo que pase, la fuerza desaparece
		Debris:AddItem(linearVelocity, CHARGE_DURATION + 0.5)
		Debris:AddItem(attachment, CHARGE_DURATION + 0.5)

		task.spawn(function()
			local hitTarget = nil
			local interrupted = false

			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			overlapParams.FilterDescendantsInstances = { character }

			local wallParams = RaycastParams.new()
			wallParams.FilterType = Enum.RaycastFilterType.Exclude
			wallParams.FilterDescendantsInstances = { character }

			local startTime = os.clock()
			local ok, err = pcall(function()
				while os.clock() - startTime < CHARGE_DURATION do
					if not hrp.Parent or not isAlive(character) or isStunned(character) then
						interrupted = true
						break
					end

					-- Impacto: un Toonflow EN PIE cerca del frente (se busca el Model ancestro: antes
					-- se miraba part.Parent y un accesorio o parte anidada se escapaba)
					local center = hrp.Position + direction * 1.5
					for _, part in ipairs(workspace:GetPartBoundsInRadius(center, CHARGE_HIT_RADIUS, overlapParams)) do
						local model = part:FindFirstAncestorOfClass("Model")
						if model and model ~= character and isValidToonflow(model) and isStanding(model) then
							hitTarget = model
							break
						end
					end
					if hitTarget then break end

					-- Pared delante: la carga termina (cuenta como fallo)
					local wall = workspace:Raycast(hrp.Position, direction * CHARGE_WALL_CHECK, wallParams)
					if wall and wall.Instance.CanCollide and not wall.Instance:FindFirstAncestorOfClass("Model") then
						break
					end

					task.wait(0.05)
				end
			end)

			-- Limpieza SIEMPRE, también si el bucle lanzó un error
			linearVelocity:Destroy()
			attachment:Destroy()
			if not ok then
				warn("[ShedMov] Error en CargaMotosierra: " .. tostring(err))
			end

			if hitTarget then
				-- ApplyDamage respeta Derribado/Muerto/Escapado (antes se usaba Humanoid:TakeDamage)
				if StatsModule.ApplyDamage(hitTarget, CHARGE_DAMAGE) then
					applyBleed(hitTarget)
					local targetHrp = hitTarget:FindFirstChild("HumanoidRootPart")
					if targetHrp then
						VFXModule.SpawnMeleeHitVFX(targetHrp.Position, BLOOD_COLOR)
					end
				end
			elseif not interrupted and isAlive(character) then
				-- Falló: breve recuperación. StatsModule.Stun no hace nada si Shed.mov es inmune (ultimate).
				StatsModule.Stun(character, CHARGE_RECOVERY_SECONDS)
			end
		end)
	end,
})

---------------------------------------------------------
-- HABILIDAD 2: ¡FUERA DE MI COBERTIZO!
---------------------------------------------------------
AbilityFramework.Register({
	Name = "FueraDeMiCobertizo",
	Description = "Grito en un área grande: Lentitud I (3 s), cancela tareas y reanimaciones en curso y revela la posición durante 6 s.",
	Cooldown = 30,
	CastTime = 0,
	Range = SCREAM_RADIUS,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end

		for _, model in ipairs(workspace:GetChildren()) do
			if model:IsA("Model") and model ~= character and isValidToonflow(model) then
				local targetHrp = model:FindFirstChild("HumanoidRootPart")
				if targetHrp and (targetHrp.Position - hrp.Position).Magnitude <= SCREAM_RADIUS then
					-- 1. Lentitud I
					StatsModule.ApplySpeedMultiplier(model, "ShedScreamSlow", SCREAM_SLOW_MULTIPLIER, SCREAM_SLOW_SECONDS)

					-- 2. Cancelar tarea / reanimación en curso (antes solo se escribían atributos que nada leía)
					local player = Players:GetPlayerFromCharacter(model)
					if player then
						TaskManager.Interrupt(player, SCREAM_INTERRUPT_SECONDS)
					end

					-- 3. Revelar posición
					revealPosition(model)
				end
			end
		end

		-- Onda visual del grito
		local ring = Instance.new("Part")
		ring.Name = "ShedScreamWave"
		ring.Shape = Enum.PartType.Ball
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Material = Enum.Material.ForceField
		ring.Color = SHED_COLOR
		ring.Transparency = 0.4
		ring.Size = Vector3.one * 2
		ring.CFrame = CFrame.new(hrp.Position)
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * SCREAM_RADIUS * 2,
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.7)

		-- Grito de área: aunque no alcance a nadie (whiffing) se consume el cooldown
	end,
})

---------------------------------------------------------
-- HABILIDAD 3 (ULTIMATE): BIENVENIDA A PONYVILLE
---------------------------------------------------------
local function endBerserk(character, berserkId)
	if not character.Parent or character:GetAttribute("BerserkId") ~= berserkId then return end
	character:SetAttribute("BerserkActive", nil)
	character:SetAttribute("StunImmune", nil)
	character:SetAttribute("SlowImmune", nil)
	character:SetAttribute("AttackSpeedMultiplier", nil)
	StatsModule.RemoveSpeedMultiplier(character, "ShedBerserk")

	local aura = character:FindFirstChild("ShedBerserkAura")
	if aura then aura:Destroy() end
end

AbilityFramework.Register({
	Name = "BienvenidaAPonyville",
	Description = "Modo berserk de 15 s: +20% de velocidad de movimiento, +50% de velocidad de ataque e inmunidad total a aturdimientos y ralentizaciones.",
	Cooldown = 90,
	CastTime = 0,

	Execute = function(params)
		local character = params.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, "NoRootPart" end
		if character:GetAttribute("BerserkActive") then return false, "AlreadyActive" end

		-- Token: un berserk nuevo no se apaga con el temporizador de uno anterior
		local berserkId = (character:GetAttribute("BerserkId") or 0) + 1
		character:SetAttribute("BerserkId", berserkId)
		character:SetAttribute("BerserkActive", true)

		-- Inmunidades: StatsModule.SetState/Stun ignoran los aturdimientos, y SetSpeedMultiplier /
		-- ApplySpeedMultiplier rechazan las ralentizaciones, mientras estén activos estos atributos
		character:SetAttribute("StunImmune", true)
		character:SetAttribute("SlowImmune", true)
		StatsModule.ClearSlows(character) -- quita las ralentizaciones que ya tuviera encima

		-- +20% de velocidad (se combina con el +10% de la persecución) y +50% de velocidad de ataque
		-- (CombatServer divide el cooldown de ataque por AttackSpeedMultiplier)
		StatsModule.ApplySpeedMultiplier(character, "ShedBerserk", BERSERK_SPEED_MULTIPLIER, BERSERK_SECONDS)
		character:SetAttribute("AttackSpeedMultiplier", BERSERK_ATTACK_SPEED)

		local previousAura = character:FindFirstChild("ShedBerserkAura")
		if previousAura then previousAura:Destroy() end
		local aura = Instance.new("Highlight")
		aura.Name = "ShedBerserkAura"
		aura.FillColor = Color3.fromRGB(255, 40, 40)
		aura.OutlineColor = SHED_COLOR
		aura.FillTransparency = 0.6
		aura.OutlineTransparency = 0
		aura.Parent = character
		Debris:AddItem(aura, BERSERK_SECONDS)

		task.delay(BERSERK_SECONDS, function()
			endBerserk(character, berserkId)
		end)
	end,
})

return ShedMovAbilities
