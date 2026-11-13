# RobloxScripts

## Dig Game: terrain digging system

A "dig to find loot" system built on Roblox **Terrain**. You swing a shovel to carve holes, loot sits buried at different depths, you sell it at a pad and buy better gear.

**Features**
- Generates a terrain pit with 5 layers: Topsoil → Clay → Stone → Deep Slate → Magma Core, with bedrock below and an undiggable border around it.
- Shovel tool: click (or hold) on terrain to dig. Hard layers need a better shovel, cost more stamina and make smaller holes.
- Buried loot (20 items, 5 rarities). It exists **only on the server** until it's dug up, so exploiters can't scan for it.
- Blue diamond **loot detector** marker with the distance (`28m`) to your nearest buried item.
- HUD: cash, hint/toast line, backpack `8/10`, stamina bar, depth meter + layer name, a dig ring that turns red when you can't dig there.
- Green **SELL LOOT** pad, **Shovel** and **Backpack** upgrade buttons, and an **⬆ Surface** button for getting out of deep holes.
- Juice: dirt chunks + dust on every dig, loot pops out and flies into you, button bounce.
- Saves Cash, upgrades and backpack (DataStore with retries; never overwrites data after a failed load).
- The dig site resets every 30 min (configurable), and loot restocks every 20 s.

### Install: option A, drag and drop (no tools)
1. Download `build/DigGame.rbxmx` and drag it into Studio. Three folders appear.
2. Move them:
   - `DigShared` → **ReplicatedStorage**
   - `DigServer` → **ServerScriptService**
   - `DigClient` → **StarterPlayer › StarterPlayerScripts**
3. (Optional) Add an anchored Part named **`DigZone`** where the pit should go. Its top face becomes the ground surface and its X/Z size becomes the diggable area. Without it, the pit is 192×192 studs centered at (0, 0, 0).
4. (Optional, for saving in Studio) Game Settings › Security › **Enable Studio Access to API Services**.
5. Press **Play**.

### Install: option B, Rojo
`rojo serve` in this folder, then connect from the Rojo plugin. `default.project.json` maps the three folders above.

### Testing in Studio
- On Play, Output prints `[DigTests] all 9 tests passed` and `[Dig] dig site ready`.
- QA chat commands (Studio, or the place owner only): `/cash 5000`, `/fill` (fill backpack), `/maxshovel`, `/stamina`, `/resetdig`.
- Test checklist: dig down through each layer → the rusty shovel gets "Stone is too hard" at 56m → `/cash 200` → buy Iron Shovel → keep digging → fill the backpack → sell on the pad → press Surface.

### Tuning
Everything is in `src/shared/DigConfig.luau`: layer depths/colors/hardness, shovel and backpack tiers/prices, stamina, loot tables and values, detector range, reset interval.

### Layout
| File | Runs on | Role |
|---|---|---|
| `src/shared/DigConfig.luau` | both | All tunables + types |
| `src/shared/DigLogic.luau` | both | Pure logic (layers, radius, cost, loot roll) |
| `src/shared/DigLogicTests.luau` | server (Studio) | Self-tests for DigLogic |
| `src/shared/LootVisuals.luau` | both | Builds loot item parts |
| `src/server/Main.server.luau` | server | Boot order |
| `src/server/DigWorld.luau` | server | Terrain generation, buried/exposed loot |
| `src/server/DigService.luau` | server | Remotes, validation, tool, sell, upgrades, stamina, detector |
| `src/server/PlayerData.luau` | server | DataStore load/save |
| `src/client/Main.client.luau` | client | HUD, input, effects, marker |

Rebuild the drag-and-drop file after editing: `python3 tools/build_rbxmx.py`.
