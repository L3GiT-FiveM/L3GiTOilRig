L3GiTOilRig — Playground Oil Rig

Overview
--------
L3GiTOilRig is a FiveM resource that adds an oil-rig / pumpjack style job loop with a custom NUI “terminal” UI, a Fuel Supplier NPC shop UI, and an Oil Buyer NPC.

Core loop:
1) Buy diesel cans from the Fuel Supplier.
2) Add fuel to a rig (1 gal per can, stored at the rig).
3) Start a production cycle (consumes 3 gal).
4) Wait for production to finish.
5) Collect produced oil barrels and sell them to the Oil Buyer.

The resource is server-authoritative for fueling, production, and inventory changes.


Requirements / Dependencies
--------------------------
This resource is built around the ox ecosystem.

Required:
- ox_lib
- ox_target
- ox_inventory
- oxmysql

Notes:
- SQL persistence requires oxmysql to be installed and running.
- Inventory and money use ox_inventory.


Installation
------------
1) Place the folder `L3GiTOilRig` into your server resources directory, for example:
   resources/[L3GiT]/L3GiTOilRig

2) Ensure dependencies are started BEFORE this resource.
   In your server.cfg (order matters):

   ensure oxmysql
   ensure ox_lib
   ensure ox_inventory
   ensure ox_target
   ensure L3GiTOilRig

3) Restart your server, or start the resource:
   - In console: `ensure L3GiTOilRig`


Configuration
-------------
Main config is in: config.lua

Key settings:
- Config.Debug
  Enable extra server logging.

- Inventory items:
  Config.FuelItem   = 'rig_fuel'
  Config.BarrelItem = 'oil_barrel'

- Economy:
  Config.FuelCost        = 2000
  Config.BarrelSellPrice = 30000

- Fuel rules:
  Config.MaxFuelCansStored   = 9     (rig tank capacity)
  Config.MaxFuelCansPerCycle = 3     (fuel used per cycle)

- Production:
  Config.ProductionTime = 30 * 60 * 1000   (30 minutes per cycle)

- Yield mapping:
  Config.FuelToYield = {
      [3] = { barrels = 1, label = '3 gal → 1 barrel' },
  }

- Storage:
  Config.MaxBarrelsStored = 10

- Locations:
  - Config.RigLocations
  - Config.FuelSupplier
  - Config.OilBuyer

If you add more rigs:
- Duplicate the entry in Config.RigLocations.
- Each rig MUST have a unique `id`.
- Optional: set `legacyId` if you previously used older IDs and want to migrate saved progress.


Gameplay Rules (Current)
-----------------------
Rig fuel:
- Fuel is added 1 at a time.
- Rig tank max: 9.

Starting production:
- Manual start.
- Requires at least 3 fuel in the rig tank.
- Consumes 3 fuel per cycle.

Production time:
- 30 minutes per cycle.

Yield:
- 3 fuel → 1 barrel (per Config.FuelToYield).

Storage:
- Barrels are stored at the rig up to 10.
- Collecting transfers ALL stored barrels at once (if the player can carry them).

Auto-continue:
- After a cycle completes, the script will automatically start another cycle if:
  - there is enough fuel, and
  - storage is not full.


NPC UIs
-------
Fuel Supplier:
- Has a “job brief” style UI and a shop screen.
- Shop uses the ox_inventory item image for the fuel item.
- Buy action is server-authoritative and enforces a hard inventory cap:
  - Max 9 diesel cans in player inventory.

Oil Buyer:
- Used to sell oil barrels.


Persistence (oxmysql)
---------------------
If oxmysql is available, the resource persists:
- Rig state (fuel, running flag, start/end timestamps, barrels ready, last fuel used)
- Per-player rig names (your custom rig name is only visible to you)

Tables are created automatically on resource start:
- l3git_oilrig_state
- l3git_oilrig_names

Timer / restart behavior:
- Production uses saved timestamps.
- On a resource restart, rigs resume with the remaining time (the cycle does not restart from 30:00).
- If a cycle finished while the resource/server was down, it will complete on load and then auto-continue if possible.


Items
-----
You must have these items defined in your ox_inventory items, matching config.lua:
- rig_fuel   (diesel can)
- oil_barrel (produced barrel)

Money handling:
- Purchases and sales use ox_inventory’s money item (typically `money`).


Blips / Map
-----------
Client creates blips for:
- Fuel Supplier
- Oil Buyer
- Oil Rigs

Rig blip name:
- The rig blip label matches the player’s saved custom rig name (client-side per player).


Controls / Interaction
----------------------
Interaction is via ox_target:
- Target the rig to open the rig terminal UI.
- Target the Fuel Supplier NPC to open the supplier UI.
- Target the Oil Buyer NPC to sell barrels.

Inside the rig UI:
- Add Fuel
- Start Cycle
- Collect (collects all stored barrels)
- Rename Rig (name is personal / per player)

Inside the supplier UI:
- Open Shop
- Buy diesel can


Troubleshooting
---------------
1) SQL persistence not working
- Ensure oxmysql is installed and started before L3GiTOilRig.
- Check server console for:
  "oxmysql is not available; SQL persistence disabled."

2) UI not opening
- Ensure `ui_page` and `files` are present in fxmanifest.lua.
- Ensure NUI files exist:
  html/index.html
  html/terminal.css
  html/script.js

3) Shop image not showing
- Confirm the fuel item name in config.lua matches your ox_inventory item name.
- The UI loads images from:
  nui://ox_inventory/web/images/<item>.(png/webp/jpg/jpeg)

4) Fuel won’t add / start won’t work
- You need the `rig_fuel` item to add fuel.
- Start requires 3 fuel stored in the rig.
- If the rig storage is full (10/10), you must collect barrels first.


File Layout
-----------
- fxmanifest.lua
- config.lua
- client/main.lua
- server/main.lua
- server/persistence.lua
- html/index.html
- html/terminal.css
- html/script.js


Version
-------
Resource version is listed in fxmanifest.lua.


Notes
-----
- This README describes the current configured defaults. If you change config.lua values, the gameplay loop (costs, yields, timing) changes accordingly.

