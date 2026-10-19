--!strict
--[[
	PlayerData (ModuleScript)
	Ubicación: ServerScriptService.ServerModules.PlayerData

	Persistencia con DataStore de lo que antes vivía SOLO como atributos del
	Player (y se perdía al salir): Coins, OwnedEmotes, EquippedEmotes y MasteryData.

	Los atributos siguen siendo el estado "en vivo" que lee el cliente (la UI ya
	escucha GetAttributeChangedSignal). Este módulo:
	  - carga el perfil al entrar y lo vuelca a los atributos,
	  - marca DataLoaded = true cuando terminó (los handlers deben esperar a eso),
	  - guarda cada AUTOSAVE_SECONDS, al salir (PlayerRemoving) y en BindToClose.

	Seguridad de datos:
	  - Session lock (UpdateAsync + JobId): dos servidores no pisan el mismo perfil.
	  - Si la carga falla en un servidor real, se expulsa al jugador en lugar de
	    dejarlo jugar con datos vacíos y luego sobrescribir su perfil real.
	  - En Studio sin acceso a DataStore se usan datos temporales y NO se guardan.
	  - Todo lo leído o escrito pasa por sanitize(): el esquema siempre es válido.

	Para cambiar el esquema: sube SCHEMA_VERSION y añade el paso en migrate().
	Se inicializa solo al hacer require (basta con requerirlo desde un script).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local STORE_NAME = "PlayerData_v1"
local SCHEMA_VERSION = 1
local SESSION_LOCK_SECONDS = 180 -- debe ser > AUTOSAVE_SECONDS (el autosave renueva el lock)
local AUTOSAVE_SECONDS = 60
local STARTING_COINS = 100
local MAX_COINS = 1_000_000_000
local EMOTE_SLOTS = 6
local MAX_MASTERY_JSON_BYTES = 200_000 -- tope defensivo; el límite de DataStore es 4 MB por clave
local IS_STUDIO = RunService:IsStudio()
local LOAD_ATTEMPTS = if IS_STUDIO then 1 else 6
local SAVE_ATTEMPTS = 4

export type Data = {
	version: number,
	coins: number,
	ownedEmotes: { string },
	equippedEmotes: { string },
	-- JSON de MasteryAndTrophyServer (maestrías, logros, skins). "" = sin datos aún.
	masteryData: string,
}

type Session = { persist: boolean, saving: boolean }

local store = DataStoreService:GetDataStore(STORE_NAME)
local sessions: { [Player]: Session } = {}

-- == ESQUEMA ==

local function defaults(): Data
	return {
		version = SCHEMA_VERSION,
		coins = STARTING_COINS,
		ownedEmotes = { "Happy", "Angry", "GG" },
		equippedEmotes = { "Happy", "Angry", "GG", "", "", "" },
		masteryData = "",
	}
end

local function sanitizeStringList(raw: any, fallback: { string }, fixedLength: number?): { string }
	if type(raw) ~= "table" then
		return fallback
	end
	local out: { string } = {}
	if fixedLength then
		for i = 1, fixedLength do
			local value = raw[i]
			out[i] = if type(value) == "string" then value else ""
		end
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, value in ipairs(raw) do
		if type(value) == "string" and value ~= "" and not seen[value] then
			seen[value] = true
			table.insert(out, value)
		end
	end
	return out
end

-- Construye un Data válido a partir de CUALQUIER cosa (DataStore, atributos...).
local function sanitize(raw: any): Data
	local base = defaults()
	if type(raw) ~= "table" then
		return base
	end

	local coins = raw.coins
	if type(coins) == "number" and coins == coins then
		base.coins = math.clamp(math.floor(coins), 0, MAX_COINS)
	end
	base.ownedEmotes = sanitizeStringList(raw.ownedEmotes, base.ownedEmotes, nil)
	base.equippedEmotes = sanitizeStringList(raw.equippedEmotes, base.equippedEmotes, EMOTE_SLOTS)
	local mastery = raw.masteryData
	if type(mastery) == "string" and #mastery <= MAX_MASTERY_JSON_BYTES then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, mastery)
		if ok and type(decoded) == "table" then
			base.masteryData = mastery
		end
	end
	base.version = SCHEMA_VERSION
	return base
end

local function migrate(raw: any): Data
	-- Aquí van los pasos de migración: if raw.version == 1 then ... end
	return sanitize(raw)
end

-- == LECTURA/ESCRITURA DE ATRIBUTOS ==

local function decodeList(raw: unknown): any
	if typeof(raw) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok then
		return decoded
	end
	return nil
end

local function snapshot(player: Player): Data
	return sanitize({
		coins = player:GetAttribute("Coins"),
		ownedEmotes = decodeList(player:GetAttribute("OwnedEmotes")),
		equippedEmotes = decodeList(player:GetAttribute("EquippedEmotes")),
		masteryData = player:GetAttribute("MasteryData"),
	})
end

local function applyToPlayer(player: Player, data: Data)
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("OwnedEmotes", HttpService:JSONEncode(data.ownedEmotes))
	player:SetAttribute("EquippedEmotes", HttpService:JSONEncode(data.equippedEmotes))
	if data.masteryData ~= "" then
		player:SetAttribute("MasteryData", data.masteryData)
	end
	-- Siempre el último: los handlers esperan a este flag.
	player:SetAttribute("DataLoaded", true)
end

-- == DATASTORE ==

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function lockedByOtherServer(old: any): boolean
	if type(old) ~= "table" or type(old.lock) ~= "table" then
		return false
	end
	local lock = old.lock
	local age = os.time() - (tonumber(lock.time) or 0)
	return lock.jobId ~= game.JobId and age < SESSION_LOCK_SECONDS
end

-- Devuelve (datastore alcanzable y lock adquirido, datos).
local function loadData(player: Player): (boolean, Data?)
	local key = keyFor(player)
	for attempt = 1, LOAD_ATTEMPTS do
		if player.Parent == nil then
			return false, nil
		end

		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old: any)
				if lockedByOtherServer(old) then
					return nil -- cancelar: otro servidor tiene la sesión
				end
				local record: any = if type(old) == "table" then old else {}
				record.lock = { jobId = game.JobId, time = os.time() }
				return record
			end)
		end)

		if ok and type(result) == "table" and type(result.lock) == "table" and result.lock.jobId == game.JobId then
			return true, migrate(result.data)
		end

		if not ok then
			warn(`[PlayerData] Error cargando a {player.Name} (intento {attempt}/{LOAD_ATTEMPTS}): {result}`)
		else
			warn(`[PlayerData] Perfil de {player.Name} bloqueado por otro servidor (intento {attempt}/{LOAD_ATTEMPTS})`)
		end
		if attempt < LOAD_ATTEMPTS then
			task.wait(math.min(2 ^ attempt, 15))
		end
	end
	return false, nil
