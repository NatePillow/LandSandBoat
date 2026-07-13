# Log Message Review

Fill in the **Updated** column with desired new text. Leave blank to keep as-is.

Commented-out log calls are excluded. The `autoutil.log` definition itself is excluded.


---

## General Guidance

Use this table to provide patterns or rules that apply across multiple log messages.

| Pattern / Applies To                                   | Guidance                                              |
|---------------------------------------------------------|-------------------------------------------------------|
| All "Not unlocked" messages                             |                                                       |
| All "packet error:" messages                            |                                                       |
| All "render error:" messages                            |                                                       |
| All Usage / help messages                               |                                                       |
| All "stopped" / "started" confirmation messages         |                                                       |
| All WARNING: prefixed messages                          |                                                       |
| Internal debug labels (e.g. `can_mb`, `stunReady`)     |                                                       |
| nil-target / nil-index error messages                   |                                                       |

---


## autobots/autobots.lua

| Line | Tag      | Current Message                                                                                                     | Updated                                             |
|------|----------|---------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------|
| 22   | AutoBots | `'Config not found: '.. path`                                                                                       |                                                     |
| 29   | AutoBots | `'Failed to parse config: '.. configName`                                                                           |                                                     |
| 48   | AutoBots | `'Loaded config: '.. configName`                                                                                    |                                                     |
| 199  | AutoBots | `'Not unlocked (waiting for server ident).'`                                                                        | Not unlocked. Are you using the single player fork? |
| 205  | AutoBots | `'Nothing to stop.'`                                                                                                |                                                     |
| 239  | AutoBots | `'No active config.'`                                                                                               |                                                     |
| 253  | AutoBots | `'Usage: /autobots lot <itemName> <charName> [charName ...]'`                                                       |                                                     |
| 263  | AutoBots | `'Usage: /autobots start <config> \| /autobots stop \| /autobots finish \| /autobots lot <item> <char> [char ...]'` |                                                     |
| 271  | AutoBots | `'Unknown config: '.. configName`                                                                                   |                                                     |

---

## autodrop/autodrop.lua

| Line | Tag      | Current Message                                                                  | Updated |
|------|----------|----------------------------------------------------------------------------------|---------|
| 51   | AutoDrop | `'dropping %s x%d (slot %d)'`                                                    |         |
| 100  | AutoDrop | `'timed out waiting for slot %d confirmation, continuing.'`                      |         |
| 111  | AutoDrop | `'render error: ' .. tostring(err)`                                              |         |
| 122  | AutoDrop | `'Not unlocked (waiting for server ident).'`                                     |         |
| 127  | AutoDrop | `'Usage: /autodrop <item name>'`                                                  |         |
| 135  | AutoDrop | `'No items found matching: %s'`                                                  |         |
| 145  | AutoDrop | `'Queued %d item(s) of "%s" to drop.'`                                           |         |

---

## autobuy/autobuy.lua

