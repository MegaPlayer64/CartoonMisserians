--[[
	VFXModule (ModuleScript)
	Ubicacion: ReplicatedStorage.Framework.VFXModule

	Modulo de efectos visuales y sonoros de prueba (Placeholder VFX).
	No requiere assets externos: usa Instance.new(), Debris y sonidos genericos
	de Roblox Studio (rbxasset://sounds/...).

	Todas las funciones son safe-to-call: verifican que los argumentos existan
	antes de crear instancias y usan Debris para limpieza automatica.

	Funciones principales:
	  - SpawnSpeedBuffVFX(character, duration)   -> Highlight verde/amarillo
	  - SpawnHealVFX(character, duration)        -> Anillo esferico verde
	  - SpawnProjectileVFX(origin, endPoint)      -> Cilindro brillante (rayo)
	  - SpawnStunVFX(position, duration)           -> Destello amarillo + ColorCorrection
	  - PlaySound3D(parent, soundId, volume)       -> Sonido posicional temporal
	  - PlaySound2D(soundId, volume)               -> Sonido global via SoundService
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local VFXModule = {}

-- == SONIDOS DEL CREATOR STORE (rbxassetid://) ==
-- IDs validos y aprobados del Creator Store.
-- Reemplazan los rbxasset:// anteriores que causaban errores de aprobacion.
VFXModule.Sounds = {
	Buff       = "rbxassetid://124666497875357",  -- energy buzz (sci-fi)
	Heal       = "rbxassetid://1838772658",        -- Xanadu's Atmosphere (ambient heal)
	Projectile = "rbxassetid://118431566107728",   -- whirlwind swing (swoosh)
	Stun       = "rbxassetid://1843932197",        -- Moving Drone 106 (stun flash)
	MeleeHit   = "rbxassetid://96359585058783",   -- victim impact punch hit
	MeleeSwing = "rbxassetid://92333163118441",   -- first sinner slash 1 (sword swing)
	SoundWave  = "rbxassetid://1843932197",        -- distortion/megaphone (reuses Stun sound)
	Medkit     = "rbxassetid://1838772658",        -- heal deploy (reuses Heal sound)
	-- Neuro sounds
	Stardoom   = "rbxassetid://124666497875357",   -- hover/dash energy (reuses Buff)
	Plasma     = "rbxassetid://118431566107728",   -- plasma projectile (reuses Projectile)
	LastShow   = "rbxassetid://92333163118441",   -- charge/dash (reuses MeleeSwing)
	FameUp     = "rbxassetid://1838772658",        -- fame gain chime (reuses Heal)
	FameDown   = "rbxassetid://1843932197",        -- fame loss buzz (reuses Stun)
	-- Trunks sounds
	SwordSwing   = "rbxassetid://92333163118441",   -- Z Sword swing (reuses MeleeSwing)
	SwordHit     = "rbxassetid://96359585058783",   -- Z Sword impact (reuses MeleeHit)
	KiBlast      = "rbxassetid://118431566107728",   -- Ki Blast fire (reuses Projectile)
	KiHit        = "rbxassetid://96359585058783",   -- Ki Blast impact (reuses MeleeHit)
	SuperSaiyan  = "rbxassetid://124666497875357",   -- SSJ transformation (reuses Buff)
	SCellGain    = "rbxassetid://1838772658",        -- SCell gain chime (reuses Heal)
}

--[[
	Reproduce un sonido posicional 3D temporal en un parent.
	Debris se encarga de destruir el Sound despues de que termine.
]]
function VFXModule.PlaySound3D(parent, soundId, volume)
	if not parent or not soundId then return end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = parent
	sound:Play()

	-- Debris elimina el sonido 2 segundos despues de que termine
	Debris:AddItem(sound, 5)
end

--[[
	Reproduce un sonido 2D global via SoundService.
	Util para sonidos de UI o efectos que todos deben escuchar.
]]
function VFXModule.PlaySound2D(soundId, volume)
	if not soundId then return end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = SoundService
	sound:Play()

	Debris:AddItem(sound, 5)
end

--[[
	EFECTO A) Buff de Velocidad (ej. "Heredado de Mamá")
	Crea un Highlight con FillColor verde/amarillo en el personaje
	que dura toda la duracion del buff y se desvanece al final.
]]
function VFXModule.SpawnSpeedBuffVFX(character, duration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Crear Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "SpeedBuffVFX"
	highlight.FillColor = Color3.fromRGB(100, 255, 100)  -- Verde
	highlight.OutlineColor = Color3.fromRGB(255, 255, 0)  -- Amarillo
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Sonido de activacion del buff
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.6)

	-- Desvanecer el highlight antes de destruirlo
	local fadeDuration = 0.8
	local fadeStart = duration - fadeDuration

	task.delay(fadeStart, function()
		if highlight and highlight.Parent then
			local tween = TweenService:Create(highlight, TweenInfo.new(fadeDuration), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				highlight:Destroy()
			end)
		end
	end)

	-- Fallback: destruir por Debris si el tween no se ejecuta
	Debris:AddItem(highlight, duration + 1)
end

--[[
	EFECTO B) Curacion (ej. "Gamechild")
	Crea una esfera verde transparente alrededor del personaje que
	se expande y se desvanece suavemente.
]]
function VFXModule.SpawnHealVFX(character, duration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local position = hrp.Position

	-- Crear esfera principal
	local sphere = Instance.new("Part")
	sphere.Name = "HealVFX_Sphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(4, 4, 4)
	sphere.CFrame = CFrame.new(position)
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.Material = Enum.Material.ForceField
	sphere.Color = Color3.fromRGB(50, 255, 100)
	sphere.Transparency = 0.3
	sphere.Parent = workspace

	-- Crear SelectionBox como anillo decorativo
	local ring = Instance.new("SelectionBox")
	ring.Adornee = sphere
	ring.LineThickness = 0.15
	ring.Color3 = Color3.fromRGB(100, 255, 150)
	ring.SurfaceTransparency = 0.2
	ring.Parent = sphere

	-- Sonido de curacion
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Heal, 0.7)

	-- Tween: expandir y desvanecer
	local expandTween = TweenService:Create(sphere, TweenInfo.new(duration or 1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(12, 12, 12),
		Transparency = 1,
	})
	expandTween:Play()

	expandTween.Completed:Connect(function()
		sphere:Destroy()
	end)

	-- Fallback con Debris
	Debris:AddItem(sphere, (duration or 1.5) + 0.5)
end

--[[
	EFECTO C) Proyectil / Skillshot (ej. "Rayos Láser", "Ráfagas de Ki")
	Genera una Part cilindrica brillante desde el origen hasta el punto
	de impacto. Se desvanece rapidamente.
]]
function VFXModule.SpawnProjectileVFX(origin, endPoint, color)
	if not (origin and endPoint) then return end

	color = color or Color3.fromRGB(255, 50, 50)
	local distance = (origin - endPoint).Magnitude

	-- Cilindro principal del rayo
	local beam = Instance.new("Part")
	beam.Name = "ProjectileVFX_Beam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Transparency = 0.2
	beam.Size = Vector3.new(0.6, 0.6, distance)
	beam.CFrame = CFrame.lookAt(origin, endPoint) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = workspace

	-- SelectionBox para resaltar el contorno
	local sb = Instance.new("SelectionBox")
	sb.Adornee = beam
	sb.LineThickness = 0.1
	sb.Color3 = Color3.fromRGB(255, 255, 255)
	sb.SurfaceTransparency = 0.1
	sb.Parent = beam

	-- Sonido del proyectil
	VFXModule.PlaySound3D(beam, VFXModule.Sounds.Projectile, 0.5)

	-- Tween de desvanecimiento
	local fadeTween = TweenService:Create(beam, TweenInfo.new(0.3), {
		Transparency = 1,
		Size = Vector3.new(0.1, 0.1, distance),
	})
	fadeTween:Play()

	fadeTween.Completed:Connect(function()
		beam:Destroy()
	end)

	Debris:AddItem(beam, 1)
end

--[[
	EFECTO D) Stun / Ceguera (ej. "Taiyoken", "Barra Fantasma")
	Crea un destello brillante en el area de la habilidad:
	  - Cilindro conico amarillo que se expande rapidamente
	  - ColorCorrectionEffect temporal en Lighting para cegar
	Se destruye tras 0.5 segundos.
]]
function VFXModule.SpawnStunVFX(position, duration)
	if not position then return end
	duration = duration or 0.5

	-- Cilindro conico amarillo (explosion de luz)
	local flash = Instance.new("Part")
	flash.Name = "StunVFX_Flash"
	flash.Shape = Enum.PartType.Cylinder
	flash.Size = Vector3.new(2, 2, 2)
	flash.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 255, 50)  -- Amarillo brillante
	flash.Transparency = 0.1
	flash.Parent = workspace

	-- Sonido del stun
	VFXModule.PlaySound3D(flash, VFXModule.Sounds.Stun, 0.8)

	-- Tween: expandir rapidamente y desvanecer
	local expandTween = TweenService:Create(flash, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(30, 30, 30),
		Transparency = 1,
	})
	expandTween:Play()

	expandTween.Completed:Connect(function()
		flash:Destroy()
	end)

	Debris:AddItem(flash, duration + 0.5)

	-- ColorCorrectionEffect temporal en Lighting (efecto de ceguera)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "StunVFX_ColorCorrection"
	cc.Brightness = 0.8
	cc.Contrast = 0.5
	cc.Saturation = -0.3
	cc.TintColor = Color3.fromRGB(255, 255, 200)
	cc.Parent = game:GetService("Lighting")

	-- Desvanecer el ColorCorrection
	local ccTween = TweenService:Create(cc, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.fromRGB(255, 255, 255),
	})
	ccTween:Play()

	ccTween.Completed:Connect(function()
		cc:Destroy()
	end)

	Debris:AddItem(cc, duration + 0.5)
