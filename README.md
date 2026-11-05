# pfUI-PaladinBar

A [pfUI](https://github.com/brues-code/pfUI) third-party module for paladins (WoW 1.12 / OctoWoW / Turtle WoW),
modelled on pfUI-TotemBar.

## Buttons
| Button | Left-click | Hover list |
| --- | --- | --- |
| **Aura** | cast the active aura | every aura you know |
| **Libram** | equip the active libram (relic slot) | librams in your bags / equipped |
| **Seal** | cast the active seal (timer = time left) | every seal you know |
| **Judgement** | see below | the seals: pick the one Judgement works with |

In every list: **left-click** casts / equips, **right-click** makes it the active one. Each list also has
**None** (red cross). Right-clicking a bar button pins its list open.

Aura and seal buttons are dimmed while that aura / seal is not on you.

## Judgement
The button shows the Judgement icon, and a small icon in the top right corner shows the seal chosen for it
(outlined while that seal is up on you, dimmed otherwise). Hover the button and click a seal in the list to
choose it (any click; the chosen one is outlined).

With *Cast the chosen seal first if it is not up* (default on), a click casts the chosen seal when it is not
active on you, and the next click casts Judgement. Turn it off to always cast Judgement directly.

## Commands
`/paladinbar` (alias `/ppb`)

| Command | Effect |
| --- | --- |
| `/paladinbar aura` / `seal` | cast the active one if it is not up (`force` = always) |
| `/paladinbar judgement` | same as clicking the Judgement button |
| `/paladinbar libram` | equip the active libram |
| `/paladinbar next\|prev <group>` | cycle aura / libram / seal / judgement seal |
| `/paladinbar set <group> <name\|none>` | e.g. `/paladinbar set judgement wisdom` |
| `/paladinbar list` / `scan` | show the selection / rescan spellbook and bags |

Key bindings: *Key Bindings → pfUI Paladin Bar*. For scripts: `pfPaladinBar.CastAura()`, `CastSeal()`,
`Judge()`, `EquipLibram()`, `SetActive("judgement", "wisdom")`.

Config: `/pfui` → Thirdparty → Paladin Bar.

pfUI's own stance bar (the one listing your auras) is hidden while the Paladin Bar is enabled. Untick
*Hide pfUI Stance Bar* in the config to get it back.

## Install
Copy the `pfUI-PaladinBar` folder into `Interface\AddOns`. Requires [pfUI](https://github.com/brues-code/pfUI).