| Line   | Tag       | Current Message                                                            | Updated   |
| ------ | --------- | -------------------------------------------------------------------------- | --------- |
| 118    | AutoBuy   | `'WARNING: could not open price CSV: %s'`                                  |           |
| 155    | AutoBuy   | `'Loaded %d price entries from CSV.'`                                      |           |
| 181    | AutoBuy   | `'WARNING: could not enumerate recipes directory.'`                        |           |
| 197    | AutoBuy   | `'WARNING: failed to parse recipe file: %s'`                               |           |
| 222    | AutoBuy   | `'Loaded %d recipe file(s).'`                                              |           |
| 236    | AutoBuy   | `'WARNING: could not enumerate groups directory.'`                         |           |
| 252    | AutoBuy   | `'WARNING: failed to parse group file: %s'`                                |           |
| 276    | AutoBuy   | `'Loaded %d group file(s).'`                                               |           |
| 430    | AutoBuy   | `'  MISSING from CSV: %s (id=%d)'`                                         |           |
| 432    | AutoBuy   | `'  insufficient stock: %s needs %d (stock_single=%d stock_stacks=%d)'`    |           |
| 563    | AutoBuy   | `'All bids sent.'`                                                         |           |
| 575    | AutoBuy   | `'Not unlocked (waiting for server ident).'`                               |           |
| 582    | AutoBuy   | `'Usage:'`                                                                 |           |
| 583    | AutoBuy   | `'  /autobuy item "Item Name" single\|stack quantity [bid_price]'`         |           |
| 584    | AutoBuy   | `'  /autobuy recipe "Recipe Name or Alias" single\|stack quantity'`        |           |
| 585    | AutoBuy   | `'  /autobuy group "Group Name or Alias"'`                                 |           |
| 586    | AutoBuy   | `'  /autobuy scrolls'`                                                     |           |
| 595    | AutoBuy   | `'Usage: /autobuy group "Group Name or Alias"'`                            |           |
| 602    | AutoBuy   | `'No group found for "%s".'`                                               |           |
| 611    | AutoBuy   | `'Group: %s'`                                                              |           |
| 616    | AutoBuy   | `'  item not found: %s'`                                                   |           |
| 620    | AutoBuy   | `'  not on AH: %s'`                                                        |           |
| 622    | AutoBuy   | `'  queuing: %s x%d @ %d gil'`                                             |           |
| 631    | AutoBuy   | `'Nothing to purchase.'`                                                   |           |
| 635    | AutoBuy   | `'Queued %d bid packet(s).'`                                               |           |
| 662    | AutoBuy   | `'scroll not found in table: %s'`                                          |           |
| 666    | AutoBuy   | `'scroll not on AH: %s'`                                                   |           |
| 668    | AutoBuy   | `'queuing scroll: %s @ %d gil'`                                            |           |
| 679    | AutoBuy   | `'No scrolls to purchase.'`                                                |           |
| 683    | AutoBuy   | `'Queued %d scroll bid(s).'`                                               |           |
| 693    | AutoBuy   | `'Usage: /autobuy recipe "Recipe Name or Alias" single\|stack quantity'`   |           |
| 702    | AutoBuy   | `'Buy type must be "single" or "stack"'`                                   |           |
| 707    | AutoBuy   | `'Quantity must be a positive integer'`                                    |           |
| 713    | AutoBuy   | `'No recipe found for "%s".'`                                              |           |
| 722    | AutoBuy   | `'No recipe found where all ingredients appear available (CSV check).'`    |           |
| 730    | AutoBuy   | `'Purchase aborted: not enough inventory space (%d free, %d needed).'`     |           |
| 740    | AutoBuy   | `'Recipe: %s — crystal: %s%s, %d synth(s)'`                                |           |
| 743    | AutoBuy   | `'  %s x%d %s @ %d gil'`                                                   |           |
| 749    | AutoBuy   | `'Queued %d bid packet(s).'`                                               |           |
| 758    | AutoBuy   | `'Usage: /autobuy item "Item Name" single\|stack quantity [bid_price]'`    |           |
| 768    | AutoBuy   | `'Buy type must be "single" or "stack"'`                                   |           |
| 773    | AutoBuy   | `'Quantity must be a positive integer'`                                    |           |
| 777    | AutoBuy   | `'Searching for item: %s'`                                                 |           |
| 781    | AutoBuy   | `'Item not found: %s'`                                                     |           |
| 798    | AutoBuy   | `'Item "%s" is not sold as %s on the AH (sell_%s=0 in CSV).'`              |           |
| 810    | AutoBuy   | `'Queuing %d %s bid(s) for %s @ %d gil.'`                                  |           |
| 815    | AutoBuy   | `'Purchase aborted: not enough inventory space (%d free, %d needed).'`     |           |
| 853    | AutoBuy   | `'AH unavailable (result=0x%02X). Aborting.'`                              |           |
| 882    | AutoBuy   | `'%s: purchased %d, could not purchase %d (%s).'`                          |           |
| 894    | AutoBuy   | `'packet error: '.. tostring(err)`                                         |           |
| 906    | AutoBuy   | `'WARNING: no 0x004C response received, sending next packet anyway.'`      |           |
| 911    | AutoBuy   | `'render error: '.. tostring(err)`                                         |           |

---

## autoheal/autoheal.lua