end

--[[
	EFECTO E) Rastro de Particulas (Trail) para buff de velocidad
	Crea un Trail con Attachment en el HumanoidRootPart que dura
	toda la duracion del buff y se limpia automaticamente.
]]
function VFXModule.SpawnTrailVFX(character, duration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Crear dos Attachments para el Trail
	local att0 = Instance.new("Attachment")
	att0.Name = "TrailAtt0"
	att0.Position = Vector3.new(-1, 1, 0)
	att0.Parent = hrp

	local att1 = Instance.new("Attachment")
	att1.Name = "TrailAtt1"
	att1.Position = Vector3.new(1, 1, 0)
	att1.Parent = hrp

	-- Crear Trail
	local trail = Instance.new("Trail")
	trail.Name = "SpeedTrailVFX"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 255, 100)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	trail.Parent = hrp

	-- Desvanecer el trail antes de destruirlo
	task.delay(duration - 0.5, function()
		if trail and trail.Parent then
			trail.Enabled = false
		end
	end)

	-- Limpieza
	Debris:AddItem(att0, duration + 1)
	Debris:AddItem(att1, duration + 1)
	Debris:AddItem(trail, duration + 1)
end

--[[
	EFECTO F) Aura / Cilindro de Curacion (Gamechild)
	Crea un cilindro verde brillante alrededor del personaje que
	se desvanece suavemente en la duracion especificada.
]]
function VFXModule.SpawnHealAuraVFX(character, duration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local position = hrp.Position

	-- Crear cilindro vertical (aura alrededor del personaje)
	local aura = Instance.new("Part")
	aura.Name = "HealAuraVFX"
	aura.Shape = Enum.PartType.Cylinder
	aura.Size = Vector3.new(6, 6, 6)
	aura.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.Material = Enum.Material.ForceField
	aura.Color = Color3.fromRGB(50, 255, 100)
	aura.Transparency = 0.3
	aura.Parent = workspace

	-- SelectionBox decorativa
	local ring = Instance.new("SelectionBox")
	ring.Adornee = aura
	ring.LineThickness = 0.15
	ring.Color3 = Color3.fromRGB(100, 255, 150)
	ring.SurfaceTransparency = 0.2
	ring.Parent = aura

	-- Sonido de curacion
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Heal, 0.7)

	-- Tween: expandir y desvanecer suavemente
	local fadeTween = TweenService:Create(aura, TweenInfo.new(duration or 1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(10, 10, 10),
		Transparency = 1,
	})
	fadeTween:Play()

	fadeTween.Completed:Connect(function()
		aura:Destroy()
	end)

	Debris:AddItem(aura, (duration or 1) + 0.5)
