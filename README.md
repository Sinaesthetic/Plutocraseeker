# Plutocraseeker

Plutocraseeker is a Mists of Pandaria Classic addon for tracking wanted raid drops across multiple custom gear sets.

## Features

- Create multiple monitored sets, such as `Holy Priest` and `Discipline Priest`.
- Add wanted items by item ID or by pasting an item link.
- Browse AtlasLootClassic dungeon and raid tables in a Plutocraseeker-owned loot browser.
- Watch raid, raid leader, and raid warning chat for linked wanted items.
- Show a popup and chat alert when a wanted item is linked.
- Suppress alerts when the item is already equipped or in the player's bags.
- Include an Interface Options configuration panel stub for future settings.
- Provide an optional AtlasLoot button that opens AtlasLootClassic when available.

## Install

Place these files in a World of Warcraft addon folder named `Plutocraseeker`, for example:

`World of Warcraft\_classic_\Interface\AddOns\Plutocraseeker`

WoW expects the folder and TOC basename to match. Keep the folder named `Plutocraseeker` so the client can see `Plutocraseeker.toc` and `Plutocraseeker_Mists.toc`.

## Usage

- `/plutocraseeker` or `/ps` opens the main window.
- `/ps add 105485` adds an item ID to the selected set.
- `/ps new Holy Priest` creates a new set.
- `/ps browse` opens the Plutocraseeker loot browser powered by AtlasLootClassic tables.
- `/ps atlasloot` tries to open AtlasLootClassic.

The loot browser reads AtlasLootClassic's loaded data tables, lets you filter sources, hover items for tooltips, Ctrl-click items for the dressing room, and add items to the selected Plutocraseeker set.
