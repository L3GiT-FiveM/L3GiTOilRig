# L3GiTOilRig

Advanced Oil Rig w/ a NUI terminal UI + Fuel supplier + Oil buyer.

## Requirements
- `ox_lib`
- `ox_target`
- `ox_inventory`
- `oxmysql`

## Install
1. Place the resource folder:
   - `resources/[L3GiT]/L3GiTOilRig`
2. Ensure start order in `server.cfg`:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure L3GiTOilRig
```

## Configure
Edit [config.lua](config.lua).

Most common:
- Branding/UI text: `Config.JobName`, `Config.NotifyTitle`, `Config.Ui.*`
- Economy/items: `Config.FuelItem`, `Config.BarrelItem`, `Config.FuelCost`, `Config.BarrelSellPrice`
- Production: `Config.MaxFuelCansPerCycle`, `Config.ProductionTime`, `Config.FuelToYield`
- Storage: `Config.MaxFuelCansStored`, `Config.MaxBarrelsStored`
- Locations: `Config.RigLocations`, `Config.FuelSupplier`, `Config.OilBuyer`
- Rig placement: `Config.RigZOffset` (if the rig model is floating)

## Debug
Set `Config.Debug = true` to print extra debug logs (client + server).

## Persistence (SQL)
Rig state + per-player rig names save via oxmysql.

Tables auto-create:
- `l3git_oilrig_state`
- `l3git_oilrig_names`

Optional manual SQL: [sql/l3git_oilrig.sql](sql/l3git_oilrig.sql)

## Notes
- Fuel supplier purchase clamps so players can’t hold more than 9 fuel cans total.
- Oil buyer quantity clamps to what the player has.

## Troubleshooting
- Callback error / UI opens but shows errors: restart the resource after changes.
- No persistence: make sure `oxmysql` starts before this resource.
- UI not opening: verify `ui_page` and file list in [fxmanifest.lua](fxmanifest.lua).

