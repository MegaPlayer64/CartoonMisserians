# Actualización de diseño (QNA): estado y decisiones pendientes

## Hecho
| Regla | Implementación |
|---|---|
| **Sin salto** | `default.project.json` (StarterPlayer `CharacterJumpPower/Height = 0`), `NoJump.server.luau` (fuerza 0 y desactiva el estado `Jumping` en cada personaje, incluidos los clones de `Characters/`), `Bars` ya no reescribe `JumpPower` por stamina. Desactivar `Jumping` además oculta el botón de salto táctil de Roblox *(no lo he podido verificar en un móvil)*. |
| **Móvil sin hueco de salto** | `MobileControls`: se elimina `JUMP_CLEARANCE`; ATACAR en la esquina inferior derecha, CORRER encima (o en la esquina si no hay ataque) y las habilidades a su izquierda. |
| **1-3 salidas según tamaño** | `MatchConfig.ExitsByCategory` (Chico 1, Mediano 2, Grande 3). `MatchManager` lee los Models de salida de `Mapa/Exits/*` (si no existe esa carpeta, usa la salida única heredada `Exit`/`ExitDoor`), elige al azar tantas como le tocan al tamaño y conecta un `Touched` por salida. Todas se abren y cierran juntas. |
| **El Devilish elige mapa entre 3 (Chico/Mediano/Grande)** | **Ya existía** (`MapSelection`, 15 s). Ahora cada opción incluye `ExitCount` y `RecommendedKillers`, y `MapVoteClient` los muestra (y el panel cabe en móviles apaisados). |
| **Moneda "Maldad"** | `PlayerData`: campo `maldad` (guardado en DataStore), atributo `Maldad`, `PlayerData.addMaldad(jugador, cantidad)` y `getMaldad`. **Aparte** de los Cartoonsitos (`Coins`), que no cambian. |
| **LMS: música** | `MusicManagerClient` escucha `LMSActivated` y reproduce `MusicData.LMS[skin/personaje/"Default"]` hasta terminar la partida. |
| **Punto único de la duración de salida** | `MatchManager.computeExitDuration()` (hoy devuelve `ExitOpenDuration`, 70 s). |

## Cómo preparar los mapas (en el place)
- Añade a `Workspace/Maps/<Mapa>` una carpeta **`Exits`** con un Model por salida (cada uno con su parte `Trigger`).
- Registra cada mapa en `MatchConfig.AvailableMaps` con `Category` (`"Pequeño"`, `"Mediano"`, `"Grande"`) y `RecommendedKillers = { "Shedmov", "Stan.oma.png" }` (nombres canónicos de `CharacterDatabase`).
- Para que salgan 3 opciones (una por tamaño) hace falta al menos un mapa de cada tamaño; si falta uno, `MapSelection` rellena con otros.

## Temporizador de salida (confirmado: lectura A)
Partida de ~5 min. Valores en `MatchConfig.ExitTiming` / `LMSDuration`; lógica en `MatchManager` (`computeExitOpenAt`, `computeExitDuration`, `openExit`, `shortenExit`, `applyLMSTimer`).

| | Sin tareas | Con todas las tareas |
|---|---|---|
| **Se abre en el segundo…** | 240 (último minuto) | 120 (hasta 2:00 antes); cada tarea adelanta 20 s |
| **Dura abierta** | 0:50 | 1:10 |

- La salida **se abre sola** cuando llega su hora: completar tareas ya no la abre al instante, solo la adelanta (si ya pasó la hora, se abre enseguida). Esto sustituye a la decisión anterior de "tiempo agotado sin tareas = gana el Devilish": ahora siempre hay salida en el último minuto.
- El reloj del HUD cuenta hasta la apertura y se actualiza al momento con cada tarea.
- **LMS** (queda un Toonflow en pie): la partida se acorta según el arquetipo del último superviviente: **Sentinel 1:50** (Trunks, Toby), **Survivalist 1:30** (Brothercat), **Support 1:10** (Deerphina, Takorita). Si la salida aún no se abrió, se abre dejando al menos 0:50 de ventana antes del final; si ya está abierta, se acorta a ese tiempo. Solo acorta, nunca alarga.
- Los arquetipos están en `CharacterDatabase` (`Archetype`). **Brothercat = Survivalist es mi suposición.**

