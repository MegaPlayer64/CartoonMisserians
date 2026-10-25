# Controles móviles

## Qué había (y por qué "no funcionaban")
- **No existían botones de habilidades ni de sprint**: `MovileButtons` solo mostraba un contenedor
  (`M1Button` / `SprintButton`) sin ninguna lógica conectada.
- **Cualquier toque en pantalla lanzaba un ataque melee** (`CombatClient`), también al arrastrar
  para girar la cámara.
- **La puntería de habilidades usaba `Mouse.Hit`**, que en táctil es el punto bajo el último toque
  (p. ej. el propio botón): las habilidades salían hacia puntos aleatorios.
- El sprint solo existía con Shift o gamepad.

## Qué hay ahora (`MobileControls.client.luau`)
| Botón | Qué hace |
|---|---|
| 1-4 (cuadrícula a la izquierda del salto) | Habilidades del personaje (`AbilityLoadouts`), con cuenta atrás de cooldown. |
| ATACAR (solo Devilish) | Mantener pulsado repite el ataque. |
| CORRER | Interruptor. Corre mientras te mueves y queda stamina. |

- Puntería táctil: hacia donde mira la **cámara** (40 studs, bajando al suelo). Con teclado/ratón
  todo sigue igual que antes.
- Se muestran solo cuando el último input es táctil; en tablets/portátiles con teclado se ocultan.
- Respeta el área segura (notch) y se escala con la pantalla.
- Los botones se ocultan al escapar (zona segura) y fuera de partida (el sprint se queda).
- Los botones antiguos de `ActionContainer` se ocultan; borra `M1Button`/`SprintButton` de tu GUI
  si no los vas a usar.

## Cómo probar
1. Studio -> pestaña Test -> Device -> elige un teléfono; toca una vez la pantalla.
2. O, con el juego en marcha, en el cliente:
   `game.Players.LocalPlayer:SetAttribute("ForceMobileControls", true)`
3. Entra en una partida de prueba y comprueba habilidades, cooldowns, ataque y sprint.

## Ajustes
Las constantes de diseño (tamaños, márgenes, `JUMP_CLEARANCE`, colores) están arriba de
`MobileControls.client.luau`. Si el botón de emotes u otro elemento del HUD se solapa con los
botones, mueve la cuadrícula cambiando `JUMP_CLEARANCE`/`EDGE_MARGIN`.