| Line   | Tag      | Current Message                                                                                                               | Updated   |
| ------ | -------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- |
| 47     | AutoHeal | `'packet error: '.. tostring(err)`                                                                                            |           |
| 84     | AutoHeal | `'Curaga'`                                                                                                                    |           |
| 87     | AutoHeal | `'Cure_P1'`                                                                                                                   |           |
| 90     | AutoHeal | `'can_cure_high_priority_status'`                                                                                             |           |
| 93     | AutoHeal | `'Cure_P2'`                                                                                                                   |           |
| 96     | AutoHeal | `'sleeping_members'`                                                                                                          |           |
| 99     | AutoHeal | `'can_bar_spell'`                                                                                                             |           |
| 102    | AutoHeal | `'can_cure_medium_priority_status'`                                                                                           |           |
| 105    | AutoHeal | `'Regen'`                                                                                                                     |           |
| 108    | AutoHeal | `'always_ability_is_up'`                                                                                                      |           |
| 111    | AutoHeal | `'can_protectra_or_shellra'`                                                                                                  |           |
| 114    | AutoHeal | `'can_haste'`                                                                                                                 |           |
| 117    | AutoHeal | `'sleeping_alliance'`                                                                                                         |           |
| 120    | AutoHeal | `'can_whm_enfeeble'`                                                                                                          |           |
| 123    | AutoHeal | `'can_cure_low_priority_status'`                                                                                              |           |
| 126    | AutoHeal | `'can_buff_self'`                                                                                                             |           |
| 129    | AutoHeal | `'can_use_food'`                                                                                                              |           |
| 132    | AutoHeal | `'can_mb'`                                                                                                                    |           |
| 135    | AutoHeal | `'can_mb_2'`                                                                                                                  |           |
| 138    | AutoHeal | `'casual_whm_nuke_is_up'`                                                                                                     |           |
| 147    | AutoHeal | `'render error: '.. tostring(err)`                                                                                            |           |
| 161    | AutoHeal | `'Not unlocked (waiting for server ident).'`                                                                                  |           |
| 166    | AutoHeal | `'stopped'`                                                                                                                   |           |
| 177    | AutoHeal | `'dps stats reset'`                                                                                                           |           |
| 181    | AutoHeal | `'Usage: /autoheal start <config> \| /autoheal controller <config> \| /autoheal stop \| /autoheal dps \| /autoheal dpsreset'` |           |

---

## autolot/autolot.lua

| Line   | Tag     | Current Message                                                                 | Updated   |
| ------ | ------- | ------------------------------------------------------------------------------- | --------- |
| 76     | AutoLot | `'skipping "'.. name .. '" — already in inventory'`                             |           |
| 92     | AutoLot | `'LOT slot=%d item=%s'`                                                         |           |
| 103    | AutoLot | `'PASS slot=%d item=%s'`                                                        |           |
| 216    | AutoLot | `'OUTROLLED on %s (leader: %s)'`                                                |           |
| 249    | AutoLot | `'WON: %s'`                                                                     |           |
| 252    | AutoLot | `'LOST: %s (winner: %s)'`                                                       |           |
| 295    | AutoLot | `'packet error: '.. tostring(err)`                                              |           |
| 319    | AutoLot | `'render error: '.. tostring(err)`                                              |           |
| 343    | AutoLot | `'groups: %d, items: %d'`                                                       |           |
| 353    | AutoLot | `'Not unlocked (waiting for server ident).'`                                    |           |
| 361    | AutoLot | `'active: '.. tostring(active)`                                                 |           |
| 362    | AutoLot | `'groups: '.. (#groupNames > 0 and table.concat(groupNames, ', ') or '(none)')` |           |
| 363    | AutoLot | `'items: '.. (#namedItems > 0 and table.concat(namedItems, ', ') or '(none)')`  |           |
| 369    | AutoLot | `'stopped'`                                                                     |           |
| 383    | AutoLot | `'started'`                                                                     |           |
| 392    | AutoLot | `'added'`                                                                       |           |
| 404    | AutoLot | `'removed'`                                                                     |           |
| 409    | AutoLot | `usage`                                                                         |           |

---

## autonuke/autonuke.lua

