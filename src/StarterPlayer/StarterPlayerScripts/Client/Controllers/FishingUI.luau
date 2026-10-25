--!strict
-- GUI del minijuego de pesca. SOLO dibuja y pide acciones; no calcula nada
-- autoritativo: puntos, vidas, Cartonsitos y colisiones vienen del servidor.
--
-- Disposición (como tu boceto): bote con Lucia arriba a la izquierda, tablero
-- "POINTS" arriba a la derecha, agua debajo y dos botones-rombo (▲ ▼) a la
-- derecha para subir/bajar el gancho. Mantén pulsado para moverlo
-- (también W/S o ↑/↓).
--
-- Los dibujos son PLACEHOLDERS (emoji + formas de UI). Para usar tus dibujos,
-- cambia `label` en addEntity por un ImageLabel con `Image = "rbxassetid://..."`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

ReplicatedStorage:WaitForChild("Shared") -- esperar a que replique
local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local FishingLogic = require(ReplicatedStorage.Shared.Util.FishingLogic)
local Net = require(script.Parent.Parent.Net)

local MatchStateRemote =
	ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes"):WaitForChild("MatchState") :: RemoteEvent

local C = Config.Fishing
local KEY_ACTION = "FishingHookKeys"

local FishingUI = {}

-- ───────────────────────── Constantes de diseño ─────────────────────────
-- Unidades de campo: 1 unidad mide lo mismo en X que en Y porque el campo
-- mantiene la proporción fieldWidth : TOTAL_H (UIAspectRatioConstraint).
local SKY_H = 3.2
local TOTAL_H = SKY_H + C.fieldDepth
local SKY_FRAC = SKY_H / TOTAL_H
local HOOK_SX = C.hookX / C.fieldWidth
local ROPE_TOP = SKY_FRAC - 0.16
local ROPE_WIDTH = 0.004
local VISUAL_SCALE = 1.4 -- tamaño dibujado vs. radio de colisión

local INK = Color3.new(0, 0, 0)
local PAPER = Color3.new(1, 1, 1)
local WATER = Color3.fromRGB(205, 236, 250)
local GOOD = Color3.fromRGB(46, 160, 67)
local BAD = Color3.fromRGB(214, 48, 49)
local TRASH = Color3.fromRGB(201, 152, 76)
-- Color del círculo de cada criatura según su categoría: verde = pez, marrón = basura, rojo = peligro
local CATEGORY_COLORS: { [string]: Color3 } = {
	Fish = GOOD,
	Trash = TRASH,
	Danger = BAD,
}
local FONT = Enum.Font.Bangers

-- Vocabulario de animación
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOUNCY = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLOAT = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COUNT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local TITLES: { [string]: string } = {
	TimeUp = "¡SE ACABÓ EL TIEMPO!",
	NoLives = "¡TE QUEDASTE SIN VIDAS!",
	Quit = "FIN DE LA PESCA",
	Left = "FIN DE LA PESCA",
}

-- ───────────────────────────── Helpers de UI ─────────────────────────────
-- Un tween vivo por instancia: cancelar el anterior evita peleas entre tweens.
local live: { [Instance]: Tween } = setmetatable({}, { __mode = "k" }) :: any