end

--[[
	EFECTO G) Aura de Amistacion (Pasiva de Toby)
	Crea un aura azul brillante alrededor del personaje que dura
	la duracion especificada, indicando que la pasiva se activo.
]]
function VFXModule.SpawnAmistacionVFX(character, duration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local position = hrp.Position

	-- Esfera azul brillante (aura de amistacion)
	local aura = Instance.new("Part")
	aura.Name = "AmistacionVFX"
	aura.Shape = Enum.PartType.Ball
	aura.Size = Vector3.new(4, 4, 4)
	aura.CFrame = CFrame.new(position)
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.Material = Enum.Material.ForceField
	aura.Color = Color3.fromRGB(100, 150, 255)
	aura.Transparency = 0.3
	aura.Parent = workspace

	-- Highlight azul temporal en el personaje
	local highlight = Instance.new("Highlight")
	highlight.Name = "AmistacionHighlight"
	highlight.FillColor = Color3.fromRGB(100, 150, 255)
	highlight.OutlineColor = Color3.fromRGB(200, 220, 255)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Sonido de recompensa (usamos Heal como placeholder de recompensa)
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Heal, 0.8)

	-- Tween: expandir y desvanecer el aura
	local fadeTween = TweenService:Create(aura, TweenInfo.new(duration or 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(10, 10, 10),
		Transparency = 1,
	})
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		aura:Destroy()
	end)

	-- Desvanecer el highlight
	task.delay((duration or 2) - 0.5, function()
		if highlight and highlight.Parent then
			local hlTween = TweenService:Create(highlight, TweenInfo.new(0.5), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			})
			hlTween:Play()
			hlTween.Completed:Connect(function()
				highlight:Destroy()
			end)
		end
	end)

	Debris:AddItem(aura, (duration or 2) + 0.5)
	Debris:AddItem(highlight, (duration or 2) + 1)
end

--[[
	EFECTO H) Swing de Melee (Bara Normal / Bara Fantasma)
	Crea un arco visual temporal desde el origen hasta el punto de impacto
	que representa el movimiento del palo.
]]
function VFXModule.SpawnMeleeSwingVFX(origin, endPoint, color)
	if not (origin and endPoint) then return end

	color = color or Color3.fromRGB(100, 200, 255)
	local distance = (origin - endPoint).Magnitude

	-- Cilindro delgado temporal que representa el swing
	local swing = Instance.new("Part")
	swing.Name = "MeleeSwingVFX"
	swing.Anchored = true
	swing.CanCollide = false
	swing.CanQuery = false
	swing.Material = Enum.Material.Neon
	swing.Color = color
	swing.Transparency = 0.3
	swing.Size = Vector3.new(1.5, 1.5, distance)
	swing.CFrame = CFrame.lookAt(origin, endPoint) * CFrame.new(0, 0, -distance / 2)
	swing.Parent = workspace

	-- Sonido del swing
	VFXModule.PlaySound3D(swing, VFXModule.Sounds.MeleeSwing, 0.5)

	-- Tween de desvanecimiento rapido
	local fadeTween = TweenService:Create(swing, TweenInfo.new(0.2), {
		Transparency = 1,
		Size = Vector3.new(0.3, 0.3, distance),
	})
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		swing:Destroy()
	end)

	Debris:AddItem(swing, 0.5)
