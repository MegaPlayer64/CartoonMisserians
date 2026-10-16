--[[
	IntroCutsceneClient (LocalScript)
	Ubicación: StarterPlayer.StarterPlayerScripts.IntroCutsceneClient

	Gestiona cinemáticas de presentación para el Devilish al iniciar la partida (InProgress).
	Funciona tanto para el jugador local como para los Toonflows que observan al Devilish en el mapa.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- == REMOTES ==
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MatchStateRemote = Remotes:WaitForChild("MatchState")

-- == ESTADO INTERNO ==
local cutsceneActive = false
local cutscenePlayedThisMatch = false
local cutsceneThread = nil
local renderConn = nil

local cachedDevilishPlayer = nil
local cachedDevilishName = nil

-- == BANNER UI ==
local screenGui = nil
local bannerFrame = nil
local titleLabel = nil
local subtitleLabel = nil

local function createBanner()
	if screenGui then return end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IntroCutsceneGui"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 50
	screenGui.Parent = player:WaitForChild("PlayerGui")

	bannerFrame = Instance.new("Frame")
	bannerFrame.Name = "CutsceneBanner"
	bannerFrame.Size = UDim2.new(0.5, 0, 0.18, 0)
	bannerFrame.Position = UDim2.new(0.5, 0, 0.78, 0)
	bannerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bannerFrame.BackgroundTransparency = 0.35
	bannerFrame.BorderSizePixel = 0
	bannerFrame.Visible = false
	bannerFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = bannerFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(200, 0, 0)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = bannerFrame

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, -20, 0.55, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0.05, 0)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 28
	titleLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Text = ""
	titleLabel.Parent = bannerFrame

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "SubtitleLabel"
	subtitleLabel.Size = UDim2.new(1, -20, 0.35, 0)
	subtitleLabel.Position = UDim2.new(0.5, 0, 0.6, 0)
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextSize = 18
	subtitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	subtitleLabel.TextStrokeTransparency = 0.5
	subtitleLabel.Text = ""
	subtitleLabel.Parent = bannerFrame
end

local function showBanner(characterName, displayName)
	createBanner()
	if titleLabel then titleLabel.Text = "DEVILISH: " .. tostring(characterName) end
	if subtitleLabel then subtitleLabel.Text = "JUGADO POR: " .. tostring(displayName) end
	if bannerFrame then
		bannerFrame.Visible = true
		bannerFrame.BackgroundTransparency = 1
		local tweenIn = TweenService:Create(
			bannerFrame,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.35 }
		)
		tweenIn:Play()
	end
end

local function hideBanner()
	if not bannerFrame then return end
	local tweenOut = TweenService:Create(
		bannerFrame,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	tweenOut:Play()
	tweenOut.Completed:Connect(function()
		if bannerFrame then bannerFrame.Visible = false end
	end)
end

-- == LIMPIEZA Y RESTAURACIÓN DE CÁMARA ==
local function cleanupCutscene()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end

	if cutsceneThread then
		local threadToCancel = cutsceneThread
		cutsceneThread = nil
		if threadToCancel ~= coroutine.running() then
			task.cancel(threadToCancel)
		end
	end

	local localChar = player.Character
	local localHum = localChar and localChar:FindFirstChildOfClass("Humanoid")

	camera.CameraType = Enum.CameraType.Custom
	if localHum then
		camera.CameraSubject = localHum
	end
	camera.FieldOfView = 70

	cutsceneActive = false
	hideBanner()
end

-- == PRESETS DE CÁMARA ==

local function presetMariposaurio(devilishChar, hrp)
	local startPos = hrp.CFrame * CFrame.new(0, 3, 12)
	camera.CFrame = startPos
	camera.FieldOfView = 70

	local endPos = hrp.CFrame * CFrame.new(0, 2, -10)

	local posTween = TweenService:Create(
		camera,
		TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ CFrame = endPos }
	)
	local fovTween = TweenService:Create(
		camera,
		TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ FieldOfView = 50 }
	)

	posTween:Play()
	fovTween:Play()
end

