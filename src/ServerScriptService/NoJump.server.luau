--[[
	NoJump (Script)
	Ubicación: ServerScriptService.NoJump

	QNA oficial: el salto está desactivado en todo el juego.

	default.project.json ya deja StarterPlayer con JumpPower/JumpHeight = 0, pero los personajes de
	partida se sustituyen por un clon de ReplicatedStorage.Characters (con los valores del modelo), así que
	aquí se fuerza en CADA personaje que aparece. El estado Jumping se desactiva además: el botón de salto
	táctil de Roblox se oculta con él y la tecla Espacio no hace nada.
]]

local Players = game:GetService("Players")

local function disableJump(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(disableJump)
	if player.Character then
		task.spawn(disableJump, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
