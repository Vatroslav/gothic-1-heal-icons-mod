# Gothic 1 Remake: Health & Mana Icons

A small script-only mod for Gothic 1 Remake: every inventory item that restores Health gets the game's red Health icon in the top-right corner of its slot, and every item that restores Mana gets the blue Mana icon. Items that restore both show both. You can tell food, herbs and potions apart at a glance instead of hovering each one.

Nothing about the items changes: same effects, same values.

Settings in `Settings > Game > Health & Mana Icons`:

| Setting | Values | Default |
|---|---|---|
| Icon size | 12 to 48 | 24 |

## How it works

When the inventory opens, the mod reads every item's consume effects, the same data the game's AI reads when it chooses what to drink or eat. A positive Heal amount means Health, a positive Mana amount means Mana; items that only raise maximum Health or Mana, or only hurt, get no icon. Each inventory slot is matched to its item by name, and the icons are added on top of the slot's own picture. The icons are the game's own Health and Mana symbols, tinted red and blue.

## Install

1. Copy the `HealthManaIcons` folder to `G1R/Mods` in the game's install folder.
2. Enable the mod in the game's mod manager (launch option `-ModManagementUI`).

No UE4SS or other loader is needed. Loading an older save shows the game's different-modlist warning, as with any mod.

This is an unofficial modification. It is not made, endorsed or supported by THQ Nordic.