| Line   | Tag      | Current Message                                                                                                               | Updated   |
| ------ | -------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- |
| 48     | AutoNuke | `'packet error: '.. tostring(err)`                                                                                            |           |
| 85     | AutoNuke | `'stunReady'`                                                                                                                 |           |
| 88     | AutoNuke | `'can_mb'`                                                                                                                    |           |
| 91     | AutoNuke | `'can_mb_2'`                                                                                                                  |           |
| 94     | AutoNuke | `'nukeUntilDead'`                                                                                                             |           |
| 97     | AutoNuke | `'sc_is_close'`                                                                                                               |           |
| 99     | AutoNuke | `'sleeping_whm'`                                                                                                              |           |
| 102    | AutoNuke | `'Curaga'`                                                                                                                    |           |
| 105    | AutoNuke | `'Cure_P1'`                                                                                                                   |           |
| 108    | AutoNuke | `'can_sleep_add'`                                                                                                             |           |
| 111    | AutoNuke | `'can_sleep_add with rdm'`                                                                                                    |           |
| 114    | AutoNuke | `'always_ability_is_up'`                                                                                                      |           |
| 117    | AutoNuke | `'can_enfeeble'`                                                                                                              |           |
| 120    | AutoNuke | `'can_blm_enfeeble'`                                                                                                          |           |
| 123    | AutoNuke | `'can_buff_self'`                                                                                                             |           |
| 126    | AutoNuke | `'can_use_food'`                                                                                                              |           |
| 129    | AutoNuke | `'can_leech'`                                                                                                                 |           |
| 132    | AutoNuke | `'casual_nuke_is_up'`                                                                                                         |           |
| 136    | AutoNuke | `'render error: '.. tostring(err)`                                                                                            |           |
| 150    | AutoNuke | `'Not unlocked (waiting for server ident).'`                                                                                  |           |
| 155    | AutoNuke | `'stopped'`                                                                                                                   |           |
| 171    | AutoNuke | `'dps stats reset'`                                                                                                           |           |
| 175    | AutoNuke | `'Usage: /autonuke start <config> \| /autonuke controller <config> \| /autonuke stop \| /autonuke dps \| /autonuke dpsreset'` |           |

---

## autora/autora.lua

| Line   | Tag    | Current Message                                           | Updated   |
| ------ | ------ | --------------------------------------------------------- | --------- |
| 35     | AutoRA | `'Not unlocked (waiting for server ident).'`              |           |
| 41     | AutoRA | `"Delay: ".. shootDelay`                                  |           |
| 45     | AutoRA | `"Delay: ".. shootDelay`                                  |           |
| 49     | AutoRA | `"Starting auto ranged attacks!"`                         |           |
| 53     | AutoRA | `"Stopping auto ranged attacks!"`                         |           |
| 57     | AutoRA | `"Stopping auto ranged attacks at ".. stopAtTp .. " TP!"` |           |
| 97     | AutoRA | `'render error: '.. tostring(err)`                        |           |

---

## autordm/autordm.lua

| Line   | Tag     | Current Message                                                                                                          | Updated   |
| ------ | ------- | ------------------------------------------------------------------------------------------------------------------------ | --------- |
| 48     | AutoRdm | `'packet error: '.. tostring(err)`                                                                                       |           |
| 86     | AutoRdm | `'stunReady'`                                                                                                            |           |
| 89     | AutoRdm | `'can_mb'`                                                                                                               |           |
| 92     | AutoRdm | `'can_mb_2'`                                                                                                             |           |
| 95     | AutoRdm | `'sleeping_whm'`                                                                                                         |           |
| 98     | AutoRdm | `'can_sleep_add'`                                                                                                        |           |
| 101    | AutoRdm | `'nukeUntilDead'`                                                                                                        |           |
| 104    | AutoRdm | `'sc_is_close'`                                                                                                          |           |
| 106    | AutoRdm | `'Curaga'`                                                                                                               |           |
| 109    | AutoRdm | `'Cure_P1'`                                                                                                              |           |
| 112    | AutoRdm | `'can_dia'`                                                                                                              |           |
| 115    | AutoRdm | `'can_haste_self'`                                                                                                       |           |
| 118    | AutoRdm | `'can_refresh'`                                                                                                          |           |
| 121    | AutoRdm | `'can_haste'`                                                                                                            |           |
| 124    | AutoRdm | `'can_silence'`                                                                                                          |           |
| 127    | AutoRdm | `'can_enfeeble'`                                                                                                         |           |
| 130    | AutoRdm | `'sleeping_members'`                                                                                                     |           |
| 133    | AutoRdm | `'can_cure_high_priority_status'`                                                                                        |           |
| 136    | AutoRdm | `'can_cure_medium_priority_status'`                                                                                      |           |
| 139    | AutoRdm | `'always_ability_is_up'`                                                                                                 |           |
| 142    | AutoRdm | `'can_blm_enfeeble'`                                                                                                     |           |
| 145    | AutoRdm | `'can_cure_low_priority_status'`                                                                                         |           |
| 148    | AutoRdm | `'can_buff_self'`                                                                                                        |           |
| 151    | AutoRdm | `'can_use_food'`                                                                                                         |           |
| 154    | AutoRdm | `'can_leech'`                                                                                                            |           |
| 157    | AutoRdm | `'casual_nuke_is_up'`                                                                                                    |           |
| 161    | AutoRdm | `'render error: '.. tostring(err)`                                                                                       |           |
| 175    | AutoRdm | `'Not unlocked (waiting for server ident).'`                                                                             |           |
| 180    | AutoRdm | `'stopped'`                                                                                                              |           |
| 196    | AutoRdm | `'dps stats reset'`                                                                                                      |           |
| 200    | AutoRdm | `'Usage: /autordm start <config> \| /autordm controller <config> \| /autordm stop \| /autordm dps \| /autordm dpsreset'` |           |

