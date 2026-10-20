--[[
	EmoteWheelHUD (LocalScript)
	StarterGui.GameGUI.EmoteWheelHUD

	Rueda radial in-game para usar emotes.
	Teclas 'C' o 'G' en PC | Botón de Emote / Fondo / Botón 'X' en Móvil.
	6 slots distribuidos radialmente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gameGUI = script.Parent

local CosmeticsDatabase = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("CosmeticsDatabase"))
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local UseEmoteRemote = Remotes:WaitForChild("UseEmote")

-- == CONFIGURACIÓN ==
local EMOTE_COOLDOWN = 7
local WHEEL_RADIUS = 120 -- píxeles desde el centro
local SLOT_SIZE = 64

-- == ESTADO ==
local wheelOpen = false
local lastEmoteTime = 0
local equippedEmotes = { "", "", "", "", "", "" }

-- Declaraciones adelantadas de funciones
local openWheel, closeWheel, useEmote

-- == CREACIÓN DE UI ==

local wheelFrame = Instance.new("Frame")
wheelFrame.Name = "EmoteWheel"
wheelFrame.Size = UDim2.new(1, 0, 1, 0)
wheelFrame.BackgroundTransparency = 1
wheelFrame.Visible = false
wheelFrame.Parent = gameGUI

-- Overlay oscurecido táctil (Cierra al tocar el fondo en móviles)
local overlay = Instance.new("TextButton")
overlay.Name = "Overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.Parent = wheelFrame

overlay.Activated:Connect(function()
	closeWheel()
end)

-- Centro de la rueda
local centerX = 0.5
local centerY = 0.5

-- Botón de Salir "X" para Móviles y Pistas Rápidas
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 48, 0, 48)
closeButton.Position = UDim2.new(centerX, -24, centerY, -24) -- Centrado en el medio de la rueda
closeButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 22
closeButton.ZIndex = 5
closeButton.Parent = wheelFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0) -- Totalmente circular
closeCorner.Parent = closeButton

local closeStroke = Instance.new("UIStroke")
closeStroke.Color = Color3.fromRGB(255, 255, 255)
closeStroke.Thickness = 2
closeStroke.Parent = closeButton

closeButton.Activated:Connect(function()
	closeWheel()
end)

-- Crear 6 slots radiales como TextButton para soporte completo móvil
local slotFrames = {}
local slotIcons = {}
local slotKeyLabels = {}

for i = 1, 6 do
	local theta = (i - 1) * (2 * math.pi / 6)
	local offsetX = math.cos(theta) * WHEEL_RADIUS
	local offsetY = math.sin(theta) * WHEEL_RADIUS

	local slot = Instance.new("TextButton")
	slot.Name = "EmoteSlot_" .. i
	slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
	slot.Position = UDim2.new(centerX, offsetX - SLOT_SIZE / 2, centerY, offsetY - SLOT_SIZE / 2)
	slot.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	slot.BackgroundTransparency = 0.2
	slot.Text = ""
	slot.AutoButtonColor = false
	slot.ZIndex = 4
	slot.Parent = wheelFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 120)
	stroke.Thickness = 2
	stroke.Parent = slot

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0.8, 0, 0.8, 0)
	icon.Position = UDim2.new(0.1, 0, 0.1, 0)
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.ZIndex = 4
	icon.Parent = slot

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Size = UDim2.new(0.4, 0, 0.3, 0)
	keyLabel.Position = UDim2.new(-0.1, 0, -0.1, 0)
	keyLabel.BackgroundTransparency = 1
	keyLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextSize = 12
	keyLabel.Text = tostring(i)
	keyLabel.ZIndex = 5
	keyLabel.Parent = slot

	slotFrames[i] = slot
	slotIcons[i] = icon
	slotKeyLabels[i] = keyLabel

	-- Interacción táctil y de cursor
	slot.MouseEnter:Connect(function()
		slot.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	end)
	slot.MouseLeave:Connect(function()
		slot.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	end)

	-- Acción de activar emote
	slot.Activated:Connect(function()
		useEmote(i)
	end)
