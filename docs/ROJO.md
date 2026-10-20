# Rojo: cómo evitar que borre o duplique las GUI y los modelos

## Qué pasaba
El repo solo guarda **scripts**. Las GUI (ScreenGui con sus Frames) y los modelos de
`ReplicatedStorage` viven únicamente en el place.

1. Sin `$ignoreUnknownInstances`, Rojo borraba lo que no estaba en el repo (GUI y modelos).
2. Con `$ignoreUnknownInstances: true` solo en el servicio, las carpetas del repo
   (`GameGUI/`, `LobbyGUI/`...) se creaban como **Folder**. En el place esas instancias son
   **ScreenGui**: Rojo las ve como otra clase, así que crea una carpeta nueva con solo el
   script nuevo junto a la GUI original. `script.Parent` apunta entonces a un contenedor vacío.

## Qué cambia
- `default.project.json`: los servicios con `$path` llevan `$ignoreUnknownInstances: true`.
- Cada carpeta con scripts que en el place es otra clase lleva un `init.meta.json` con su
  `className` y `ignoreUnknownInstances: true`; así Rojo **adopta** la instancia existente y
  solo gestiona los scripts.

## Antes de conectar Rojo
1. Haz una copia del `.rbxl`.
2. Borra a mano los duplicados que dejó la prueba anterior (carpetas vacías con un solo script).
3. Pega `tools/verificar-clases-rojo.luau` en la barra de comandos de Studio y revisa que todo
   diga `OK` y que no haya duplicados. Si sale `DISTINTA`, corrige el `className` en el
   `init.meta.json` de esa carpeta: una clase equivocada hace que Rojo reemplace el original.
4. Comprueba que el script original dentro de cada GUI se llama igual que el archivo
   (`HUDController.client.luau` -> LocalScript `HUDController`); si no, Rojo creará un segundo.
5. Ejecuta `rojo serve` y revisa el diff que muestra el plugin antes de aceptar.

## Si añades una GUI nueva
Crea su carpeta con un `init.meta.json` (`ScreenGui`, `ignoreUnknownInstances: true`) antes de
poner scripts dentro.
