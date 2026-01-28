# L3GiTOilRig

Advanced Oil Rig Job w/ a NUI terminal UI + fuel supplier + oil buyer.

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


<img width="664" height="482" alt="image" src="https://github.com/user-attachments/assets/343a962c-1194-4c9e-bac7-92e035d9ba2c" />
<img width="366" height="387" alt="image" src="https://github.com/user-attachments/assets/33e6f23d-154a-4716-8a3a-69fc419c1f29" />
<img width="365" height="458" alt="image" src="https://github.com/user-attachments/assets/84815571-8820-4407-a956-9025dc94b0cb" />
<img width="358" height="429" alt="image" src="https://github.com/user-attachments/assets/eb589c3e-4dce-4333-8f53-b2eb4d1c3935" />