-- Preset Stan.oma.png: Glitch frontal a la cara usando CFrame local
local function presetStan(devilishChar, hrp)
	local head = devilishChar:FindFirstChild("Head")
	local focusPos = head and head.Position or (hrp.Position + Vector3.new(0, 1.5, 0))

	-- Posición frontal local: -5 en Z coloca la cámara directamente de frente a Stan
	local frontCFrame = hrp.CFrame * CFrame.new(0, 1, -5)
	camera.CFrame = CFrame.new(frontCFrame.Position, focusPos)
	camera.FieldOfView = 65

	renderConn = RunService.RenderStepped:Connect(function()
		if not cutsceneActive then return end
		local shakeX = math.random() * 0.4 - 0.2
		local shakeY = math.random() * 0.4 - 0.2
		local shakeZ = math.random() * 0.2 - 0.1
		local shakeOffset = Vector3.new(shakeX, shakeY, shakeZ)

		local camPos = (hrp.CFrame * CFrame.new(0, 1, -5)).Position + shakeOffset
		camera.CFrame = CFrame.new(camPos, focusPos)
	end)
end

local function presetDefault(devilishChar, hrp)
	local radius = 12
	local heightOffset = 3
	local startTime = os.clock()
	local duration = 3.5

	renderConn = RunService.RenderStepped:Connect(function()
		if not cutsceneActive then return end
		local elapsed = os.clock() - startTime
		local angle = (elapsed / duration) * math.pi * 2.5
		local currentRadius = radius + math.sin(elapsed * 2) * 2
		local currentHeight = heightOffset + math.sin(elapsed * 1.5) * 2

		local offset = Vector3.new(
			math.cos(angle) * currentRadius,
			currentHeight,
			math.sin(angle) * currentRadius
		)
		camera.CFrame = CFrame.new(hrp.Position + offset, hrp.Position)
	end)
end

-- == FUNCIÓN PRINCIPAL DE CINEMÁTICA ==
local function startCutscene(devilishPlayer, characterName)
	if cutsceneActive then cleanupCutscene() end

	local devilishChar = devilishPlayer.Character
	if not devilishChar then
		devilishChar = devilishPlayer.CharacterAdded:Wait()
	end

	local hrp = devilishChar:FindFirstChild("HumanoidRootPart") or devilishChar:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	task.wait(0.2)
	if not (hrp and hrp.Parent) then return end

	cutsceneActive = true
	camera.CameraType = Enum.CameraType.Scriptable

	showBanner(characterName, devilishPlayer.DisplayName)

	cutsceneThread = task.spawn(function()
		if characterName == "Mariposaurio" then
			presetMariposaurio(devilishChar, hrp)
		elseif characterName == "Stan.oma.png" then
			presetStan(devilishChar, hrp)
		else
			presetDefault(devilishChar, hrp)
		end

		task.wait(3.5)

		if cutsceneActive then
			cleanupCutscene()
		end
	end)
end

-- == ESCUCHAR MATCH STATE REMOTE ==
MatchStateRemote.OnClientEvent:Connect(function(state, data)
	if state == "RoleAssigned" then
		cutscenePlayedThisMatch = false
		if not data then return end

		if data.role == "Devilish" then
			cachedDevilishPlayer = player
			cachedDevilishName = data.characterName or "Devilish"
		else
			if data.devilishPlayer then
				cachedDevilishPlayer = data.devilishPlayer
				cachedDevilishName = data.devilishCharacterName or "Devilish"
			end
		end

	elseif state == "InProgress" then
		-- Previene ejecuciones duplicadas en la misma partida
		if cutscenePlayedThisMatch or cutsceneActive then return end

		if not cachedDevilishPlayer then
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				if char then
					local roleAttr = char:GetAttribute("Role")
					local statsRole = char:FindFirstChild("Stats") and char.Stats:FindFirstChild("Role")
					if roleAttr == "Devilish" or (statsRole and statsRole.Value == "Devilish") then
						cachedDevilishPlayer = p
						cachedDevilishName = char:GetAttribute("CharacterName") or "Devilish"
						break
					end
				end
			end
		end

		if cachedDevilishPlayer then
			cutscenePlayedThisMatch = true
			startCutscene(cachedDevilishPlayer, cachedDevilishName or "Devilish")
		end

	elseif state == "Ending" or state == "Intermission" then
		cutscenePlayedThisMatch = false
		cachedDevilishPlayer = nil
		cachedDevilishName = nil
		if cutsceneActive then
			cleanupCutscene()
		end
	end
end)

print("[IntroCutsceneClient] Sincronizado para ejecutarse una sola vez en InProgress.")