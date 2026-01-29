# Installation

## Requirements
- `oxmysql`
- `ox_lib`
- `ox_inventory`
- `ox_target`

## Folder Placement
Place the resource folder here:
- `resources/[L3GiT]/L3GiTOilRig`

## Start Order (`server.cfg`)
Ensure dependencies start before the resource:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure L3GiTOilRig
```

## Database (Persistence)
- Tables auto-create on first start (via `oxmysql`).
- Optional manual SQL: `sql/l3git_oilrig.sql`

Tables used:
- `l3git_oilrig_state` (legacy/shared state, kept for backwards compatibility)
- `l3git_oilrig_state_personal` (per-player rig state)
- `l3git_oilrig_names` (per-player rig names)

## Items (ox_inventory)
Configure item names in `config.lua`:
- `Config.FuelItem` (default: `rig_fuel`)
- `Config.BarrelItem` (default: `oil_barrel`)

Make sure those items exist in your `ox_inventory` item definitions.

### Item Images (NUI)
The UI tries to load images from:
- `nui://ox_inventory/web/images/<item>.(png|webp|jpg|jpeg)`

If you rename items, add matching images in `ox_inventory/web/images`.

## Configure
Edit `config.lua`:
- Branding: `Config.JobName`, `Config.NotifyTitle`, `Config.Ui.*`
- Locations: `Config.RigLocations`, `Config.FuelSupplier`, `Config.OilBuyer`
- Economy: `Config.FuelCost`, `Config.BarrelSellPrice`
- Storage/production: `Config.MaxFuelCansStored`, `Config.MaxBarrelsStored`, `Config.ProductionTime`

Optional:
- Set `Config.Debug = true` for extra client/server logs.

## Sanity Checklist
- Start the server and interact with:
  - Fuel Supplier NPC (shop UI)
  - Oil Buyer NPC (sell UI)
  - Rig control panel target (rig terminal UI)

If UI doesn’t open:
- Confirm the resource is started
- Confirm `ox_lib` / `ox_target` / `ox_inventory` are started
- Confirm `ui_page` and files list in `fxmanifest.lua`