end

--[[
	EFECTO I) Impacto de Melee (Bara Normal / Bara Fantasma)
	Crea un destello en el punto de impacto para indicar que el golpe conecto.
]]
function VFXModule.SpawnMeleeHitVFX(position, color)
	if not position then return end

	color = color or Color3.fromRGB(100, 200, 255)

	-- Esfera pequena de impacto
	local impact = Instance.new("Part")
	impact.Name = "MeleeHitVFX"
	impact.Shape = Enum.PartType.Ball
	impact.Size = Vector3.new(2, 2, 2)
	impact.CFrame = CFrame.new(position)
	impact.Anchored = true
	impact.CanCollide = false
	impact.CanQuery = false
	impact.Material = Enum.Material.Neon
	impact.Color = color
	impact.Transparency = 0.1
	impact.Parent = workspace

	-- Sonido de impacto
	VFXModule.PlaySound3D(impact, VFXModule.Sounds.MeleeHit, 0.6)

	-- Tween: expandir y desvanecer rapidamente
	local fadeTween = TweenService:Create(impact, TweenInfo.new(0.3), {
		Size = Vector3.new(5, 5, 5),
		Transparency = 1,
	})
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		impact:Destroy()
	end)

	Debris:AddItem(impact, 0.5)
end

--[[
	EFECTO J) Canalizacion (Rayos Laser de Toby)
	Crea un aura de carga alrededor del personaje durante la canalizacion.
	Indica visualmente que el personaje esta cargando un ataque.
]]
function VFXModule.SpawnChannelVFX(character, duration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Highlight pulsante durante la carga
	local highlight = Instance.new("Highlight")
	highlight.Name = "ChannelVFX"
	highlight.FillColor = Color3.fromRGB(50, 100, 255)
	highlight.OutlineColor = Color3.fromRGB(255, 50, 50)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Anillo de carga en el suelo
	local ring = Instance.new("Part")
	ring.Name = "ChannelRingVFX"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(8, 8, 0.2)
	ring.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(50, 100, 255)
	ring.Transparency = 0.5
	ring.Parent = workspace

	-- Sonido de carga (buzz energetico)
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.5)

	-- Tween: el anillo se contrae hacia el personaje (cargando energia)
	local chargeTween = TweenService:Create(ring, TweenInfo.new(duration or 3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = Vector3.new(2, 2, 0.2),
		Transparency = 0.1,
	})
	chargeTween:Play()

	chargeTween.Completed:Connect(function()
		-- Flash final al completar la carga
		local flash = Instance.new("Part")
		flash.Name = "ChannelFlashVFX"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(3, 3, 3)
		flash.CFrame = CFrame.new(hrp.Position)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 255, 255)
		flash.Transparency = 0
		flash.Parent = workspace

		local flashTween = TweenService:Create(flash, TweenInfo.new(0.3), {
			Size = Vector3.new(8, 8, 8),
			Transparency = 1,
		})
		flashTween:Play()
		flashTween.Completed:Connect(function()
			flash:Destroy()
		end)

		Debris:AddItem(flash, 0.5)
		ring:Destroy()
		highlight:Destroy()
	end)

	Debris:AddItem(ring, (duration or 3) + 0.5)
	Debris:AddItem(highlight, (duration or 3) + 0.5)
end