local function play(target: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local old = live[target]
	if old then
		old:Cancel()
	end
	local tween = TweenService:Create(target, info, goal)
	live[target] = tween
	-- Completed también se dispara al cancelar. Sin esto, cada instancia animada quedaba retenida
	-- por `live` (el valor, el Tween, referencia a su propia clave): los textos flotantes destruidos
	-- no se liberaban.
	tween.Completed:Connect(function()
		if live[target] == tween then
			live[target] = nil
		end
	end)
	tween:Play()
	return tween
end

local function stroke(target: GuiObject, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = thickness
	s.Parent = target
	return s
end

local function corner(target: GuiObject, radiusScale: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radiusScale, 0)
	c.Parent = target
	return c
end

local function makeFrame(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	zIndex: number
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	f.Parent = parent
	return f
end

local function makeText(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	zIndex: number,
	maxSize: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = INK
	l.TextScaled = true
	l.Position = position
	l.Size = size
	l.ZIndex = zIndex
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = l
	l.Parent = parent
	return l
end

local function makeButton(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	zIndex: number,
	maxSize: number
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundColor3 = PAPER
	b.BorderSizePixel = 0
	b.Font = FONT
	b.Text = text
	b.TextColor3 = INK
	b.TextScaled = true
	b.Position = position
	b.Size = size
	b.ZIndex = zIndex
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = b
	corner(b, 0.25)
	stroke(b, 4)
	-- Estado "pulsado": pequeño pop hacia dentro.
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		play(scale, FAST, { Scale = 0.94 })
	end)
	b.MouseButton1Up:Connect(function()
		play(scale, FAST, { Scale = 1 })
	end)
	b.MouseLeave:Connect(function()
		play(scale, FAST, { Scale = 1 })
	end)
	b.Parent = parent
	return b
end

-- Número que "cuenta" hacia el nuevo valor en vez de saltar.
local function bindCounter(target: TextLabel, format: (number) -> string): (number, boolean) -> ()
	local value = Instance.new("NumberValue")
	value.Changed:Connect(function(v: number)
		target.Text = format(math.round(v))
	end)
	return function(newValue: number, instant: boolean)
		if instant then
			local old = live[value]
			if old then
				old:Cancel()
			end
			value.Value = newValue
			target.Text = format(newValue)
		else
			play(value, COUNT, { Value = newValue })
		end
	end
end

local function makePanel(name: string, title: string): (CanvasGroup, UIScale, TextLabel)
	local p = Instance.new("CanvasGroup")
	p.Name = name
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.Size = UDim2.fromScale(0.56, 0.62)
	p.BackgroundColor3 = PAPER
	p.BorderSizePixel = 0
	p.ZIndex = 10
	p.Visible = false
	corner(p, 0.06)
	stroke(p, 5)
	local scale = Instance.new("UIScale")
	scale.Parent = p
	local titleLabel = makeText(p, "Title", title, UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.18), 11, 60)
	return p, scale, titleLabel
end

-- ──────────────────────────── Construcción de la GUI ────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "FishingGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local launchButton =
	makeButton(gui, "Launch", "🎣 PESCAR", UDim2.fromScale(0.02, 0.86), UDim2.fromScale(0.16, 0.09), 1, 36)
launchButton.Visible = false -- Deactivated: ProximityPrompt replaces the floating button

-- Root: franjas negras (letterbox) alrededor del campo.
local root = makeFrame(gui, "Root", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), INK, 1)
root.Active = true -- no dejar pasar clics al juego de debajo
root.Visible = false

local field = makeFrame(root, "Field", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), PAPER, 1)
field.AnchorPoint = Vector2.new(0.5, 0.5)
field.ClipsDescendants = true
local ratio = Instance.new("UIAspectRatioConstraint")
ratio.AspectRatio = C.fieldWidth / TOTAL_H
ratio.Parent = field

-- Agua + línea de superficie
makeFrame(field, "Water", UDim2.fromScale(0, SKY_FRAC), UDim2.fromScale(1, 1 - SKY_FRAC), WATER, 1)
makeFrame(field, "Surface", UDim2.fromScale(0, SKY_FRAC - 0.003), UDim2.fromScale(1, 0.006), INK, 2)

-- Bote, Lucia y compañero (decoración)
local boat = makeFrame(field, "Boat", UDim2.fromScale(0.01, SKY_FRAC - 0.1), UDim2.fromScale(0.46, 0.115), PAPER, 2)
corner(boat, 0.4)
stroke(boat, 4)
makeText(field, "Companion", "😁", UDim2.fromScale(0.03, SKY_FRAC - 0.22), UDim2.fromScale(0.1, 0.14), 3, 80)
makeText(field, "Lucia", "👧", UDim2.fromScale(0.27, SKY_FRAC - 0.24), UDim2.fromScale(0.1, 0.15), 3, 80)
makeText(field, "LuciaTag", "LUCIA ↙", UDim2.fromScale(0.36, 0.03), UDim2.fromScale(0.13, 0.06), 3, 36)

-- Cuerda + gancho (el servidor manda la profundidad; aquí solo se dibuja)
local rope = makeFrame(field, "Rope", UDim2.fromScale(HOOK_SX, ROPE_TOP), UDim2.fromScale(ROPE_WIDTH, 0), INK, 4)
rope.AnchorPoint = Vector2.new(0.5, 0)
local hookSize = C.hookRadius * 2 * 1.8
local hook = makeFrame(
	field,
	"Hook",
	UDim2.fromScale(HOOK_SX, SKY_FRAC),
	UDim2.fromScale(hookSize / C.fieldWidth, hookSize / TOTAL_H),
	PAPER,
	5
)
hook.AnchorPoint = Vector2.new(0.5, 0.5)
corner(hook, 0.5)
stroke(hook, 4)
makeText(hook, "Glyph", "J", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.8, 0.8), 6, 40)

