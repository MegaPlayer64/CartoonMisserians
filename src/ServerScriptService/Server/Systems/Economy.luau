--!strict
-- Saldo de Cartonsitos. Única puerta para modificarlo: Economy.addCartonsitos.
--
-- Persistencia delegada a CartoonsitosManager (atributos en Player + CoinUpdate remote).
-- Economy actúa como capa de validación y traducción para el minijuego de pesca.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local CartoonsitosManager = require(ServerScriptService:FindFirstChild("CartoonsitosManager") :: ModuleScript)

local MAX_GRANT = 1_000_000

local Economy = {}

function Economy.get(player: Player): number
	return CartoonsitosManager.GetCoins(player)
end

-- Devuelve false si el valor es inválido (NaN, negativo, no entero, enorme).
-- Acredita los Cartonsitos de forma persistente via CartoonsitosManager.
function Economy.addCartonsitos(player: Player, amount: number): boolean
	if amount ~= amount or amount < 0 or amount ~= math.floor(amount) or amount > MAX_GRANT then
		return false
	end
	CartoonsitosManager.AddCoins(player, amount, "Minijuego Pesca Arcade")
	return true
end

-- Solo para QA (Cheat_Reset).
function Economy.reset(player: Player)
	player:SetAttribute("Coins", 0)
end

function Economy.init()
	-- CartoonsitosManager handles player initialization via Player attributes.
	-- Economy delegates all balance management to it.
end

return Economy