--[[
	EFECTO K) Pulso de Curacion (EmergenciaSevera de Takorita)
	Crea un anillo verde + cruz brillante sobre el objetivo que dura
	la duracion especificada, indicando la curacion canalizada.
]]
function VFXModule.SpawnHealPulseVFX(targetCharacter, duration)
	if not targetCharacter then return end

	local hrp = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local position = hrp.Position
	duration = duration or 1.5

	-- Anillo verde en el suelo bajo el objetivo
	local ring = Instance.new("Part")
	ring.Name = "HealPulseVFX_Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(6, 6, 0.2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(50, 255, 100)
	ring.Transparency = 0.3
	ring.Parent = workspace

	-- Cruz verde brillante sobre el objetivo (Part vertical)
	local crossV = Instance.new("Part")
	crossV.Name = "HealPulseVFX_CrossV"
	crossV.Size = Vector3.new(0.3, 4, 0.3)
	crossV.CFrame = CFrame.new(position + Vector3.new(0, 5, 0))
	crossV.Anchored = true
	crossV.CanCollide = false
	crossV.CanQuery = false
	crossV.Material = Enum.Material.Neon
	crossV.Color = Color3.fromRGB(100, 255, 150)
	crossV.Transparency = 0.1
	crossV.Parent = workspace

	local crossH = Instance.new("Part")
	crossH.Name = "HealPulseVFX_CrossH"
	crossH.Size = Vector3.new(4, 0.3, 0.3)
	crossH.CFrame = CFrame.new(position + Vector3.new(0, 5, 0))
	crossH.Anchored = true
	crossH.CanCollide = false
	crossH.CanQuery = false
	crossH.Material = Enum.Material.Neon
	crossH.Color = Color3.fromRGB(100, 255, 150)
	crossH.Transparency = 0.1
	crossH.Parent = workspace

	-- Highlight verde temporal en el objetivo
	local highlight = Instance.new("Highlight")
	highlight.Name = "HealPulseVFX_Highlight"
	highlight.FillColor = Color3.fromRGB(50, 255, 100)
	highlight.OutlineColor = Color3.fromRGB(150, 255, 200)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = targetCharacter

	-- Sonido de curacion
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Heal, 0.6)

	-- Tween: el anillo pulsa (se expande y contrae)
	local pulseTween = TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Size = Vector3.new(10, 10, 0.2),
		Transparency = 0.8,
	})
	pulseTween:Play()

	-- Desvanecer la cruz y el highlight
	task.delay(duration - 0.5, function()
		if crossV and crossV.Parent then
			TweenService:Create(crossV, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		if crossH and crossH.Parent then
			TweenService:Create(crossH, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		if highlight and highlight.Parent then
			TweenService:Create(highlight, TweenInfo.new(0.5), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			}):Play()
		end
	end)

	pulseTween.Completed:Connect(function()
		ring:Destroy()
		crossV:Destroy()
		crossH:Destroy()
		highlight:Destroy()
	end)

	Debris:AddItem(ring, duration + 0.5)
	Debris:AddItem(crossV, duration + 0.5)
	Debris:AddItem(crossH, duration + 0.5)
	Debris:AddItem(highlight, duration + 1)
end

--[[
	EFECTO L) Botiquin en Suelo (CuracionAumentante de Takorita)
	Crea un modelo de botiquin (Part roja/blanca) + cilindro verde transparente
	que marca el radio de curacion. Retorna el modelo para que el llamador
	pueda gestionar su ciclo de vida.
]]
function VFXModule.SpawnMedkitVFX(position, radius, duration)
	radius = radius or 15
	duration = duration or 50

	-- Modelo contenedor
	local medkitModel = Instance.new("Model")
	medkitModel.Name = "CuracionAumentante_Medkit"
	medkitModel.Parent = workspace

	-- Caja del botiquin (Part roja con cruz blanca)
	local box = Instance.new("Part")
	box.Name = "MedkitBox"
	box.Size = Vector3.new(2, 1.5, 1.5)
	box.CFrame = CFrame.new(position + Vector3.new(0, 0.75, 0))
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.Material = Enum.Material.SmoothPlastic
	box.Color = Color3.fromRGB(255, 100, 100)  -- Rojo
	box.Transparency = 0
	box.Parent = medkitModel

	-- Cruz blanca en la caja (Part delgada)
	local crossPart = Instance.new("Part")
	crossPart.Name = "MedkitCross"
	crossPart.Size = Vector3.new(1.2, 0.1, 1.2)
	crossPart.CFrame = CFrame.new(position + Vector3.new(0, 1.55, 0))
	crossPart.Anchored = true
	crossPart.CanCollide = false
	crossPart.CanQuery = false
	crossPart.Material = Enum.Material.SmoothPlastic
	crossPart.Color = Color3.fromRGB(255, 255, 255)  -- Blanco
	crossPart.Transparency = 0
	crossPart.Parent = medkitModel

	-- Cilindro verde transparente que marca el radio de curacion
	local healArea = Instance.new("Part")
	healArea.Name = "HealPulseVFX"
	healArea.Shape = Enum.PartType.Cylinder
	-- El cilindro se acuesta: Size = (diameter, diameter, height)
	local diameter = radius * 2
	healArea.Size = Vector3.new(diameter, diameter, 0.2)
	healArea.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	healArea.Anchored = true
	healArea.CanCollide = false
	healArea.CanQuery = false
	healArea.Material = Enum.Material.ForceField
	healArea.Color = Color3.fromRGB(50, 255, 100)
	healArea.Transparency = 0.6
	healArea.Parent = medkitModel

	-- SelectionBox decorativa en el cilindro
	local ring = Instance.new("SelectionBox")
	ring.Adornee = healArea
	ring.LineThickness = 0.1
	ring.Color3 = Color3.fromRGB(100, 255, 150)
	ring.SurfaceTransparency = 0.3
	ring.Parent = healArea

	-- Sonido de despliegue
	VFXModule.PlaySound3D(box, VFXModule.Sounds.Medkit, 0.5)

	-- Auto-destruccion por Debris como fallback
	Debris:AddItem(medkitModel, duration + 2)

	return medkitModel
end