-- Tablero POINTS (arriba a la derecha)
local board = makeFrame(field, "Board", UDim2.fromScale(0.985, 0.015), UDim2.fromScale(0.27, 0.24), PAPER, 6)
board.AnchorPoint = Vector2.new(1, 0)
stroke(board, 4)
local boardScale = Instance.new("UIScale")
boardScale.Parent = board
makeText(board, "Title", "POINT'S", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.28), 7, 40)
local scoreLabel = makeText(board, "Score", "000000", UDim2.fromScale(0.05, 0.34), UDim2.fromScale(0.9, 0.36), 7, 60)
local cartLabel =
	makeText(board, "Cartonsitos", "0 CARTONSITOS", UDim2.fromScale(0.05, 0.74), UDim2.fromScale(0.9, 0.2), 7, 30)

-- Vidas y tiempo (arriba a la izquierda)
local livesLabel = makeText(field, "Lives", "", UDim2.fromScale(0.015, 0.015), UDim2.fromScale(0.22, 0.07), 6, 40)
local timeLabel = makeText(field, "Time", "", UDim2.fromScale(0.015, 0.09), UDim2.fromScale(0.2, 0.06), 6, 34)
livesLabel.TextXAlignment = Enum.TextXAlignment.Left
timeLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Botones-rombo ▲ ▼
local function makeArrowButton(name: string, glyph: string, centerY: number): (TextButton, Frame)
	local holder = Instance.new("Frame")
	holder.Name = name .. "Holder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.875, centerY)
	holder.Size = UDim2.fromScale(0.2, 0.2)
	holder.ZIndex = 7
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = holder

	local diamond = makeFrame(holder, "Diamond", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.68, 0.68), PAPER, 7)
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Rotation = 45
	stroke(diamond, 5)

	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Font = Enum.Font.GothamBlack
	button.Text = glyph
	button.TextColor3 = INK
	button.TextScaled = true
	button.ZIndex = 8
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.28, 0)
	pad.PaddingBottom = UDim.new(0.28, 0)
	pad.PaddingLeft = UDim.new(0.28, 0)
	pad.PaddingRight = UDim.new(0.28, 0)
	pad.Parent = button
	button.Parent = holder

	holder.Parent = field
	return button, diamond
end

local upButton, upDiamond = makeArrowButton("Up", "▲", 0.45)
local downButton, downDiamond = makeArrowButton("Down", "▼", 0.74)

-- Destello de daño (sobre el juego, bajo los paneles)
local flash = makeFrame(field, "Flash", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), BAD, 9)
flash.BackgroundTransparency = 1

-- Panel de inicio
local startPanel, startScale = makePanel("StartPanel", "¡A PESCAR!")
local startBody = makeText(
	startPanel,
	"Body",
	"Sube y baja el gancho.\nAtrapa peces y gana CARTONSITOS.\nEsquiva la basura y los bichos peligrosos.",
	UDim2.fromScale(0.06, 0.24),
	UDim2.fromScale(0.88, 0.38),
	11,
	34
)
startBody.TextWrapped = true
local playButton = makeButton(startPanel, "Play", "PESCAR", UDim2.fromScale(0.1, 0.66), UDim2.fromScale(0.8, 0.14), 11, 44)
local closeButton =
	makeButton(startPanel, "Close", "SALIR", UDim2.fromScale(0.1, 0.83), UDim2.fromScale(0.8, 0.11), 11, 30)
