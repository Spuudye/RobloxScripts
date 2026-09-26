# eat test

Rojo project for the "eat test" place.

| Folder        | Shows up in Studio as                          |
|---------------|------------------------------------------------|
| `src/server`  | `ServerScriptService.Server`                   |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`    |
| `src/shared`  | `ReplicatedStorage.Shared`                     |

File suffixes decide the script type: `.server.lua` becomes a Script,
`.client.lua` becomes a LocalScript, and plain `.lua` becomes a ModuleScript.

## Syncing into Studio

1. Install Rojo (`rokit install` in this folder, or grab it from https://rojo.space).
2. Install the Rojo plugin in Studio (Plugins tab, or `rojo plugin install`).
3. In this folder run `rojo serve`.
4. Open the "eat test" place in Studio, open the Rojo plugin, and click **Connect**.

Edits to files in `src/` now appear in Studio live.
