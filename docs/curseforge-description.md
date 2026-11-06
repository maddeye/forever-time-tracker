**`/played` tells you how long. This tells you what you actually did with it.**

Forever Time Tracker sorts every second you spend in World of Warcraft: Forever into categories like Fighting, Traveling, Crafting and AFK. Then it shows you the split. Find out how much of that 8-hour session was combat, and how much was running back from the graveyard.

## What you get

- **A full breakdown.** Time and percentage for each activity, sorted from most to least.
- **A timeline of your session.** See when you were fighting and when you stood in Orgrimmar for twenty minutes.
- **Daily history.** Stacked columns for the last 7 or 30 days. Hover over a day for its numbers.
- **Actively playing vs. not.** One number for real play, one for idle, AFK and loading screens.
- **Every character.** Switch between one character and all of them, for any time range.
- **Nothing to set up.** Install it and play. It starts counting when you log in.

## What it tracks

| Category | When it counts |
| --- | --- |
| Fighting | The game has you in combat |
| Traveling | You're moving, mounted or not, or on a flight path |
| Gathering | Mining, herbing, skinning or fishing |
| Crafting | Crafting something, or standing at an open profession window |
| Eating & Drinking | Sitting with food or drink |
| NPCs & Trade | Quest dialogs, vendors, trainers, mail, the bank, the auction house and trades |
| Dead | Lying dead or running back as a ghost |
| Idle | In the game but not doing anything: chatting, reading the map, deciding what's next |
| AFK | Flagged AFK, plus the idle minutes before the game set the flag |
| Loading | Loading screens |

## How to use it

Click the stopwatch on your minimap or type `/ftt`. With EllesmereUI, the button sits in the group button's flyout unless you turn on "Ungroup Minimap Buttons".

- `/ftt` opens or closes the window
- `/ftt minimap` hides or shows the minimap button
- `/ftt reset` deletes this character's data, after asking you to confirm
- `/ftt debug` prints what the addon thinks you're doing right now

## Good to know

- The total is lower than `/played` because the addon only counts time since you installed it.
- The game saves addon data when you log out or `/reload`, so a crash loses everything since the last save.
- Your data stays in your `WTF` folder. The addon sends nothing anywhere.
- Eating and drinking are recognized in English, German, French and Spanish. Gathering is matched in English and German.

## Found a bug?

A wrong category is likely in this early version. Please [open an issue](https://github.com/maddeye/forever-time-tracker/issues) with what you were doing and the output of `/ftt debug`.