--[[
	EFECTO M) Onda Sonora Expansiva (AnnouncerAttack de Takorita)
	Crea una esfera semitransparente que se expande rapidamente desde
	Takorita hacia el radio especificado, simulando un estruendo sonoro.
	Incluye sonido de distorsion/megafono.
]]
function VFXModule.SpawnSoundWaveVFX(character, radius, duration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	radius = radius or 25
	duration = duration or 1.0
	local position = hrp.Position

	-- Esfera semitransparente que se expande
	local wave = Instance.new("Part")
	wave.Name = "SoundWaveVFX"
	wave.Shape = Enum.PartType.Ball
	wave.Size = Vector3.new(2, 2, 2)
	wave.CFrame = CFrame.new(position)
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.Material = Enum.Material.ForceField
	wave.Color = Color3.fromRGB(255, 220, 100)  -- Amarillo/sonoro
	wave.Transparency = 0.2
	wave.Parent = workspace

	-- SelectionBox para resaltar el contorno de la onda
	local ring = Instance.new("SelectionBox")
	ring.Adornee = wave
	ring.LineThickness = 0.15
	ring.Color3 = Color3.fromRGB(255, 255, 200)
	ring.SurfaceTransparency = 0.1
	ring.Parent = wave

	-- Highlight temporal en Takorita (efecto de megafono)
	local highlight = Instance.new("Highlight")
	highlight.Name = "SoundWaveHighlight"
	highlight.FillColor = Color3.fromRGB(255, 220, 100)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 200)
	highlight.FillTransparency = 0.4
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Sonido de distorsion/megafono
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.SoundWave, 0.8)

	-- Tween: expandir la esfera al radio objetivo y desvanecer
	local targetSize = radius * 2
	local expandTween = TweenService:Create(wave, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(targetSize, targetSize, targetSize),
		Transparency = 1,
	})
	expandTween:Play()

	expandTween.Completed:Connect(function()
		wave:Destroy()
		highlight:Destroy()
	end)

	-- Desvanecer el highlight antes de terminar
	task.delay(duration - 0.3, function()
		if highlight and highlight.Parent then
			TweenService:Create(highlight, TweenInfo.new(0.3), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			}):Play()
		end
	end)

	Debris:AddItem(wave, duration + 0.5)
	Debris:AddItem(highlight, duration + 1)
end

--[[
	EFECTO N) Hover + Reveal + Dash (CallOfStardoom de Neuro)
	Crea un highlight violeta en Neuro durante el hover, revela siluetas
	de Toonflows cercanos con highlights blancos, y un trail de dash.
	duration = tiempo total del efecto (hover + reveal + dash)
]]
function VFXModule.SpawnStardoomVFX(character, revealDuration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	revealDuration = revealDuration or 2

	-- Highlight violeta en Neuro durante el hover
	local highlight = Instance.new("Highlight")
	highlight.Name = "StardoomVFX"
	highlight.FillColor = Color3.fromRGB(180, 100, 255)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Anillo de energia en el suelo bajo Neuro
	local ring = Instance.new("Part")
	ring.Name = "StardoomRingVFX"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(6, 6, 0.2)
	ring.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(180, 100, 255)
	ring.Transparency = 0.3
	ring.Parent = workspace

	-- Sonido de hover
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Stardoom, 0.6)

	-- Tween: el anillo pulsa
	local pulseTween = TweenService:Create(ring, TweenInfo.new(revealDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Size = Vector3.new(10, 10, 0.2),
		Transparency = 0.8,
	})
	pulseTween:Play()

	pulseTween.Completed:Connect(function()
		ring:Destroy()
	end)

	-- Desvanecer highlight despues del reveal
	task.delay(revealDuration, function()
		if highlight and highlight.Parent then
			local hlTween = TweenService:Create(highlight, TweenInfo.new(0.5), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			})
			hlTween:Play()
			hlTween.Completed:Connect(function()
				highlight:Destroy()
			end)
		end
	end)

	Debris:AddItem(ring, revealDuration + 0.5)
	Debris:AddItem(highlight, revealDuration + 1)
end

--[[
	EFECTO O) Revelar Toonflow (silueta blanca)
	Crea un highlight blanco temporal en un Toonflow cercano para indicar
	que ha sido revelado por CallOfStardoom.
]]
function VFXModule.SpawnRevealVFX(targetCharacter, duration)
	if not targetCharacter then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "RevealVFX"
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineColor = Color3.fromRGB(200, 150, 255)
	highlight.FillTransparency = 0.4
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = targetCharacter

	task.delay(duration or 2, function()
		if highlight and highlight.Parent then
			local tween = TweenService:Create(highlight, TweenInfo.new(0.5), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				highlight:Destroy()
			end)
		end
	end)

	Debris:AddItem(highlight, (duration or 2) + 1)
end

--[[
	EFECTO P) Proyectil de Plasma (LightsAndAction de Neuro)
	Crea un proyectil esferico violeta/blanco que viaja desde el origen
	hasta el punto objetivo. Mas brillante y duradero que SpawnProjectileVFX.
]]
function VFXModule.SpawnPlasmaProjectileVFX(origin, endPoint)
	if not (origin and endPoint) then return end

	local distance = (origin - endPoint).Magnitude

	-- Esfera de plasma violeta/blanca
	local plasma = Instance.new("Part")
	plasma.Name = "PlasmaProjectileVFX"
	plasma.Shape = Enum.PartType.Ball
	plasma.Size = Vector3.new(2, 2, 2)
	plasma.CFrame = CFrame.new(origin)
	plasma.Anchored = true
	plasma.CanCollide = false
	plasma.CanQuery = false
	plasma.Material = Enum.Material.Neon
	plasma.Color = Color3.fromRGB(200, 150, 255)
	plasma.Transparency = 0.1
	plasma.Parent = workspace

	-- SelectionBox brillante
	local sb = Instance.new("SelectionBox")
	sb.Adornee = plasma
	sb.LineThickness = 0.15
	sb.Color3 = Color3.fromRGB(255, 255, 255)
	sb.SurfaceTransparency = 0.1
	sb.Parent = plasma

	-- Sonido del proyectil de plasma
	VFXModule.PlaySound3D(plasma, VFXModule.Sounds.Plasma, 0.6)

	-- Tween: viajar hacia el objetivo
	local travelTime = math.min(distance / 80, 0.5)
	local travelTween = TweenService:Create(plasma, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(endPoint),
	})
	travelTween:Play()

	travelTween.Completed:Connect(function()
		-- Explosion al impactar
		local flash = Instance.new("Part")
		flash.Name = "PlasmaImpactVFX"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(3, 3, 3)
		flash.CFrame = CFrame.new(endPoint)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 255, 255)
		flash.Transparency = 0
		flash.Parent = workspace

		local flashTween = TweenService:Create(flash, TweenInfo.new(0.4), {
			Size = Vector3.new(10, 10, 10),
			Transparency = 1,
		})
		flashTween:Play()
		flashTween.Completed:Connect(function()
			flash:Destroy()
		end)

		Debris:AddItem(flash, 0.5)
		plasma:Destroy()
	end)

	Debris:AddItem(plasma, 1)
