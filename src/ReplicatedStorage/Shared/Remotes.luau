--!strict
-- Única fuente de verdad de los RemoteEvents. El servidor los crea todos al
-- arrancar (Net.init); el cliente nunca crea remotes.

export type RemoteName =
	"Fishing_Start" -- C→S: pedir iniciar ronda (o re-sincronizar si ya hay una)
	| "Fishing_Input" -- C→S: dirección del gancho (-1 sube, 0 quieto, 1 baja)
	| "Fishing_Quit" -- C→S: abandonar la ronda
	| "Fishing_State" -- S→C: snapshot completo de la ronda
	| "Fishing_Spawn" -- S→C: nueva criatura
	| "Fishing_HookState" -- S→C: corrección del gancho (~10 Hz)
	| "Fishing_Result" -- S→C: el gancho tocó algo
	| "Fishing_End" -- S→C: fin de ronda
	| "Cheat_Grant" -- QA (gated por UserId / Studio)
	| "Cheat_Spawn"
	| "Cheat_EndRound"
	| "Cheat_Reset"

local NAMES: { RemoteName } = {
	"Fishing_Start",
	"Fishing_Input",
	"Fishing_Quit",
	"Fishing_State",
	"Fishing_Spawn",
	"Fishing_HookState",
	"Fishing_Result",
	"Fishing_End",
	"Cheat_Grant",
	"Cheat_Spawn",
	"Cheat_EndRound",
	"Cheat_Reset",
}

return NAMES