## Calificación y Maldad (infraestructura lista, DESACTIVADA)
`MatchScoring.Enabled = false`: mientras esté apagada no se calcula nada, no se reparte Maldad y el panel de resultado no aparece. Los pesos y umbrales de `MatchScoring.luau` son una **propuesta** para probar:

| Métrica (de la dirección) | Estado | Puntos propuestos |
|---|---|---|
| Stuns dados | recogida (solo habilidades que pasan `params.Player`: hoy Deerphina) | 8 c/u |
| Supervivientes curados (distintos) | recogida (hoy Deerphina) | 10 c/u |
| Escapes de persecución | **pendiente** (falta un detector de persecuciones) | 15 c/u |
| Supervivientes salvados de una persecución | **pendiente** | 20 c/u |
| Habilidades usadas (solo Survivalist) | recogida (todas las habilidades) | 2 c/u |
| Escapar | recogida | +40 |
| Caer / morir | recogida | +15 (consuelo) |
| *Mi propuesta:* tareas purificadas | recogida | 5 c/u |
| *Mi propuesta:* victoria del equipo | recogida | +20 |
| **Killer:** derribos / eliminaciones | recogidas | 15 / 30 c/u |
| **Killer:** habilidades usadas | recogidas | 4 c/u |
| **Killer:** victoria | recogida | +30 |

Notas: 9 notas de SUPER F a SS+ (SUPER F, F, D, C, B, A, S, SS, SS+) con umbrales 0/10/25/45/70/100/140/190/250 puntos y Maldad 1/3/6/10/15/22/30/40/50. Todo está en `MatchScoring.luau`.

**Pendiente de ampliar:** (a) detector de persecuciones (escapes y rescates) — propuesta: persecución = un Toonflow a ≤ 25 studs del Devilish con línea de visión (el mismo criterio que usa la pasiva de Shed.mov); escape = la persecución termina sin que lo derriben tras ≥ 5 s; rescate = otro Toonflow aturde o interrumpe al Devilish mientras persigue a un aliado. (b) El resto de habilidades (Toby, Takorita, Trunks, Brothercat...) deben pasar `params.Player` a `StatsModule.Stun`/`ApplyHeal` para que sus stuns y curaciones cuenten.

**Falta decidir:** cuánta Maldad cuesta jugar/seleccionar un Killer y desde qué pantalla se gasta.

## Quién es el Killer: Maldad y opción para desactivarlo (confirmado)
- **Regla:** el jugador con **más Maldad** entre quienes pueden ser Killer es el candidato; los empates se sortean. Al empezar su partida como Killer su Maldad **se gasta y vuelve a 0**, para que el puesto rote (su calificación de esa partida volverá a subirla).
- **Opción "Poder ser Killer"** (`KillerOptIn`, guardada en `PlayerData`): si se desactiva, el jugador nunca es candidato. **Única excepción:** si *nadie* quiere ser Killer se elige entre todos, para que la partida pueda empezar.
- Código: `KillerSelection` (servidor), `PlayerData.setKillerOptIn / resetMaldad`, `KillerOptionsServer` (remote `SetKillerOptIn`), y `KillerOptionClient` (panel provisional con engranaje, muestra tu Maldad y el candidato actual).
- El reinicio de Maldad ocurre al **empezar** la partida, no al asignar el rol: si la partida se cancela antes, no se cobra.
- **Para tu UI de Opciones:** lee el atributo `KillerOptIn` del jugador (nil o `true` = puede ser Killer) y cambia con `Remotes.SetKillerOptIn:FireServer(true | false)`.
- **Ojo:** el botón "Options" que ya existe en el lobby abre hoy el **menú de depuración** (hitboxes). Conviene limitarlo a desarrolladores o reutilizarlo para unas opciones de verdad.