end

--[[
	EFECTO Q) Carga + Dash arrastrando (LastShow de Neuro)
	Crea un aura de carga violeta/blanca en Neuro durante la carga,
	seguida de un trail de dash. Si impacta una pared, flash de impacto.
]]
function VFXModule.SpawnLastShowVFX(character, chargeDuration)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	chargeDuration = chargeDuration or 1.5

	-- Highlight de carga violeta intenso
	local highlight = Instance.new("Highlight")
	highlight.Name = "LastShowChargeVFX"
	highlight.FillColor = Color3.fromRGB(200, 100, 255)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Anillo de carga en el suelo
	local ring = Instance.new("Part")
	ring.Name = "LastShowRingVFX"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(8, 8, 0.2)
	ring.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(200, 100, 255)
	ring.Transparency = 0.3
	ring.Parent = workspace

	-- Sonido de carga
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.LastShow, 0.7)

	-- Tween: el anillo se contrae (cargando energia)
	local chargeTween = TweenService:Create(ring, TweenInfo.new(chargeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = Vector3.new(2, 2, 0.2),
		Transparency = 0.1,
	})
	chargeTween:Play()

	chargeTween.Completed:Connect(function()
		-- Flash final al completar la carga
		local flash = Instance.new("Part")
		flash.Name = "LastShowFlashVFX"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(4, 4, 4)
		flash.CFrame = CFrame.new(hrp.Position)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 255, 255)
		flash.Transparency = 0
		flash.Parent = workspace

		local flashTween = TweenService:Create(flash, TweenInfo.new(0.3), {
			Size = Vector3.new(10, 10, 10),
			Transparency = 1,
		})
		flashTween:Play()
		flashTween.Completed:Connect(function()
			flash:Destroy()
		end)

		Debris:AddItem(flash, 0.5)
		ring:Destroy()
		highlight:Destroy()
	end)

	Debris:AddItem(ring, chargeDuration + 0.5)
	Debris:AddItem(highlight, chargeDuration + 0.5)
end

--[[
	EFECTO R) Aura de Fame (pasiva de Neuro)
	Crea un highlight violeta pulsante en Neuro que indica que Fame >= 45
	y el buff de velocidad esta activo.
]]
function VFXModule.SpawnFameAuraVFX(character)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "FameAuraVFX"
	highlight.FillColor = Color3.fromRGB(200, 150, 255)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Sonido de fame up
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.FameUp, 0.4)

	return highlight
end

--[[
	EFECTO S) Swing de Espada Z (Trunks)
	Crea un arco brillante amarillo/azul desde Trunks hacia el punto de impacto.
	Usa un cilindro delgado temporal con sonido de espada.
]]
function VFXModule.SpawnSwordSwingVFX(origin, endPoint)
	if not (origin and endPoint) then return end

	local distance = (origin - endPoint).Magnitude

	-- Cilindro delgado del swing (amarillo/azul)
	local swing = Instance.new("Part")
	swing.Name = "SwordSwingVFX"
	swing.Anchored = true
	swing.CanCollide = false
	swing.CanQuery = false
	swing.Material = Enum.Material.Neon
	swing.Color = Color3.fromRGB(255, 215, 0)  -- Amarillo dorado
	swing.Transparency = 0.2
	swing.Size = Vector3.new(2, 2, distance)
	swing.CFrame = CFrame.lookAt(origin, endPoint) * CFrame.new(0, 0, -distance / 2)
	swing.Parent = workspace

	-- SelectionBox para el contorno
	local sb = Instance.new("SelectionBox")
	sb.Adornee = swing
	sb.LineThickness = 0.15
	sb.Color3 = Color3.fromRGB(100, 150, 255)  -- Azul
	sb.SurfaceTransparency = 0.1
	sb.Parent = swing

	-- Sonido del swing de espada
	VFXModule.PlaySound3D(swing, VFXModule.Sounds.SwordSwing, 0.6)

	-- Tween de desvanecimiento
	local fadeTween = TweenService:Create(swing, TweenInfo.new(0.3), {
		Transparency = 1,
		Size = Vector3.new(0.3, 0.3, distance),
	})
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		swing:Destroy()
	end)

	Debris:AddItem(swing, 0.6)
