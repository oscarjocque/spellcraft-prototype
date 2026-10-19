# Spellcraft Prototype

A Godot 4 prototype of a game where players invent their own magic: spells are
sentences built from snap-together blocks, like Scratch. See
[docs/game-design.md](docs/game-design.md) for the full design.

This is **Prototype 1**. It aims to show that three verbs, four materials and one
selector are enough to build spells that interact in ways nobody scripted.

![Sandbox](docs/screenshot.png)

## Running it

1. Install [Godot 4.5](https://godotengine.org/download) (standard build, GDScript only).
2. Open `project.godot` in Godot and press **F5**, or run
   `godot --path .` from this folder.

| Input | Action |
| --- | --- |
| WASD / arrows | Move |
| 1–9 | Pick a spell slot |
| Left click | Cast the selected spell toward the cursor |
| Tab | Open or close the spell editor (pauses the simulation) |
| R | Reset the sandbox |

Walk over the colored diamonds to collect mana.

## What's in Prototype 1

| Block family | In the prototype |
| --- | --- |
| Verbs | Create, Destroy, Move |
| Create's objects | Fire, Water, Wood, Stone, or Spell [*another spell*] |
| Qualifiers | Fire, Water, Wood, Stone, Spell, Player, Mana |
| Selectors | Closest (takes a qualifier), inside a spell or cast on its own |
| References | Me, It |

The preset slots cover every spell the design doc lists for this prototype:

| Slot | Spell | Name in the design doc |
| --- | --- | --- |
| 1 | Create Fire. | |
| 2 | Create Water. | |
| 3 | Create Wood. | Barrier |
| 4 | Destroy (Closest Fire). | Extinguish |
| 5 | Move (Closest Stone) to (Closest Player). | Boulder throw |
| 6 | Destroy (Closest Spell). | Dispel |
| 7 + 8 | Closest Player (independent), then Move (Closest Stone) to It. | Live tracker |
| 9 | Create Spell [Destroy (Closest Fire)]. | Fire warden |

To try a live tracker, cast 7 near the training dummy (the yellow circle), then cast 8.
The stone chases whichever player is closest to the selector.

### Spells that create spells

Choose **Spell** as Create's object to describe the spell to create (in the
editor, a nested sentence opens in brackets). Spells nest: the created spell
can itself be a Create Spell.

- **The creator carries the mana up front.** Casting a spell that creates
  another takes, besides its own fuel, a *reserve*: enough to run the created
  spell for 5 s, plus that spell's own reserve, and so on down. If storage
  can't cover the reserve, the cast fails.
- **A created spell is paid from its creator's reserve**, never from the
  caster's storage. It keeps what it must carry for its own created spell as
  its reserve and burns the rest.
- **A created spell sits where it was made**, just in front of its creator,
  and doesn't follow the caster. Me still means the caster, and It means the
  new spell.
- Each spell drains only its own words. A spell that ends returns fuel and
  any unspent reserve to the world.
- There is no word limit; cost (drain plus reserve) is what keeps spells in check.

### Rules

Interaction rules: fire sets flammable things burning, and burning wood is
destroyed. Water destroys fire and puts out burning things. Anything moving
stops at stone. A fast, heavy solid object damages whatever it hits. A spell
that touches mana absorbs it into its own fuel, so `Move (Closest Mana) to It`
can top up a running spell.

## How it's built

```
scripts/
  sim/             deterministic simulation; never draws
    simulation.gd    fixed 20 Hz tick, collisions, casting, mana release
    world_object.gd  the single object type; kinds differ only by properties
    materials.gd     property presets for materials, players, mana, spells
    rules.gd         contact rules written against properties
  spells/
    spell_grammar.gd spells as data: blocks, words, mana colors, validation
    spell.gd         a cast spell: performs its verb every tick until it ends
  render/world_view.gd   draws simulation state, smoothed between ticks
  ui/hud.gd, ui/spell_editor.gd
  sandbox.gd       test arena and preset spells
  main.gd          runs the tick loop and turns local input into commands
tests/test_spells.gd   headless tests for every prototype spell and rule
```

The design calls for a server-authoritative multiplayer game, so the
simulation is kept apart from everything else. It takes input only as
command dictionaries, validates every cast (grammar, mana), and
is deterministic for a given seed and inputs. Networking can be added later
without changing it.

Run the tests with:

```
godot --headless --path . --script res://tests/test_spells.gd
```

## Decisions made for the prototype

These are open questions in the design doc. The prototype picks a simple
answer for each so it can be playtested. Every value can be tuned through the
constants at the top of each script.

- **Create places its object in front of the caster**, toward the cursor, so it needs no Where.
- **Created objects stay** after their Create spell ends. Fire burns out after 10 s.
- **Mana storage is a limit per color** (30), and players start full. A cast infuses at most 10 of each color it needs.
- **Every block drains 1 mana per second** of its color. Colors follow the design doc's first sketch, and Wood, Me, It and Mana have colors assigned here.
- **Mana can be selected and moved but not created.** Create Mana would produce mana for less than it yields.
- **Mana crystals regrow:** one random crystal appears every 3 s, up to 12 in the world.
- **A selector picks one object**, the closest. An independent selector sits where it was cast (the cursor) and can feed any number of spells through "It".
- **Spells are edited while the game is paused.** The editor is dropdowns that only offer blocks that fit the grammar. It stands in for a drag-and-drop block editor.
- **Objects are circles.** There are no boxes or height layers yet.
