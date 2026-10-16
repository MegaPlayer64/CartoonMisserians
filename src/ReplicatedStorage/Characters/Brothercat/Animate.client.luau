--[[
	Brothercat Animate Script (Optimizado)
	Carga KeyframeSequences desde ReplicatedStorage.BrothercatAnims
	Maneja animaciones de esqueleto Mixamo a través de Animator
]]

local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid")
local Animator = Humanoid:FindFirstChildOfClass("Animator")
if not Animator then
	Animator = Instance.new("Animator")
	Animator.Parent = Humanoid
end

-- Desactivar/Eliminar el script Animate nativo si existe para evitar conflictos
local defaultAnimate = Character:FindFirstChild("Animate")
if defaultAnimate and defaultAnimate ~= script then
	defaultAnimate:Destroy()
end

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Esperar a que la carpeta principal de animaciones exista en el cliente
local brothercatFolder = ReplicatedStorage:WaitForChild("BrothercatAnims", 10)

-- Estado de animación
local currentAnim = ""
local currentAnimTrack = nil
local currentAnimSpeed = 1.0
local pose = "Standing"

-- Cargar KeyframeSequences y convertirlos en objetos Animation
local function loadAnimationsFromFolder(folderName)
	if not brothercatFolder then return {} end
	local typeFolder = brothercatFolder:FindFirstChild(folderName)
	if not typeFolder then return {} end

	local animations = {}
	for _, ks in ipairs(typeFolder:GetChildren()) do
		if ks:IsA("KeyframeSequence") then
			local success, animId = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(ks)
			end)

			if success and animId then
				local anim = Instance.new("Animation")
				anim.AnimationId = animId
				anim.Name = folderName
				table.insert(animations, anim)
			end
		end
	end
	return animations
end

-- Cargar todos los tipos
local animSets = {
	idle = loadAnimationsFromFolder("idle"),
	walk = loadAnimationsFromFolder("walk"),
	run = loadAnimationsFromFolder("run"),
	jump = loadAnimationsFromFolder("jump"),
}

-- Reutilizar salto para caída si no existe carpeta propia
animSets.fall = (#loadAnimationsFromFolder("fall") > 0) and loadAnimationsFromFolder("fall") or animSets.jump

-- Precargar Tracks en el Animator
local tracks = {
	idle = {},
	walk = {},
	run = {},
	jump = {},
	fall = {},
}

for animType, anims in pairs(animSets) do
	for _, anim in ipairs(anims) do
		local track = Animator:LoadAnimation(anim)
		-- Prioridad ajustada a Movement/Action para sobreescribir la postura base
		track.Priority = (animType == "idle") and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Action
		track.Looped = true
		table.insert(tracks[animType], track)
	end
end

-- Validar si se cargaron animaciones
local totalAnims = 0
for _, trackList in pairs(tracks) do
	totalAnims = totalAnims + #trackList
end

if totalAnims == 0 then
	warn("[Brothercat Animate] ⚠️ No se encontraron animaciones en ReplicatedStorage.BrothercatAnims!")
end

-- Configurar salto y caída sin bucle
for _, track in ipairs(tracks.jump) do track.Looped = false end
for _, track in ipairs(tracks.fall) do track.Looped = false end

local trackIndex = { idle = 1, walk = 1, run = 1, jump = 1, fall = 1 }

local function pickTrack(animType)
	local trackList = tracks[animType]
	if not trackList or #trackList == 0 then return nil end
	local idx = trackIndex[animType]
	trackIndex[animType] = (idx % #trackList) + 1
	return trackList[idx]
end

local function playAnimation(animType, transitionTime)
	local newTrack = pickTrack(animType)
	if not newTrack or currentAnimTrack == newTrack then return end

	if currentAnimTrack then
		currentAnimTrack:Stop(transitionTime or 0.2)
	end

	currentAnimTrack = newTrack
	currentAnim = animType
	currentAnimSpeed = 1.0
	newTrack:Play(transitionTime or 0.2)
end

local function setAnimationSpeed(speed)
	if speed ~= currentAnimSpeed then
		currentAnimSpeed = speed
		if currentAnimTrack then
			currentAnimTrack:AdjustSpeed(currentAnimSpeed)
		end
	end
end

-- Handlers de estado
local function onRunning(speed)
	if speed > 1 then
		local scale = 5.0
		if speed > 20 then
			playAnimation("run", 0.15)
			scale = 10.0
		else
			playAnimation("walk", 0.15)
		end
		setAnimationSpeed(speed / scale)
		pose = "Running"
	else
		playAnimation("idle", 0.25)
		pose = "Standing"
	end
end

local function onDied()
	pose = "Dead"
	if currentAnimTrack then
		currentAnimTrack:Stop()
	end
end

local function onJumping()
	playAnimation("jump", 0.1)
	pose = "Jumping"
end

local function onClimbing(speed)
	playAnimation("walk", 0.1)
	setAnimationSpeed(speed / 5.0)
	pose = "Climbing"
end

local function onFreeFall()
	playAnimation("fall", 0.15)
	pose = "FreeFall"
end

local function onSeated()
	pose = "Seated"
	if currentAnimTrack then
		currentAnimTrack:Stop(0.3)
	end
end

-- Conexión de eventos
Humanoid.Died:Connect(onDied)
Humanoid.Running:Connect(onRunning)
Humanoid.Jumping:Connect(onJumping)
Humanoid.Climbing:Connect(onClimbing)
Humanoid.FreeFalling:Connect(onFreeFall)
Humanoid.Seated:Connect(onSeated)

-- Inicialización
if Character.Parent ~= nil then
	playAnimation("idle", 0.1)
	pose = "Standing"
end