---

## autosc/autosc.lua

| Line   | Tag    | Current Message                                                                                                     | Updated   |
| ------ | ------ | ------------------------------------------------------------------------------------------------------------------- | --------- |
| 39     | AutoSC | `'out of melee range: %.1f / %.1f'`                                                                                 |           |
| 150    | AutoSC | `'cast_utsusemi: no utsusemi spell available'`                                                                      |           |
| 241    | AutoSC | `'packet error: '.. tostring(err)`                                                                                  |           |
| 276    | AutoSC | `'chi_blast'`                                                                                                       |           |
| 288    | AutoSC | `'potentPoison'`                                                                                                    |           |
| 296    | AutoSC | `'activeTargets: get_target_index returned nil for '.. tostring(autoability.activeTargets[1])`                      |           |
| 300    | AutoSC | `'can_use_boost'`                                                                                                   |           |
| 303    | AutoSC | `'opening toolbag for shihei'`                                                                                      |           |
| 306    | AutoSC | `'can_cast_utsusemi'`                                                                                               |           |
| 326    | AutoSC | `'Locking on...'`                                                                                                   |           |
| 340    | AutoSC | `'use_weapon_skill'`                                                                                                |           |
| 349    | AutoSC | `'should_use_ability'`                                                                                              |           |
| 355    | AutoSC | `'should_start_sc'`                                                                                                 |           |
| 358    | AutoSC | `'can_provoke_add'`                                                                                                 |           |
| 361    | AutoSC | `'can_provoke_target'`                                                                                              |           |
| 364    | AutoSC | `'should_use_always_ability'`                                                                                       |           |
| 370    | AutoSC | `'should_solo_ws'`                                                                                                  |           |
| 373    | AutoSC | `'can_use_chakra'`                                                                                                  |           |
| 376    | AutoSC | `'can_use_spirit_link'`                                                                                             |           |
| 379    | AutoSC | `'can_use_call_wyvern'`                                                                                             |           |
| 382    | AutoSC | `'can_use_barrage'`                                                                                                 |           |
| 385    | AutoSC | `'can_use_ancient_circle'`                                                                                          |           |
| 388    | AutoSC | `'can_use_arcane_circle'`                                                                                           |           |
| 391    | AutoSC | `'can_use_warding_circle'`                                                                                          |           |
| 394    | AutoSC | `'should_ra'`                                                                                                       |           |
| 398    | AutoSC | `'render error: '.. tostring(err)`                                                                                  |           |
| 412    | AutoSC | `'Not unlocked (waiting for server ident).'`                                                                        |           |
| 417    | AutoSC | `'stopped'`                                                                                                         |           |
| 428    | AutoSC | `'dps stats reset'`                                                                                                 |           |
| 432    | AutoSC | `'Usage: /autosc start <config> \| /autosc controller <config> \| /autosc stop \| /autosc dps \| /autosc dpsreset'` |           |

---

## autoskill/autoskill.lua

| Line   | Tag       | Current Message                                                               | Updated   |
| ------ | --------- | ----------------------------------------------------------------------------- | --------- |
| 64     | AutoSkill | `'packet error: '.. tostring(err)`                                            |           |
| 95     | AutoSkill | `'render error: '.. tostring(err)`                                            |           |
| 103    | AutoSkill | `'Not unlocked (waiting for server ident).'`                                  |           |
| 115    | AutoSkill | `"Starting auto magic skillups using ".. table.concat(magicCmd, ", ") .. "!"` |           |
| 117    | AutoSkill | `"Starting auto magic skillups!"`                                             |           |
| 122    | AutoSkill | `"Stopping auto magic skillups!"`                                             |           |

---

## autotank/autotank.lua

