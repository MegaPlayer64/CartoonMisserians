--[[
	MovementAndHUDController (LocalScript)
	Ubicación: StarterGui.GameGUI.HUDController (o StarterPlayerScripts)
	
	Maneja Stamina, Control de Sprint (Shift), Salto Dinámico, FOV y UI.
]]

local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local CharacterDatabase = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("CharacterDatabase"))

-- CONFIGURACIÓN DE MOVIMIENTO Y VELOCIDADES
local NORMAL_SPEED = 16
local SPRINT_SPEED = 22

local MAX_STAMINA = 100
local stamina = MAX_STAMINA
local jumpCost, runCost, regenRate = 10, 15, 10
local RECOVERY_THRESHOLD = 25

local JUMP_MIN_STAMINA = 25
local MIN_JUMP_POWER = 25 
local MAX_JUMP_POWER = 50 

-- CONFIGURACIÓN DE CÁMARA (FOV)
local NORMAL_FOV = 70
local RUN_FOV = 82
local FOV_LERP_SPEED = 8 

-- ESTADOS INTERNOS
local character = nil
local humanoid = nil
local lastHealth = 100
local isExhausted = false
local isSprintKeyPressed = false

-- REFERENCIAS A UI
local playerGui = player:WaitForChild("PlayerGui")
local gameGUI = playerGui:WaitForChild("GameGUI")
local HUD = gameGUI:WaitForChild("Character_GUI")

local staminFill = HUD:WaitForChild("StaminaIndicator")
local healthFill = HUD:WaitForChild("HealthIndicator")

local staminGradient = staminFill:WaitForChild("UIGradient")
local healthGradient = healthFill:WaitForChild("UIGradient")

-- ACTUALIZAR GRADIENTES DE FORMA SEGURA
local function updateBarGradient(gradient, percentage)
	percentage = math.clamp(percentage, 0, 1)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(math.clamp(percentage, 0, 0.999), 0),
		NumberSequenceKeypoint.new(math.clamp(percentage + 0.001, 0.001, 1), 1),
		NumberSequenceKeypoint.new(1, 1)
	})
end

-- CONTROLES DE ENTRADA (SHIFT / GAMEPAD)
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
		isSprintKeyPressed = true
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
		isSprintKeyPressed = false
	end
end)

-- SETUP DEL PERSONAJE
local function setupCharacter(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	humanoid.UseJumpPower = true
	lastHealth = humanoid.Health

	-- Obtener velocidad de sprint desde CharacterDatabase si está definida
	local charName = character:GetAttribute("CharacterName") or character.Name
	local charData = CharacterDatabase.Toonflows[charName] or CharacterDatabase.Devilishes[charName]
	if charData and charData.SprintSpeed then
		SPRINT_SPEED = charData.SprintSpeed
	else
		SPRINT_SPEED = 22
	end

	humanoid.HealthChanged:Connect(function(currentHealth)
		lastHealth = currentHealth
	end)

	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			if stamina >= jumpCost then
				stamina = stamina - jumpCost
			end
		end
	end)
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)

-- BUCLE ÚNICO DE RENDERIZADO
RunService.RenderStepped:Connect(function(dt)
	if not (character and humanoid and humanoid.Parent) then return end

	local camera = Workspace.CurrentCamera
	local isMoving = humanoid.MoveDirection.Magnitude > 0

	---------------------------------------------------------
	-- 1. LÓGICA DE STAMINA Y CONTROL DE SPEED
	---------------------------------------------------------
	if stamina <= 0 then 
		isExhausted = true
	elseif stamina >= RECOVERY_THRESHOLD then 
		isExhausted = false 
	end

	local wantsToSprint = isSprintKeyPressed and isMoving and not isExhausted and stamina > 0

	if wantsToSprint then
		humanoid.WalkSpeed = SPRINT_SPEED
		stamina = math.max(0, stamina - (runCost * dt))
	else
		humanoid.WalkSpeed = NORMAL_SPEED
		stamina = math.min(MAX_STAMINA, stamina + (regenRate * dt))
	end

	---------------------------------------------------------
	-- 2. LÓGICA DE SALTO DINÁMICO
	---------------------------------------------------------
	if stamina < JUMP_MIN_STAMINA or isExhausted then
		humanoid.JumpPower = 0
	else
		local staminaFactor = (stamina - JUMP_MIN_STAMINA) / (MAX_STAMINA - JUMP_MIN_STAMINA)
		humanoid.JumpPower = MIN_JUMP_POWER + (staminaFactor * (MAX_JUMP_POWER - MIN_JUMP_POWER))
	end

	---------------------------------------------------------
	-- 3. FOV DINÁMICO
	---------------------------------------------------------
	if camera then
		local targetFOV = wantsToSprint and RUN_FOV or NORMAL_FOV
		camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * math.min(dt * FOV_LERP_SPEED, 1)
	end

	---------------------------------------------------------
	-- 4. BARRAS Y GRADIENTES DE UI
	---------------------------------------------------------
	local healthPercent = humanoid.Health / humanoid.MaxHealth
	updateBarGradient(staminGradient, stamina / MAX_STAMINA)
	updateBarGradient(healthGradient, healthPercent)

	staminFill.ImageColor3 = isExhausted and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
	healthFill.ImageColor3 = (healthPercent <= 0.25) and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
end)