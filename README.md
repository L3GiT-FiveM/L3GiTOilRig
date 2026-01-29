# L3GiTOilRig

Modular oil rig job for FiveM with a terminal-style NUI, a Fuel Supplier NPC, an Oil Buyer NPC, and per-player persistence.

## Features
- Rig terminal UI: fuel, status, time remaining, storage, collect, start cycle
- Fuel Supplier NPC: buy fuel cans
- Oil Buyer NPC: sell produced barrels
- Per-player saving:
  - rig fuel/state/timers
  - produced barrels
  - personal rig name (visible only to that player)

## Requirements
- `oxmysql`
- `ox_lib`
- `ox_inventory`
- `ox_target`

## Installation
1. Place the folder in your resources:
   - `resources/[L3GiT]/L3GiTOilRig`

2. Ensure start order in `server.cfg`:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure L3GiTOilRig
```

3. Configure locations/economy in `config.lua`.

## How It Works (Gameplay Loop)
1. Buy fuel cans from the Fuel Supplier NPC.
2. Use the rig control panel target.
3. Add fuel (1 can = 1 gallon).
4. Start a production cycle (uses `Config.MaxFuelCansPerCycle`, default 3 gallons).
5. When the cycle finishes, barrels become available.
6. Collect barrels to your inventory.
7. Sell barrels to the Oil Buyer NPC.

## Configuration
Edit `config.lua`.

Common settings:
- Branding/UI: `Config.JobName`, `Config.NotifyTitle`, `Config.Ui.*`
- Items/economy: `Config.FuelItem`, `Config.BarrelItem`, `Config.FuelCost`, `Config.BarrelSellPrice`
- Production: `Config.MaxFuelCansPerCycle`, `Config.ProductionTime`, `Config.FuelToYield`
- Storage: `Config.MaxFuelCansStored`, `Config.MaxBarrelsStored`
- Locations: `Config.RigLocations`, `Config.FuelSupplier`, `Config.OilBuyer`
- Placement: `Config.RigZOffset`

Defaults (from config):
- Fuel item: `rig_fuel`
- Barrel item: `oil_barrel`

## Items / ox_inventory Images
- The NUI attempts to load item images from `ox_inventory`:
  - `nui://ox_inventory/web/images/<item>.(png|webp|jpg|jpeg)`
- If you rename items, ensure the matching image exists in your `ox_inventory/web/images` folder.

## Persistence (SQL)
- Saved via `oxmysql`.
- Tables auto-create on resource start.
- Optional manual SQL: `sql/l3git_oilrig.sql`

Tables used:
- `l3git_oilrig_state` (legacy/shared state, kept for backwards compatibility)
- `l3git_oilrig_state_personal` (per-player rig state)
- `l3git_oilrig_names` (per-player rig names)

## Debug
Set `Config.Debug = true` to print extra debug logs (client + server).

## Troubleshooting
- UI not opening:
  - verify the resource is started
  - verify `ox_lib`, `ox_target`, `ox_inventory` are started
  - verify `ui_page` and file list in `fxmanifest.lua`
- No persistence:
  - ensure `oxmysql` starts before this resource
  - check your SQL permissions

## Extra Docs
- Install steps: `INSTALLATION.md`
- Script overview (plain text): `explanation.txt`
