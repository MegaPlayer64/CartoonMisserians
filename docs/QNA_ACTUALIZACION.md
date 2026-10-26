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

## Pendiente: necesito que lo confirmes
### 1. Tiempo de salida según las tareas
Hoy la salida **se abre al completar las 6 tareas y dura 70 s fijos**; si se agotan los 300 s antes, gana el Devilish. "Cada tarea purificada reduce el temporizador global (de 0:50 a 1:10 si se completan todas)" admite varias lecturas:
- **A.** Hay un temporizador de cierre global que arranca desde el principio y **cada tarea lo acorta**; al completarlas todas la salida se abre y quedan entre 0:50 y 1:10.
- **B.** La salida se abre al completar las tareas, pero **su duración abierta** va de 0:50 (pocas tareas / más salidas) a 1:10 (todas).
- **C.** Otra (dime cuál).
Necesito: ¿qué mide exactamente el 0:50–1:10 y en qué sentido va (más tareas = más o menos tiempo)? ¿Depende del número de salidas?

### 2. Calificación y "Maldad"
La lista que mencionaste (SUPER F, B, A, SS+) parece incompleta. Necesito: **la escala completa** de notas, **qué mide cada nota** (¿tareas, supervivencia, escape, daño, eliminaciones? ¿distinto para Killer y Toonflows?), **cuánta Maldad da cada nota**, y **quién la gana** (¿solo el Killer o todos?). Hay métricas que hoy no se registran (daño, eliminaciones): habría que añadirlas.
También: ¿cuánta Maldad cuesta jugar/seleccionar un Killer, y desde dónde se gasta (pantalla de selección)?

### 3. LMS: temporizador de cierre
"Forzar entre 1:10 y 1:50 máximo": propongo **`restante = clamp(restante, 70, 110)`** (si quedan más de 1:50 se baja a 1:50; si quedan menos de 1:10 se sube a 1:10). ¿Es esa la intención, o solo hay que *recortar* a 1:50 sin alargar? ¿Y qué temporizador es: el global de 5:00 o el de la salida abierta?
