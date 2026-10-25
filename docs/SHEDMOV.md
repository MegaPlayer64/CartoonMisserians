# Shed.mov (Devilish)

`CharacterDatabase.Name = "Shedmov"` · módulo `ServerModules/ShedMovAbilities.luau` · todo el balance está
en las constantes de la parte superior de ese archivo.

| Parte | Cómo está implementado |
|---|---|
| **Pasiva "Mantente fuera"** | `StartPassive` (la inicia `MatchManager`). Hay *persecución* cuando un Toonflow en pie está a ≤ 25 studs con línea de visión; se sale de ella tras 3 s sin verlo. **Pasiva:** atributo `TerrorRadiusMultiplier = 0.5` (el cliente escala las capas de tensión de la música con él). **Agresiva:** `TerrorRadiusMultiplier = 1`, +10 % de velocidad (fuente `ShedChase`) y ruido de motosierra. |
| **Carga de Motosierra** (24 s) | `LinearVelocity` horizontal 1,75 s hacia el punto apuntado. Impacta al primer Toonflow *en pie*: 30 de daño (`ApplyDamage`) + **Sangrado** (3 de daño/s durante 6 s, sin apilar, se corta si el objetivo cae derribado). Si falla (o choca con una pared) queda en recuperación 1,2 s (`StatsModule.Stun`). |
| **¡FUERA DE MI COBERTIZO!** (30 s) | Radio 45 studs. A cada Toonflow vivo y no escapado: **Lentitud I** (×0,5, 3 s), **cancela la tarea en curso** (`TaskManager.Interrupt`, 1 s sin poder retomarla; avisa al cliente con `CancelInteraction`) y **revela su posición** 6 s (Highlight `AlwaysOnTop`). |
| **Bienvenida a Ponyville** (90 s) | 15 s: velocidad ×1,2 (fuente `ShedBerserk`, se combina multiplicando con el ×1,1 de la persecución), `AttackSpeedMultiplier = 1.5` (el cooldown de ataque de `CombatServer` se divide por él), y atributos `StunImmune` / `SlowImmune`. |

## Piezas nuevas que usa
- `StatsModule.ApplySpeedMultiplier(personaje, nombre, multiplicador, duración?)`, `RemoveSpeedMultiplier`, `ClearSlows`: velocidades **con nombre** que se combinan y caducan solas.
- Inmunidades en `StatsModule` (`SetState`, `Stun`, `SetSpeedMultiplier`, `ApplySpeedMultiplier`) mediante los atributos `StunImmune` y `SlowImmune`.
- `TaskManager.Interrupt(jugador, segundos)` / `IsInterrupted(jugador)`.
- Remote `CancelInteraction` + `InteractionCancelClient` (cierra la barra de "mantener pulsado").
- `AbilityLoadouts.ByCharacter.Shedmov`: teclas 1-3, HUD y botones móviles salen de ahí.

## Pendiente de tu parte
- **Sonido de la motosierra:** pon el asset en `CHAINSAW_SOUND_ID`. Vacío = no suena.
- **Valores de balance**: los he elegido yo donde la ficha no daba número (daño, distancia de la carga, sangrado, radio de 45 studs, Lentitud I = ×0,5, 1 s de interrupción).
- **Reanimaciones:** el proyecto aún no tiene mecánica de reanimar (solo existe `ReviveTime`). Cuando se añada, debe consultar `TaskManager.IsInterrupted(jugador)` para que el grito la cancele también.
- Retrato/icono de Shed.mov en el HUD y tema de persecución propio (`MusicData.ChaseThemes["Shedmov"]`): usa los de por defecto.

## Pruebas en Studio
1. Sale como Devilish (`/role killer` y selección de personaje) y aparecen 3 habilidades en las teclas 1-3 (y en los botones móviles).
2. Pasiva: lejos de los Toonflows el tema de tensión empieza a la mitad de distancia; al acercarte (≤ 25 studs, con visión) pasas a persecución: más rápido y con el radio completo.
3. Carga: impacta → daño y sangrado (ver `Bleeding` en los atributos); falla o choca con pared → queda inmóvil 1,2 s; con el ultimate activo **no** queda inmóvil.
4. Grito: un Toonflow manteniendo una tarea ve cerrarse la barra y no puede retomarla ~1 s; queda lento 3 s y resaltado 6 s a través de las paredes.
5. Ultimate: durante 15 s ningún aturdimiento (p. ej. cuernos de Deerphina) ni ralentización le afecta; ataca más rápido; al terminar vuelve todo a la normalidad.