| Line   | Tag      | Current Message                                                                          | Updated   |
| ------ | -------- | ---------------------------------------------------------------------------------------- | --------- |
| 55     | AutoTank | `'packet error: '.. tostring(err)`                                                       |           |
| 94     | AutoTank | `'potentPoison'`                                                                         |           |
| 98     | AutoTank | `'new adds stop_rest'`                                                                   |           |
| 104    | AutoTank | `'newAdds not empty'`                                                                    |           |
| 106    | AutoTank | `'newAdds: get_target_index returned nil for '.. tostring(autoability.newAdds[1])`       |           |
| 110    | AutoTank | `'activeAdds not empty'`                                                                 |           |
| 112    | AutoTank | `'activeAdds: get_target_index returned nil for '.. tostring(autoability.activeAdds[1])` |           |
| 116    | AutoTank | `'can_rest'`                                                                             |           |
| 119    | AutoTank | `'stop_rest'`                                                                            |           |
| 140    | AutoTank | `'Locking on...'`                                                                        |           |
| 150    | AutoTank | `'have_potion'`                                                                          |           |
| 158    | AutoTank | `'sleeping_whm'`                                                                         |           |
| 161    | AutoTank | `'always_ability_is_up'`                                                                 |           |
| 165    | AutoTank | `'provoke_is_up'`                                                                        |           |
| 168    | AutoTank | `'can_use_rampart'`                                                                      |           |
| 171    | AutoTank | `'flash_is_up'`                                                                          |           |
| 174    | AutoTank | `'Cure_P1'`                                                                              |           |
| 177    | AutoTank | `'can_use_sentinel'`                                                                     |           |
| 180    | AutoTank | `'Cure_P2'`                                                                              |           |
| 183    | AutoTank | `'can_use_holy_circle'`                                                                  |           |
| 186    | AutoTank | `'Cure_P3'`                                                                              |           |
| 189    | AutoTank | `'Cure_P4'`                                                                              |           |
| 195    | AutoTank | `'render error: '.. tostring(err)`                                                       |           |
| 209    | AutoTank | `'Not unlocked (waiting for server ident).'`                                             |           |
| 214    | AutoTank | `'stopped'`                                                                              |           |
| 218    | AutoTank | `'Usage: /autotank start <config> \| /autotank controller <config> \| /autotank stop'`   |           |

---

## libs/autoability.lua

| Line   | Tag         | Current Message                                                        | Updated   |
| ------ | ----------- | ---------------------------------------------------------------------- | --------- |
| 309    | AutoAbility | `'use_ability: nil target for '.. tostring(abilityName)`               |           |
| 326    | AutoAbility | `'use_ability_on: nil index for '.. tostring(abilityName)`             |           |
| 599    | AutoAbility | `'use_ws: nil target for '.. tostring(wsName)`                         |           |
| 604    | AutoAbility | `'Unknown WS: '.. tostring(wsName)`                                    |           |
| 613    | AutoAbility | `'ranged_attack: nil target'`                                          |           |
| 648    | AutoAbility | `'found attacking add: '.. actorId`                                    |           |
| 651    | AutoAbility | `'found sleeping add: '.. targetId`                                    |           |
| 677    | AutoAbility | `'off-tank: activeTarget attacking %s'`                                |           |
| 702    | AutoAbility | `'provoking add: '.. targetId`                                         |           |
| 706    | AutoAbility | `'rampart'`                                                            |           |
| 756    | AutoAbility | `'activeAdd %d hitting non-tank/non-provoker, re-queuing for provoke'` |           |
| 865    | AutoAbility | `'opener ws=%s msg=%d hasAddEffect=%d addEffectMsg=%d isSC=%s'`        |           |
| 872    | AutoAbility | `'closer ws=%s msg=%d hasAddEffect=%d addEffectMsg=%d isSC=%s'`        |           |
| 919    | DPS         | `'melee  %d/%d (%s) dmg=%d avg=%d'`                                    |           |
| 922    | DPS         | `'%s %d/%d (%s) dmg=%d avg=%d'` (ws label)                             |           |
| 925    | DPS         | `'ranged %d/%d (%s) dmg=%d avg=%d'`                                    |           |
| 934    | DPS         | `'%s %d/%d (%s) dmg=%d avg=%d'` (ability name)                         |           |

---

## libs/autoequip.lua