end

-- Texto de cooldown
local cooldownLabel = Instance.new("TextLabel")
cooldownLabel.Size = UDim2.new(0, 200, 0, 40)
cooldownLabel.Position = UDim2.new(centerX, -100, centerY + WHEEL_RADIUS + 30, 0)
cooldownLabel.BackgroundTransparency = 1
cooldownLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
cooldownLabel.Font = Enum.Font.GothamBold
cooldownLabel.TextSize = 18
cooldownLabel.Text = ""
cooldownLabel.Visible = false
cooldownLabel.ZIndex = 5
cooldownLabel.Parent = wheelFrame

-- == LÓGICA DE EMOTE ==

local function getRemainingCooldown()
	local elapsed = tick() - lastEmoteTime
	if elapsed >= EMOTE_COOLDOWN then return 0 end
	return math.ceil(EMOTE_COOLDOWN - elapsed)
end

function useEmote(slotIndex)
	local emoteId = equippedEmotes[slotIndex]
	if not emoteId or emoteId == "" then return end

	local remaining = getRemainingCooldown()
	if remaining > 0 then
		cooldownLabel.Visible = true
		cooldownLabel.Text = "Espera " .. remaining .. "s"
		task.delay(1.5, function()
			cooldownLabel.Visible = false
		end)
		return
	end

	UseEmoteRemote:FireServer(emoteId)
	lastEmoteTime = tick()
	closeWheel()
end

-- == ACTUALIZAR WHEEL CON EMOTES EQUIPADOS ==

local function refreshWheel()
	local raw = player:GetAttribute("EquippedEmotes")
	if raw then
		local ok, data = pcall(function()
			return game:GetService("HttpService"):JSONDecode(raw)
		end)
		if ok and type(data) == "table" then
			for i = 1, 6 do
				equippedEmotes[i] = data[i] or ""
			end
		end
	end

	for i = 1, 6 do
		local emoteId = equippedEmotes[i]
		local cosmeticData = emoteId ~= "" and CosmeticsDatabase.GetCosmetic(emoteId)
		if cosmeticData then
			if cosmeticData.Image then
				slotIcons[i].Image = cosmeticData.Image
			elseif cosmeticData.AnimationId then
				slotIcons[i].Image = "rbxassetid://7734028100"
			end
			slotFrames[i].Visible = true
			slotKeyLabels[i].Text = tostring(i)
		else
			slotIcons[i].Image = ""
			slotFrames[i].Visible = false
		end
	end
end

-- == ABRIR / CERRAR WHEEL ==

function openWheel()
	refreshWheel()
	wheelFrame.Visible = true
	wheelOpen = true

	-- Animación de entrada
	for i = 1, 6 do
		slotFrames[i].Size = UDim2.new(0, 0, 0, 0)
		local targetSize = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		task.delay(i * 0.02, function()
			local tween = TweenService:Create(
				slotFrames[i],
				TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = targetSize }
			)
			tween:Play()
		end)
	end
end

function closeWheel()
	wheelFrame.Visible = false
	wheelOpen = false
end

-- == INPUT ==

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.G then
		if wheelOpen then
			closeWheel()
		else
			openWheel()
		end
	elseif wheelOpen and input.KeyCode == Enum.KeyCode.Escape then
		closeWheel()
	end

	local digitKeys = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
		[Enum.KeyCode.Five] = 5,
		[Enum.KeyCode.Six] = 6,
	}
	local slotNum = digitKeys[input.KeyCode]
	if slotNum and wheelOpen then
		useEmote(slotNum)
	end
end)

-- Actualizar emotes equipados cuando cambian
player:GetAttributeChangedSignal("EquippedEmotes"):Connect(refreshWheel)

print("[EmoteWheelHUD] Rueda de emotes optimizada para Móvil y PC lista.")