# Details! Damage Meter for Conquest of Azeroth

This repository holds the Details! Damage Meter addon for World of Warcraft 3.3.5 (Wrath of the Lich King), with fixes for [Conquest of Azeroth](https://github.com/Conquest-of-AzerothCore/azerothcore-wotlk-coa). It includes the main Details addon and all 12 of its plugins.

The addon still works on a standard 3.3.5 server. The Conquest of Azeroth (CoA) changes turn on only when the CoA server needs them.

## What this version changes

- **Credits script summons to their owners.** CoA spawns many pets and helpers from server scripts, so the combat log never reports who summoned them. Without this fix, Details shows them as separate enemies or drops their damage. The addon now assigns these units to their owners, including:
  - Tinker mechs and pets
  - The Cultist Tentacle of C'Thun
  - Eldritch Command helpers
  - Necromancer pets
- **Shares pet owners with your group.** The combat log marks the units you own, so your own summons always count. For a teammate's script summons, the log shows only that the unit belongs to someone in your group, not who. Each copy of this version tells the rest of your party or raid which units belong to its player, so your copy learns the owners from teammates who run it too. For more information, see [Teammates without this version](#teammates-without-this-version).
- **Shows pet ability names.** Some CoA pets deal damage through helper spells that carry the pet's name, so the breakdown shows entries like "Tentacle of C'Thun (Tentacle of C'Thun)." The addon watches which ability the pet casts right before each hit and shows the real ability instead, for example "Mental Assault (Tentacle of C'Thun)." It accepts a name only after several matching casts, and it rejects a name if casts ever disagree.
- **Fixes the `tabela_pets` error** in the Details_TimeLine plugin.
- **Fixes an error in absorb handling** that repeated many times in each fight.
- **Reduces slowdown in long sessions.** The addon clears caches that grew without limit, and the errors that repeated during combat are gone.

## Install

1. Download the zip from the [latest release](https://github.com/TheLastDarkthorne/Details-CoA/releases/latest).
1. Exit the game.
1. Delete any existing `Details` and `Details_*` folders from your `Interface\AddOns` folder.
1. Extract the zip into `Interface\AddOns`. Each addon gets its own folder, such as `Interface\AddOns\Details`.
1. Start the game.

## Pet ability names setting

To switch pet ability names on or off, open a player's breakdown window, open its options, and find **Show Pet Ability Names [CoA]** in the **Group Pet Spells** section. An orange asterisk marks it as a CoA feature.

When the setting is off, every spell shows the name the game gives it.

## Commands

| Command | What it does |
|---|---|
| `/details coapets` | Lists units without a known owner and the pet ability names learned so far. |
| `/details coapets reset` | Clears the learned pet ability names, so the addon learns them again. |
| `/details coapets names on` | Turns pet ability names on. |
| `/details coapets names off` | Turns pet ability names off. |

## Known limits

- The addon can't count damage or healing that the server never writes to the combat log.
- If one helper spell serves several different abilities, the addon can't split its damage between them, and it keeps the game's name for that spell.

### Teammates without this version

If a teammate doesn't run this version, the addon falls back to the original Details method and reads the summon's tooltip for an owner name. If the tooltip doesn't name an owner, then that summon's damage and healing don't count toward the teammate's total.

This gap affects only:

- Summons that CoA spawns from server scripts. Pets that the server summons the normal way, such as a hunter's pet, count for everyone.
- The summons' damage and healing. Spells that the teammate casts still count.

The original Details has the same gap, so your results are never less accurate than before. To see which group units have no known owner, type `/details coapets`.

## Credits

Details! Damage Meter is by Terciob. This repository changes only what Conquest of Azeroth needs.