end

--[[
	EFECTO T) Proyectil de Ki Blast (Trunks)
	Crea una esfera de energia amarilla/azul que viaja desde el origen
	hasta el punto objetivo. Mas pequena y rapida que el plasma de Neuro.
]]
function VFXModule.SpawnKiBlastVFX(origin, endPoint)
	if not (origin and endPoint) then return end

	local distance = (origin - endPoint).Magnitude

	-- Esfera de ki amarilla/azul
	local ki = Instance.new("Part")
	ki.Name = "KiBlastVFX"
	ki.Shape = Enum.PartType.Ball
	ki.Size = Vector3.new(1.5, 1.5, 1.5)
	ki.CFrame = CFrame.new(origin)
	ki.Anchored = true
	ki.CanCollide = false
	ki.CanQuery = false
	ki.Material = Enum.Material.Neon
	ki.Color = Color3.fromRGB(255, 215, 0)  -- Amarillo dorado
	ki.Transparency = 0.1
	ki.Parent = workspace

	-- SelectionBox brillante
	local sb = Instance.new("SelectionBox")
	sb.Adornee = ki
	sb.LineThickness = 0.1
	sb.Color3 = Color3.fromRGB(100, 150, 255)  -- Azul
	sb.SurfaceTransparency = 0.1
	sb.Parent = ki

	-- Sonido del ki blast
	VFXModule.PlaySound3D(ki, VFXModule.Sounds.KiBlast, 0.5)

	-- Tween: viajar hacia el objetivo
	local travelTime = math.min(distance / 100, 0.4)
	local travelTween = TweenService:Create(ki, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(endPoint),
	})
	travelTween:Play()

	travelTween.Completed:Connect(function()
		-- Explosion al impactar
		local flash = Instance.new("Part")
		flash.Name = "KiBlastImpactVFX"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(2, 2, 2)
		flash.CFrame = CFrame.new(endPoint)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 255, 200)
		flash.Transparency = 0
		flash.Parent = workspace

		VFXModule.PlaySound3D(flash, VFXModule.Sounds.KiHit, 0.5)

		local flashTween = TweenService:Create(flash, TweenInfo.new(0.3), {
			Size = Vector3.new(6, 6, 6),
			Transparency = 1,
		})
		flashTween:Play()
		flashTween.Completed:Connect(function()
			flash:Destroy()
		end)

		Debris:AddItem(flash, 0.5)
		ki:Destroy()
	end)

	Debris:AddItem(ki, 1)
end

--[[
	EFECTO U) Aura de Super Saiyan (Trunks)
	Crea un aura amarilla dorada con particulas alrededor del personaje.
	Retorna el modelo de VFX para que el llamador pueda gestionar su ciclo de vida.
]]
function VFXModule.SpawnSuperSaiyanVFX(character)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Highlight dorado intenso
	local highlight = Instance.new("Highlight")
	highlight.Name = "SuperSaiyanVFX"
	highlight.FillColor = Color3.fromRGB(255, 215, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 200)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	-- Aura de cilindro dorado alrededor del personaje
	local aura = Instance.new("Part")
	aura.Name = "SSJAuraVFX"
	aura.Shape = Enum.PartType.Cylinder
	aura.Size = Vector3.new(5, 5, 5)
	aura.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, 0, math.rad(90))
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.Material = Enum.Material.ForceField
	aura.Color = Color3.fromRGB(255, 215, 0)
	aura.Transparency = 0.4
	aura.Parent = workspace

	-- Sonido de transformacion
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.SuperSaiyan, 0.8)

	-- Tween: pulso del aura (expandir y contraer suavemente)
	local pulseTween = TweenService:Create(aura, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Size = Vector3.new(7, 7, 7),
		Transparency = 0.6,
	})
	pulseTween:Play()

	-- Retornar VFX para gestion manual
	return {
		Highlight = highlight,
		Aura = aura,
		PulseTween = pulseTween,
		Destroy = function(self)
			if self.Highlight and self.Highlight.Parent then
				self.Highlight:Destroy()
			end
			if self.Aura and self.Aura.Parent then
				self.Aura:Destroy()
			end
		end,
	}
end

--[[
	EFECTO V) Ganancia de SCells (Trunks pasiva)
	Crea un pequeno destello amarillo alrededor del personaje indicando
	que ha ganado Células S.
]]
function VFXModule.SpawnSCellGainVFX(character)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Esfera amarilla pequena y rapida
	local spark = Instance.new("Part")
	spark.Name = "SCellGainVFX"
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.new(2, 2, 2)
	spark.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 2, 0))
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.Material = Enum.Material.Neon
	spark.Color = Color3.fromRGB(255, 215, 0)
	spark.Transparency = 0.2
	spark.Parent = workspace

	-- Sonido de gain
	VFXModule.PlaySound3D(hrp, VFXModule.Sounds.SCellGain, 0.3)

	-- Tween: expandir y desvanecer rapido
	local fadeTween = TweenService:Create(spark, TweenInfo.new(0.4), {
		Size = Vector3.new(5, 5, 5),
		Transparency = 1,
	})
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		spark:Destroy()
	end)

	Debris:AddItem(spark, 0.6)
end

return VFXModule