startPanel.Parent = field

-- Panel de fin de ronda
local endPanel, endScale, endTitle = makePanel("EndPanel", "FIN DE LA PESCA")
local endStats = makeText(endPanel, "Stats", "", UDim2.fromScale(0.06, 0.24), UDim2.fromScale(0.88, 0.38), 11, 38)
endStats.TextWrapped = true
local againButton =
	makeButton(endPanel, "Again", "OTRA VEZ", UDim2.fromScale(0.1, 0.66), UDim2.fromScale(0.8, 0.14), 11, 44)
local exitButton = makeButton(endPanel, "Exit", "SALIR", UDim2.fromScale(0.1, 0.83), UDim2.fromScale(0.8, 0.11), 11, 30)
endPanel.Parent = field

local setScore = bindCounter(scoreLabel, function(n: number): string
	return string.format("%06d", n)
end)
local setCartonsitos = bindCounter(cartLabel, function(n: number): string
	return `{n} CARTONSITOS`
end)

-- ─────────────────────────────── Estado ───────────────────────────────
type EntityView = { data: Types.Entity, kind: Types.KindDef, label: ImageLabel }

local views: { [number]: EntityView } = {}
local running = false
local startPending = false
local hookY = 0
local hookInput = 0
local sentInput = 0
local stunUntil = 0
local endsAt = 0
local balanceAtStart = 0
local shownSeconds = -1
local frameConn: RBXScriptConnection? = nil
local held: { [string]: boolean } = { upButton = false, downButton = false, upKey = false, downKey = false }

local function showPanel(panel: CanvasGroup, scale: UIScale)
	panel.Visible = true
	panel.GroupTransparency = 1
	scale.Scale = 0.8
	play(panel, FAST, { GroupTransparency = 0 })
	play(scale, BOUNCY, { Scale = 1 })
end

local function hidePanel(panel: CanvasGroup)
	panel.Visible = false
end

local function setLives(lives: number)
	livesLabel.Text = string.rep("❤️", lives) .. string.rep("🖤", math.max(0, C.startingLives - lives))
end

local function entityPosition(entity: Types.Entity, t: number): UDim2
	return UDim2.fromScale(FishingLogic.entityX(entity, t, C) / C.fieldWidth, (SKY_H + entity.y) / TOTAL_H)
end

local function addEntity(entity: Types.Entity)
	if views[entity.id] then
		return
	end
	local kind = C.kindsById[entity.kind]
	if not kind then
		return
	end
	local size = kind.radius * 2 * VISUAL_SCALE
	local label = Instance.new("ImageLabel")
	label.Name = kind.id
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromScale(size / C.fieldWidth, size / TOTAL_H)
	label.ZIndex = 3
	label.Position = entityPosition(entity, workspace:GetServerTimeNow())

	if kind.image and kind.image ~= "" then
		-- Pixel-art sprite mode
		label.BackgroundTransparency = 1
		label.Image = kind.image
		label.ResampleMode = Enum.ResamplerMode.Pixelated
	else
		-- Bug 6: Fallback visual when no sprite is set
		-- Use a colored circle with the entity kind id as text
		-- Antes: `if kind.cartonsitos > 0 then GOOD elseif kind.damage > 0 ...`. `damage` no existe en KindDef:
		-- con los peces la condición se cortaba en cartonsitos > 0, pero basura y peligros (cartonsitos = 0)
		-- evaluaban `nil > 0`, lanzaban un error y NUNCA se dibujaban (aunque el servidor sí los contaba).
		label.BackgroundColor3 = CATEGORY_COLORS[kind.category] or WATER
		label.BackgroundTransparency = 0.1
		label.Image = ""
		corner(label, 0.5)
		stroke(label, 3)
		local glyph = Instance.new("TextLabel")
		glyph.Name = "Glyph"
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(0.8, 0.8)
		glyph.BackgroundTransparency = 1
		glyph.Font = FONT
		glyph.Text = if kind.icon ~= "" then kind.icon else kind.name
		glyph.TextColor3 = INK
		glyph.TextScaled = true
		glyph.ZIndex = 4
		glyph.Parent = label
	end

	label.Parent = field
	views[entity.id] = { data = entity, kind = kind, label = label }
