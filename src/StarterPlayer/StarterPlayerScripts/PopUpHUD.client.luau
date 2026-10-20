--[[
	PopUpHUD (LocalScript)
	Ubicacion: StarterPlayer.StarterPlayerScripts.PopUpHUD

	Escucha el RemoteEvent TriggerPopups enviado por StanAbilities.RayoCorrupto.
	Genera ventanas de error estilo Windows retro en posiciones aleatorias
	de la pantalla del jugador atacado durante la duracion especificada.

	Las ventanas son puramente visuales y molestas (no bloquean el juego).
	Se cierran automaticamente al terminar la duracion.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local TriggerPopups = Remotes:WaitForChild("TriggerPopups")

-- == MENSAJES DE ERROR RETRO ESTILO WINDOWS ==
local POPUP_TITLES = {
	"Error",
	"Warning",
	"System Failure",
	"Critical Error",
	"Stan.oma.exe",
	"Fatal Exception",
	"Corruption Detected",
	"System32",
}

local POPUP_MESSAGES = {
	"A fatal exception has occurred at STAN0X0040:90. The current application will be terminated.",
	"Warning: Your system has been compromised by Stan.oma.png. All your files are belong to us.",
	"System Failure: Corruption detected in memory sector 0xDEAD. Press OK to continue.",
	"Critical Error: The operation cannot be completed because Stan.oma.png has taken control.",
	"Stan.oma.exe has stopped responding. Windows is checking for a solution to the problem...",
	"Fatal Exception 0xC0RRUPT: The system has encountered a cartuhdge error.",
	"Corruption Detected: Your Toonflow data is being overwritten. Have a nice day.",
	"System32: Access denied. You do not have permission to resist Stan.oma.png.",
	"Error 404: Toonflow not found. Stan.oma.png has consumed everything.",
	"Warning: Unresolved error. The virus Stan.oma.png is spreading through your system.",
	"Runtime Error: This program has performed an illegal operation and will be shut down.",
	"Microsoft Toonflow: A problem has been detected and Stan.oma.png was installed to fix it.",
}

local POPUP_BUTTONS = {
	"OK",
	"Cancel",
	"OK",
	"Retry",
	"OK",
	"Abort",
	"OK",
	"Ignore",
}

-- Color scheme retro Windows
local COLOR_WINDOW_BG = Color3.fromRGB(192, 192, 192)
local COLOR_TITLE_BAR = Color3.fromRGB(0, 0, 128)
local COLOR_TITLE_TEXT = Color3.fromRGB(255, 255, 255)
local COLOR_TEXT = Color3.fromRGB(0, 0, 0)
local COLOR_BUTTON_BG = Color3.fromRGB(192, 192, 192)
local COLOR_BUTTON_BORDER_LIGHT = Color3.fromRGB(223, 223, 223)
local COLOR_BUTTON_BORDER_DARK = Color3.fromRGB(128, 128, 128)
local COLOR_ERROR_ICON = Color3.fromRGB(200, 0, 0)

local popupCounter = 0

local popupContainer = Instance.new("ScreenGui")
popupContainer.Name = "PopUpHUD"
popupContainer.ResetOnSpawn = false
popupContainer.IgnoreGuiInset = true
popupContainer.DisplayOrder = 9999
popupContainer.Parent = playerGui

local function createPopup()
	popupCounter += 1

	local width = math.random(180, 320)
	local height = math.random(100, 180)

	local screenW = popupContainer.AbsoluteSize.X
	local screenH = popupContainer.AbsoluteSize.Y
	if screenW <= 0 then screenW = 800 end
	if screenH <= 0 then screenH = 600 end

	local posX = math.random(0, math.max(0, screenW - width))
	local posY = math.random(0, math.max(0, screenH - height))

	local window = Instance.new("Frame")
	window.Name = "PopupWindow_" .. popupCounter
	window.Size = UDim2.new(0, width, 0, height)
	window.Position = UDim2.new(0, posX, 0, posY)
	window.BackgroundColor3 = COLOR_WINDOW_BG
	window.BorderSizePixel = 0
	window.Parent = popupContainer

	local borderLight = Instance.new("Frame")
	borderLight.Name = "BorderTopLeft"
	borderLight.Size = UDim2.new(1, 2, 1, 2)
	borderLight.Position = UDim2.new(0, -1, 0, -1)
	borderLight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	borderLight.BorderSizePixel = 0
	borderLight.ZIndex = window.ZIndex - 1
	borderLight.Parent = window

	local borderDark = Instance.new("Frame")
	borderDark.Name = "BorderBottomRight"
	borderDark.Size = UDim2.new(1, 2, 1, 2)
	borderDark.Position = UDim2.new(0, 1, 0, 1)
	borderDark.BackgroundColor3 = Color3.fromRGB(128, 128, 128)
	borderDark.BorderSizePixel = 0
	borderDark.ZIndex = window.ZIndex - 1
	borderDark.Parent = window

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, -4, 0, 22)
	titleBar.Position = UDim2.new(0, 2, 0, 2)
	titleBar.BackgroundColor3 = COLOR_TITLE_BAR
	titleBar.BorderSizePixel = 0
	titleBar.Parent = window

	local titleIndex = math.random(1, #POPUP_TITLES)
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -24, 1, 0)
	titleLabel.Position = UDim2.new(0, 4, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = POPUP_TITLES[titleIndex]
	titleLabel.TextColor3 = COLOR_TITLE_TEXT
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.Code
	titleLabel.TextSize = 12
	titleLabel.Parent = titleBar

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 18, 0, 18)
	closeButton.Position = UDim2.new(1, -20, 0, 2)
	closeButton.BackgroundColor3 = COLOR_WINDOW_BG
	closeButton.Text = "X"
	closeButton.TextColor3 = COLOR_TEXT
	closeButton.Font = Enum.Font.Code
	closeButton.TextSize = 11
	closeButton.BorderSizePixel = 1
	closeButton.Parent = titleBar

	closeButton.MouseButton1Click:Connect(function()
		window:Destroy()
		if popupContainer.Parent then
			createPopup()
		end
	end)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -8, 1, -32)
	content.Position = UDim2.new(0, 4, 0, 26)
	content.BackgroundTransparency = 1
	content.Parent = window

	local icon = Instance.new("TextLabel")
	icon.Name = "ErrorIcon"
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundColor3 = COLOR_ERROR_ICON
	icon.Text = "X"
	icon.TextColor3 = Color3.fromRGB(255, 255, 255)
	icon.Font = Enum.Font.Code
	icon.TextSize = 18
	icon.BorderSizePixel = 0
	icon.Parent = content

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local messageIndex = math.random(1, #POPUP_MESSAGES)
	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "Message"
	messageLabel.Size = UDim2.new(1, -44, 1, -40)
	messageLabel.Position = UDim2.new(0, 40, 0, 4)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = POPUP_MESSAGES[messageIndex]
	messageLabel.TextColor3 = COLOR_TEXT
	messageLabel.TextXAlignment = Enum.TextXAlignment.Left
	messageLabel.TextYAlignment = Enum.TextYAlignment.Top
	messageLabel.TextWrapped = true
	messageLabel.Font = Enum.Font.Code
	messageLabel.TextSize = 11
	messageLabel.Parent = content

	local buttonIndex = math.random(1, #POPUP_BUTTONS)
	local actionButton = Instance.new("TextButton")
	actionButton.Name = "ActionButton"
	actionButton.Size = UDim2.new(0, 70, 0, 22)
	actionButton.Position = UDim2.new(0.5, -35, 1, -26)
	actionButton.BackgroundColor3 = COLOR_BUTTON_BG
	actionButton.Text = POPUP_BUTTONS[buttonIndex]
	actionButton.TextColor3 = COLOR_TEXT
	actionButton.Font = Enum.Font.Code
	actionButton.TextSize = 11
	actionButton.BorderSizePixel = 1
	actionButton.Parent = content

	local btnLight = Instance.new("Frame")
	btnLight.Size = UDim2.new(1, 0, 0, 1)
	btnLight.Position = UDim2.new(0, 0, 0, 0)
	btnLight.BackgroundColor3 = COLOR_BUTTON_BORDER_LIGHT
	btnLight.BorderSizePixel = 0
	btnLight.ZIndex = actionButton.ZIndex + 1
	btnLight.Parent = actionButton

	local btnLight2 = Instance.new("Frame")
	btnLight2.Size = UDim2.new(0, 1, 1, 0)
	btnLight2.Position = UDim2.new(0, 0, 0, 0)
	btnLight2.BackgroundColor3 = COLOR_BUTTON_BORDER_LIGHT
	btnLight2.BorderSizePixel = 0
	btnLight2.ZIndex = actionButton.ZIndex + 1
	btnLight2.Parent = actionButton

	local btnDark = Instance.new("Frame")
	btnDark.Size = UDim2.new(1, 0, 0, 1)
	btnDark.Position = UDim2.new(0, 0, 1, -1)
	btnDark.BackgroundColor3 = COLOR_BUTTON_BORDER_DARK
	btnDark.BorderSizePixel = 0
	btnDark.ZIndex = actionButton.ZIndex + 1
	btnDark.Parent = actionButton

	local btnDark2 = Instance.new("Frame")
	btnDark2.Size = UDim2.new(0, 1, 1, 0)
	btnDark2.Position = UDim2.new(1, -1, 0, 0)
	btnDark2.BackgroundColor3 = COLOR_BUTTON_BORDER_DARK
	btnDark2.BorderSizePixel = 0
	btnDark2.ZIndex = actionButton.ZIndex + 1
	btnDark2.Parent = actionButton

	actionButton.MouseButton1Click:Connect(function()
		window:Destroy()
		if popupContainer.Parent then
			createPopup()
		end
	end)

	window.Size = UDim2.new(0, 0, 0, 0)
	window.Position = UDim2.new(0, posX + width / 2, 0, posY + height / 2)

	local appearTween = TweenService:Create(window, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, width, 0, height),
		Position = UDim2.new(0, posX, 0, posY),
	})
	appearTween:Play()

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://1843932197"
	sound.Volume = 0.3
	sound.Parent = window
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 2)

	return window
end

TriggerPopups.OnClientEvent:Connect(function(duration)
	duration = duration or 5

	for _, child in ipairs(popupContainer:GetChildren()) do
		child:Destroy()
	end

	local active = true
	local spawnInterval = 0.3
	local maxPopups = 12
	local currentPopups = 0

	task.spawn(function()
		while active and currentPopups < maxPopups do
			local existingCount = 0
			for _, child in ipairs(popupContainer:GetChildren()) do
				existingCount += 1
			end

			if existingCount < 6 then
				createPopup()
				currentPopups += 1
			end

			task.wait(spawnInterval)
		end
	end)

	task.delay(duration, function()
		active = false
		for _, child in ipairs(popupContainer:GetChildren()) do
			local fadeTween = TweenService:Create(child, TweenInfo.new(0.3), {
				BackgroundTransparency = 1,
			})
			fadeTween:Play()
			fadeTween.Completed:Connect(function()
				child:Destroy()
			end)
		end
	end)
end)

print("[PopUpHUD] Sistema de pop-ups retro inicializado para " .. player.Name)