| Line   | Tag       | Current Message                                                                  | Updated   |
| ------ | --------- | -------------------------------------------------------------------------------- | --------- |
| 33     | AutoEquip | `'WARNING: Vana\'diel time pointer not found — e_time conditions will not work'` |           |
| 664    | AutoEquip | `'find_item: no resource for item.Id=%d'`                                        |           |
| 689    | AutoEquip | `'container=%d (%s) max=%d'`                                                     |           |
| 696    | AutoEquip | `'  [%d] id=%d count=%d name="%s"'`                                              |           |
| 711    | AutoEquip | `'File not found: "%s"'`                                                         |           |
| 719    | AutoEquip | `'Failed to parse XML'`                                                          |           |
| 731    | AutoEquip | `'No <sets> element found in XML'`                                               |           |
| 753    | AutoEquip | `'Loaded %s'`                                                                    |           |
| 987    | AutoEquip | `'Item not found: "%s" (slot: %s)'`                                              |           |
| 990    | AutoEquip | `'Unknown slot name: "%s"'`                                                      |           |
| 1011   | AutoEquip | `'%s: xml not loaded (char=%s)'`                                                 |           |
| 1016   | AutoEquip | `'%s: section not found in xml'`                                                 |           |
| 1021   | AutoEquip | `'%s changed: %s'`                                                               |           |
| 1027   | AutoEquip | `'premagic: unknown spell_id=%s'`                                                |           |
| 1036   | AutoEquip | `'midcast: unknown spell_id=%s'`                                                 |           |
| 1069   | AutoEquip | `'jobability: unknown ability_id=%s'`                                            |           |

---

## libs/autoitem.lua

| Line   | Tag      | Current Message                                        | Updated   |
| ------ | -------- | ------------------------------------------------------ | --------- |
| 20     | AutoItem | `'No Remedy found!'`                                   |           |
| 33     | AutoItem | `'No Potion found!'`                                   |           |
| 46     | AutoItem | `'No Ether found!'`                                    |           |
| 59     | AutoItem | `'No Antidote found!'`                                 |           |
| 127    | AutoItem | `'potent poison detected: '.. proc_value .. 'hp/tick'` |           |

---

## libs/automagic.lua