end

local function clearViews()
	for id, view in views do
		view.label:Destroy()
		views[id] = nil
	end
end

local function floatText(position: UDim2, text: string, color: Color3)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color
	l.TextStrokeColor3 = INK
	l.TextStrokeTransparency = 0
	l.TextScaled = true
	l.Size = UDim2.fromScale(0.14, 0.07)
	l.Position = position
	l.ZIndex = 8
	l.Parent = field
	local tween = TweenService:Create(l, FLOAT, {
		Position = position - UDim2.fromScale(0, 0.1),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Once(function()
		l:Destroy()
	end)
	tween:Play()
end

local function pop(scale: UIScale, amount: number)
	scale.Scale = amount
	play(scale, BOUNCY, { Scale = 1 })
end

-- ───────────────────────────── Entrada del jugador ─────────────────────────────
-- Solo se envía al servidor cuando la dirección CAMBIA (nunca por frame).
local function refreshInput()
	local up = held.upButton or held.upKey
	local down = held.downButton or held.downKey
	local value = (if down then 1 else 0) - (if up then 1 else 0)
	hookInput = value -- predicción local (el servidor corrige)
	if value ~= sentInput then
		sentInput = value
		Net.fire("Fishing_Input", value)
	end
end

local function isPointerPress(input: InputObject): boolean
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

local function bindHold(button: TextButton, diamond: Frame, key: string)
	button.InputBegan:Connect(function(input: InputObject)
		if not running or not isPointerPress(input) then
			return
		end
		held[key] = true
		diamond.BackgroundColor3 = WATER
		refreshInput()
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if not isPointerPress(input) then
			return
		end
		held[key] = false
		diamond.BackgroundColor3 = PAPER
		if running then
			refreshInput()
		end
	end)
end

-- W/S/↑/↓ mueven el gancho. Con UserInputService el personaje TAMBIÉN caminaba (W/S son sus
-- teclas de movimiento y no llegan marcadas como "processed"). ContextActionService con prioridad
-- alta y Sink se queda con las teclas mientras dura la ronda.
local function onKeyAction(
	_actionName: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult?
	local pressed = state == Enum.UserInputState.Begin
	local released = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	if not pressed and not released then
		return Enum.ContextActionResult.Sink
	end
	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then
		held.upKey = pressed
		refreshInput()
	elseif input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then
		held.downKey = pressed
		refreshInput()
	end
	return Enum.ContextActionResult.Sink
end

local function connectKeys()
	ContextActionService:UnbindAction(KEY_ACTION)
	ContextActionService:BindActionAtPriority(
		KEY_ACTION,
		onKeyAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.W,
		Enum.KeyCode.S,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down
	)
end

bindHold(upButton, upDiamond, "upButton")
bindHold(downButton, downDiamond, "downButton")

-- ─────────────────────────────── Bucle de dibujo ───────────────────────────────
-- Se conecta SOLO mientras hay una ronda y se desconecta al terminar.
local function onFrame(dt: number)
	local t = workspace:GetServerTimeNow()
	local stunned = t < stunUntil

	if not stunned then
		hookY = FishingLogic.stepHook(hookY, hookInput, dt, C.hookSpeed, 0, C.fieldDepth)
	end

	local hy = (SKY_H + hookY) / TOTAL_H
	hook.Position = UDim2.fromScale(HOOK_SX, hy)
	hook.BackgroundColor3 = if stunned then BAD else PAPER
	rope.Size = UDim2.fromScale(ROPE_WIDTH, math.max(0, hy - ROPE_TOP))

	for id, view in views do
		if FishingLogic.isGone(view.data, t, C) then
			view.label:Destroy()
			views[id] = nil
		else
			view.label.Position = entityPosition(view.data, t)
		end
	end

	local remaining = math.max(0, math.ceil(endsAt - t))
	if remaining ~= shownSeconds then
		shownSeconds = remaining
		timeLabel.Text = `TIEMPO: {remaining}`
	end
end

local function stopLoop()
	running = false
	if frameConn then
		frameConn:Disconnect()
		frameConn = nil
	end
	ContextActionService:UnbindAction(KEY_ACTION)
	for key in held do
		held[key] = false
	end
	upDiamond.BackgroundColor3 = PAPER
	downDiamond.BackgroundColor3 = PAPER
	hookInput = 0
	sentInput = 0
end

-- ───────────────────────── Flujo: abrir / empezar / cerrar ─────────────────────────
local function openGame()
	root.Visible = true
	setScore(0, true)
	setCartonsitos(0, true)
	setLives(C.startingLives)
	timeLabel.Text = `TIEMPO: {C.roundSeconds}`
	hidePanel(endPanel)
	showPanel(startPanel, startScale)
end

local function closeGame()
	if running then
		Net.fire("Fishing_Quit")
	end
	stopLoop()
	clearViews()
	hidePanel(startPanel)
	hidePanel(endPanel)
	root.Visible = false
end

local function requestStart()
	if running or startPending then
		return
	end
	startPending = true
	hidePanel(startPanel)
	hidePanel(endPanel)
	Net.fire("Fishing_Start")
	task.delay(1.5, function()
		startPending = false
		-- Si el servidor no arrancó la ronda (p. ej. cooldown), volver al inicio.
		if not running and root.Visible then
			showPanel(startPanel, startScale)
		end
	end)
end

local function beginRound(s: Types.RoundSnapshot)
	if not root.Visible then
		-- El jugador cerró la GUI mientras el servidor arrancaba la ronda.
		Net.fire("Fishing_Quit")
		return
	end
	stopLoop()
	clearViews()
	running = true
	endsAt = s.endsAt
	hookY = s.hookY
	stunUntil = s.stunUntil
	balanceAtStart = s.balance
	shownSeconds = -1
	setScore(s.points, true)
	setCartonsitos(s.balance + s.cartonsitos, true)
	setLives(s.lives)
	for _, entity in s.entities do
		-- pcall: antes un error en addEntity cortaba beginRound a medias (paneles sin ocultar, resto de
		-- entidades sin dibujar)
		local ok, err = pcall(addEntity, entity)
		if not ok then
			warn("[FishingUI] No se pudo dibujar la entidad " .. tostring(entity.kind) .. ": " .. tostring(err))
		end
	end
	hidePanel(startPanel)
	hidePanel(endPanel)
	connectKeys()
	frameConn = RunService.Heartbeat:Connect(onFrame)
end

-- ───────────────────────────── Eventos del servidor ─────────────────────────────
local function onHookState(s: Types.HookState)
	if not running then
		return
	end
	stunUntil = s.stunUntil
	local diff = s.y - hookY
	if math.abs(diff) > 0.5 then
		hookY = s.y -- desincronizado: aceptar la posición del servidor
	else
		hookY += diff * 0.25 -- corrección suave
	end
end

local function onResult(r: Types.HookResult)
	if not running then
		return
	end
	local kind = C.kindsById[r.kind]
	local view = views[r.entityId]
	local position = if view then view.label.Position else UDim2.fromScale(HOOK_SX, (SKY_H + hookY) / TOTAL_H)
	if view then
		view.label:Destroy()
		views[r.entityId] = nil
	end

	stunUntil = r.stunUntil
	setScore(r.points, false)
	setCartonsitos(balanceAtStart + r.cartonsitos, false)
	setLives(r.lives)

	if r.pointsDelta >= 0 then
		local extra = if kind and kind.cartonsitos > 0 then ` +{kind.cartonsitos}🪙` else ""
		floatText(position, `+{r.pointsDelta}{extra}`, GOOD)
		pop(boardScale, 1.12)
	else
		floatText(position, `{r.pointsDelta}`, BAD)
		flash.BackgroundTransparency = 0.55
		play(flash, FLASH, { BackgroundTransparency = 1 })
	end
end

local function onEnd(e: Types.RoundEnd)
	if not root.Visible then
		return
	end
	stopLoop()
	clearViews()
	setScore(e.points, false)
	setCartonsitos(e.balance, false)
	endTitle.Text = TITLES[e.reason] or "FIN DE LA PESCA"
	endStats.Text = `Puntos: {e.points}\nCartonsitos ganados: {e.cartonsitos}\nTotal: {e.balance}`
	showPanel(endPanel, endScale)
end

-- ─────────────────────────────── Ciclo de vida ───────────────────────────────
-- Find the ProximityPrompt on the Arcade Machine in the workspace.
local function findArcadePrompt(): ProximityPrompt?
	local machine = workspace:FindFirstChild("Arcade Machine")
	if not machine then return nil end
	local base = machine:FindFirstChild("Base")
	if not base then return nil end
	local panel = base:FindFirstChild("Control Panel")
	if not panel then return nil end
	local part = panel:FindFirstChild("Part")
	if not part or not part:IsA("BasePart") then return nil end
	return part:FindFirstChild("FishingPrompt") :: ProximityPrompt?
end

-- Holds a reference to the arcade prompt once it streams in.
-- With StreamingEnabled, the Arcade Machine may not exist when init() runs.
local arcadePrompt: ProximityPrompt? = nil
local promptBlocked = false -- estado de partida: los prompts que lleguen por streaming lo respetan
local connectedPrompts: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function connectArcadePrompt(prompt: ProximityPrompt)
	if connectedPrompts[prompt] then
		return
	end
	connectedPrompts[prompt] = true
	arcadePrompt = prompt
	prompt.Triggered:Connect(function(player: Player)
		if player == Players.LocalPlayer and not root.Visible then
			openGame()
		end
	end)
	prompt.Enabled = not promptBlocked -- disponible en Intermission
end

function FishingUI.init()
	-- launchButton deactivated: ProximityPrompt is used instead
	playButton.Activated:Connect(requestStart)
	againButton.Activated:Connect(requestStart)
	closeButton.Activated:Connect(closeGame)
	exitButton.Activated:Connect(closeGame)

	-- Connect ProximityPrompt to openGame
	-- With StreamingEnabled, the Arcade Machine may not be loaded yet.
	-- Try immediately; if not found, listen for it to stream in.
	local prompt = findArcadePrompt()
	if prompt then
		connectArcadePrompt(prompt)
	end

	-- Conexión PERMANENTE: con StreamingEnabled la máquina se descarga y se recarga como una
	-- instancia nueva al alejarse y volver; antes la conexión se soltaba tras la primera vez y el
	-- prompt dejaba de funcionar hasta volver a entrar. Se comprueba primero el nombre (barato).
	workspace.DescendantAdded:Connect(function(descendant: Instance)
		if descendant.Name == "FishingPrompt" and descendant:IsA("ProximityPrompt") then
			connectArcadePrompt(descendant)
		end
	end)

	-- Listen to MatchState for auto-close and ProximityPrompt toggling
	MatchStateRemote.OnClientEvent:Connect(function(state: string, _data: any)
		-- Change 1: Auto-close fishing GUI when match starts
		if state == "RoleAssigned" or state == "InProgress" then
			if root.Visible then
				closeGame()
			end
		end

		-- Change 2: ProximityPrompt disabled only during active match phases
		promptBlocked = state == "RoleAssigned" or state == "InProgress" or state == "Ending"
		if arcadePrompt then
			arcadePrompt.Enabled = not promptBlocked
		end
	end)

	Net.on("Fishing_State", beginRound)
	Net.on("Fishing_Spawn", function(entity: Types.Entity)
		if running then
			local ok, err = pcall(addEntity, entity)
			if not ok then
				warn("[FishingUI] No se pudo dibujar la entidad " .. tostring(entity.kind) .. ": " .. tostring(err))
			end
		end
	end)
	Net.on("Fishing_HookState", onHookState)
	Net.on("Fishing_Result", onResult)
	Net.on("Fishing_End", onEnd)

	local player = Players.LocalPlayer
	gui.Parent = player:WaitForChild("PlayerGui")
end

return FishingUI