end

local function writeData(player: Player, data: Data, releaseLock: boolean): boolean
	local key = keyFor(player)
	for attempt = 1, SAVE_ATTEMPTS do
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: any)
				if lockedByOtherServer(old) then
					return nil -- perdimos la sesión: NO pisar el perfil del otro servidor
				end
				local record: any = if type(old) == "table" then old else {}
				record.data = data
				record.lock = if releaseLock then nil else { jobId = game.JobId, time = os.time() }
				return record
			end)
		end)
		if ok then
			return true
		end
		warn(`[PlayerData] Error guardando a {player.Name} (intento {attempt}/{SAVE_ATTEMPTS}): {err}`)
		if attempt < SAVE_ATTEMPTS then
			task.wait(attempt * 2)
		end
	end
	return false
end

local function save(player: Player, releaseLock: boolean): boolean
	local session = sessions[player]
	if not session or not session.persist then
		return true
	end

	if session.saving then
		if not releaseLock then
			return true -- ya hay un guardado en curso; el autosave puede saltarse
		end
		while session.saving do
			task.wait(0.1) -- el guardado final espera al que está en curso
		end
		if not session.persist then
			return true -- ese guardado ya liberó el lock
		end
	end

	session.saving = true
	local ok = writeData(player, snapshot(player), releaseLock)
	session.saving = false

	if ok and releaseLock then
		session.persist = false
	end
	return ok
end

-- == CICLO DE VIDA ==

local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end
	local session: Session = { persist = false, saving = false }
	sessions[player] = session

	local reachable, data = loadData(player)

	if player.Parent == nil then
		-- Se fue durante la carga. Si adquirimos el lock, devolvemos el perfil
		-- SIN tocar (no hay atributos aún): solo liberamos el lock.
		if reachable and data then
			writeData(player, data, true)
		end
		sessions[player] = nil
		return
	end

	if reachable and data then
		applyToPlayer(player, data)
		session.persist = true
	elseif IS_STUDIO then
		warn("[PlayerData] DataStore no disponible en Studio: datos TEMPORALES, no se guardarán.")
		applyToPlayer(player, defaults())
	else
		player:Kick("No pudimos cargar tus datos. Vuelve a entrar en unos minutos; tu progreso está a salvo.")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	task.spawn(function()
		save(player, true)
		sessions[player] = nil
	end)
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			local session = sessions[player]
			if session and session.persist then
				task.spawn(save, player, false)
			end
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	for player, session in pairs(sessions) do
		if session.persist then
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
	end
	local startedAt = os.clock()
	while pending > 0 and os.clock() - startedAt < 25 do
		task.wait(0.2)
	end
end)

-- == API ==

local PlayerData = {}

-- true cuando los atributos del jugador ya reflejan su perfil guardado.
function PlayerData.isLoaded(player: Player): boolean
	return player:GetAttribute("DataLoaded") == true
end

-- Guardado inmediato (p. ej. tras una compra), sin liberar la sesión.
function PlayerData.saveNow(player: Player)
	task.spawn(save, player, false)
end

return PlayerData