| Line   | Tag       | Current Message                                                                                   | Updated   |
| ------ | --------- | ------------------------------------------------------------------------------------------------- | --------- |
| 101    | AutoMagic | `'Could not find cast time for '.. spellId .. ', returning 1!'`                                   |           |
| 122    | AutoMagic | `'Could not find delay for '.. spellId .. ', returning 3!'`                                       |           |
| 135    | AutoMagic | `'Could not find id for '.. spellName .. ', returning 0!'`                                        |           |
| 172    | AutoMagic | `'Could not find target for spell: '.. spellId`                                                   |           |
| 440    | AutoMagic | `'get_valid_regen_target: member index nil for '.. memberTable[1]`                                |           |
| 503    | AutoMagic | `'cast_healing_spell: no valid target'`                                                           |           |
| 520    | AutoMagic | `'cast_regen_spell: no valid target'`                                                             |           |
| 539    | AutoMagic | `'cast_curaga: no valid target'`                                                                  |           |
| 593    | AutoMagic | `'get_player_indices_for_status: member index nil for '.. memberTable[1]`                         |           |
| 643    | AutoMagic | `'party_has_status: member index nil for '.. name`                                                |           |
| 672    | AutoMagic | `'find_status_cure: member index nil for '.. tostring(player)`                                    |           |
| 722    | AutoMagic | `'wake_up_members: member index nil for '.. tostring(sleepingPlayer)`                             |           |
| 745    | AutoMagic | `'wake_up_alliance: member index nil for '.. tostring(name)`                                      |           |
| 914    | AutoMagic | `'cast_raise: no dead member found'`                                                              |           |
| 1005   | AutoMagic | `'get_valid_refresh_target: member index nil for '.. memberTable[1]`                              |           |
| 1048   | AutoMagic | `'cast_refresh: no valid target'`                                                                 |           |
| 1066   | AutoMagic | `'get_valid_haste_target: member index nil for '.. memberTable[1]`                                |           |
| 1110   | AutoMagic | `'cast_haste: no valid target'`                                                                   |           |
| 1533   | AutoMagic | `'cast_healing_spell: no valid target'`                                                           |           |
| 1538   | AutoMagic | `'efficientSpell: '.. playerIndex`                                                                |           |
| 1544   | AutoMagic | `'spellId: '.. playerIndex`                                                                       |           |
| 1566   | AutoMagic | `'get_sleeping_whm: member index nil for '.. memberTable[1]`                                      |           |
| 1714   | AutoMagic | `'unverified msg=%d spell="%s" target="%s"'`                                                      |           |
| 1722   | AutoMagic | `'dia packet seen: spell="%s" spellId=%d statusId=%s msg=%d target=%d on=%s off=%s'`              |           |
| 1729   | AutoMagic | `'dia status via non-dia spell: spell="%s" spellId=%d statusId=%d msg=%d target=%d on=%s off=%s'` |           |
| 1734   | AutoMagic | `'dia STATUS ON via MAGIC_DMG: spell="%s" spellId=%d statusId=%s target=%d'`                      |           |
| 1739   | AutoMagic | `'TargetMPDrained packet seen: spell="%s" msg=%d target=%d'`                                      |           |
| 1743   | AutoMagic | `'TargetHPDrained packet seen: spell="%s" msg=%d target=%d'`                                      |           |
| 1747   | AutoMagic | `'TargetNoEffect packet seen: spell="%s" msg=%d target=%d'`                                       |           |
| 1753   | AutoMagic | `'dia STATUS ON via statusOnMes: spell="%s" spellId=%d statusId=%d msg=%d target=%d'`             |           |
| 1758   | AutoMagic | `'dia STATUS OFF via statusOffMes: spell="%s" spellId=%d statusId=%d msg=%d target=%d'`           |           |
| 1914   | AutoMagic | `'sc_close ws=%s msg=%d hasAddEffect=%d addEffectMsg=%d isSC=%s'`                                 |           |
| 1942   | AutoMagic | `'check_for_target_tracking: GetEntity nil for index '.. tostring(assistEngagedWithIndex)`        |           |
| 2062   | AutoMagic | `'potentPoison'`                                                                                  |           |
| 2066   | AutoMagic | `'handle_walking'`                                                                                |           |
| 2071   | AutoMagic | `'use_remedy'`                                                                                    |           |
| 2075   | AutoMagic | `'use_ether'`                                                                                     |           |
| 2080   | AutoMagic | `'poisoned_use_remedy'`                                                                           |           |
| 2084   | AutoMagic | `'can_rest'`                                                                                      |           |
| 2089   | AutoMagic | `'stop_rest'`                                                                                     |           |
| 2119   | DPS       | `'%s %d/%d (%s) dmg=%d avg=%d'` (spell label)                                                     |           |
| 2123   | DPS       | `'%s %d/%d (%s) dmg=%d avg=%d'` (mb label)                                                        |           |
| 2126   | DPS       | `'spikes x%d dmg=%d avg=%d'`                                                                      |           |

---

## libs/autoutil.lua

| Line   | Tag      | Current Message                                                                      | Updated   |
| ------ | -------- | ------------------------------------------------------------------------------------ | --------- |
| 244    | AutoUtil | `'%s -> nil'`                                                                        |           |
| 246    | AutoUtil | `'%s -> item exists but Id is nil'`                                                  |           |
| 248    | AutoUtil | `'%s -> Id=0 (empty slot)'`                                                          |           |
| 253    | AutoUtil | `'%s -> Id=%d name="%s" delay=%s'`                                                   |           |
| 352    | AutoBots | `'Unknown token: '.. tostring(nextArg)`                                              |           |
| 363    | Party    | `'config: nil'`                                                                      |           |
| 366    | Party    | `'nm='.. tostring(config['nm']) .. ' stationary=' .. tostring(config['stationary'])` |           |
| 367    | Party    | `'assist='.. tostring(config['assist'][1]) .. ' ' .. tostring(config['assist'][2])`  |           |
| 374    | Party    | `key .. ': ' .. table.concat(parts, ', ')`                                           |           |
| 380    | Party    | `'scKey: open=... close=... mb=...'` (sc config dump)                                |           |
| 405    | AutoBots | `'Config not found: '.. path`                                                        |           |
| 412    | AutoBots | `'Failed to parse config: '.. configName`                                            |           |
| 479    | 0x28     | `'t=%d actor="%s"(%d) target="%s"(%d) count=%d category=%d param=%s msg=%d'`         |           |
| 494    | 0x29     | `'t=%d actor="%s"(%d) target="%s"(%d) msg=%d param1=%s param2=%s'`                   |           |
| 513    | AutoUtil | `'Auto-accepting %s'`                                                                |           |
| 543    | Relay    | `'from=%d payload="%s"'`                                                             |           |
