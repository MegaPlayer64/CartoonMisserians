# Resumen de la auditoría y orden de integración

Todas las ramas están **apiladas** (cada una contiene a la anterior) y `main` no se ha tocado.
Nada se ha ejecutado en Roblox Studio: solo se comprobó que la sintaxis de Luau compila.

## Orden recomendado
Lo más simple es un único PR desde la última rama. Para revisar por partes (y poder revertir),
abre cada PR contra la rama anterior y mézclalos en este orden:

| # | Rama | Qué contiene |
|---|---|---|
| 1 | `fix/seguridad-criticos-altos` | Comandos de debug solo para devs (`DevAuth`), dueño de cada habilidad (`AbilityOwnership`), saneo de `targetData`, rate limit, persistencia (`PlayerData`), módulos de servidor fuera de `ReplicatedStorage`. |
| 2 | `fix/errores-medios` | `ResetSpeedMultiplier` respeta stun/buffs, `TaskManager` solo para Toonflows vivos, maestría (TotalMatches y logros), sangrado, remotes antiguos como `.model.json`. |
| 3 | `fix/matchmanager` | Cartel de ganador, `pcall` en el bucle de partidas, limpieza de la salida, mapa inexistente, LMS. |
| 4 | `fix/abilityframework-y-escape` | `Execute` reembolsa si falla; el Toonflow que escapa es invulnerable y va a zona segura. |
| 5 | `fix/rojo-mapeo-gui` | `init.meta.json` por contenedor + `$ignoreUnknownInstances`, verificador de clases. **Pruébala antes de sincronizar nada con Rojo.** |
| 6 | `fix/cliente-habilidades-hud` | `AbilityLoadouts`, HUD (reloj de salida, tareas, aliados), ceguera, tienda, debug, `Bars`. |
| 7 | `feat/controles-moviles` | Botones táctiles (habilidades, ataque, sprint) y puntería por cámara. |
| 8 | `fix/auditoria-final-cliente` | Selección de personaje responsive, intro, pesca (teclas W/S y streaming). |
| 9 | `fix/habilidades-deerphina-stan-mariposaurio` | Habilidades de los tres personajes, `StatsModule.Stun`, pasiva y láser de Stan. |
| 10 | `fix/pesca-obstaculos` | Basura y peligros del minijuego de pesca no se dibujaban. |

## Antes de empezar
1. Copia del `.rbxl`.
2. Rojo: borra los duplicados de la prueba anterior y ejecuta `tools/verificar-clases-rojo.luau` (ver `docs/ROJO.md`).
3. Studio → Game Settings → Security → "Enable Studio Access to API Services" (DataStore).
4. Pon tu UserId en `DEV_USER_IDS` (`ServerModules/DevAuth.luau`).

## Pruebas en Studio por área
**Seguridad y datos**
- Las monedas y emotes comprados sobreviven a salir y volver a entrar; `MasteryData` también.
- En Studio todos están autorizados (`IsStudio`): la restricción de los comandos solo se puede probar en un servidor publicado con una cuenta que no esté en `DEV_USER_IDS`.

**Partida (`MatchManager`)**
- El cartel final dice quién ganó de verdad (Toonflows / Devilish).
- Una partida completa: tareas → salida abierta → escape. El Toonflow que escapa va a la zona segura, no recibe daño y no puede usar habilidades ni tareas.
- Se agota el tiempo sin tareas: gana el Devilish al instante.
- Fuerza un error en una fase (p. ej. renombrar `Workspace.Maps` en pruebas) y comprueba que el servidor se recupera y empieza otra partida.
- Dos partidas seguidas en el mismo mapa: la puerta de salida empieza cerrada y no hay efectos de la anterior.

**Habilidades** (para cada uno de los 9 personajes)
- Las teclas 1-4 lanzan la habilidad que muestra el HUD.
- Con el cooldown en marcha, un fallo (sin objetivo, sin galletas) **no** lo consume.
- Deerphina: la embestida sobre el Devilish termina y no deja fuerza residual; Stan: `CambioArma` activa el láser (M1), la pasiva deja rastro cada 20 s; Mariposaurio: `Boo!!` no teletransporta a un Toonflow que ya escapó.
- Dos aturdimientos seguidos sobre el Devilish no lo dejan inmóvil.

**HUD y cliente**
- Cuenta atrás de la salida: baja sin reiniciarse a 01:00 y desaparece al cerrarse.
- El Devilish no ve el contador de tareas; el Toonflow no ve al Devilish en "aliados".
- Tienda: comprar/equipar varias veces no ralentiza; la música de persecución no se corta cada 5 s.

**Móvil** (Test → Device; toca una vez para activar)
- Sin solapes entre la cuadrícula de habilidades, el salto y el botón de emotes (ajusta `JUMP_CLEARANCE` / `EDGE_MARGIN`).
- Habilidades apuntan hacia la cámara; ATACAR (Devilish) repite al mantener; CORRER es un interruptor.
- El panel de selección de personaje cabe en pantalla y se cierra tocando fuera.

**Pesca**
- Aparecen peces (verde), basura (marrón) y peligros (rojo) y todos se ven.
- W/S solo mueven el gancho; la máquina sigue funcionando tras alejarte y volver (streaming).

## Pendiente / decisiones de diseño
- Móvil: controles de movimiento y salto son los de Roblox (`StarterPlayer.DevTouchMovementMode`).
- Victoria: todos derribados (sin escapados) da la victoria al Devilish sin esperar el desangrado; un escapado + resto derribados da victoria a los Toonflows.
- Rotación de roles y modo espectador: fase de pulido.
- `DeadHope`: `REQUIRE_DEAD_TOONFLOW = false` por ahora (ver `MariposaurioAbilities.luau`).
- Revoca el token de GitHub que se compartió en el chat.
