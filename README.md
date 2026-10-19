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
| Q / E | Choose a spell in your inventory of attached spells |
| Left click | Cast the selected spell toward the cursor |
| Tab | Open or close the spell editor (pauses the simulation) |
| R | Reset the sandbox |

For now the player has **infinite mana**: casting never takes from storage,
but each spell still gets its usual fuel and reserve. To turn it off, remove
the `infinite_mana` tag in `scripts/sandbox.gd`. Then walk over the colored
diamonds to collect mana.

## What's in Prototype 1

| Block family | In the prototype |
| --- | --- |
| Verbs | Create, Destroy, Move |
| Create's objects | Fire, Water, Wood, Stone, or Spell [*another spell*] |
| Qualifiers | Fire, Water, Wood, Stone, Spell, Player, Mana |
| Selectors | Closest (takes a qualifier), inside a spell or cast on its own |
| References | Me, It, Held, Chosen, Target of *(noun)* |

The preset slots cover every spell the design doc lists for this prototype:

| Slot | Spell | Name in the design doc |
| --- | --- | --- |
| 1 | Create Fire. | |
| 2 | Create Water. | |
| 3 | Create Wood. | Barrier |
| 4 | Destroy (Closest Fire). | Extinguish |
| 5 | Move (Closest Stone) to (Closest Player). | Boulder throw |
| 6 | Destroy (Closest Spell). | Dispel |
| 7 + 8 | Closest Player, then Move (Closest Stone) to Held. | Live tracker |
| 9 | Create Spell [Destroy (Closest Fire)]. | Fire warden |

To try a live tracker, cast 7, then 8. The stone chases whichever other player
is closest to you, switching targets as you move, until its mana runs out.

### Held selectors

Casting an incomplete spell, a bare selector like `Closest Player`, doesn't
do anything by itself: you **hold** it. It stays attached to you, never picks
you, and re-chooses every tick while its mana lasts.

The noun **Held** puts the selector you're holding into the next spell you
cast that uses it. That spell then follows whatever the selector picks *now*,
where an inline `(Closest Player)` would choose once at cast and stay locked.
The taken selector belongs to that spell: you no longer hold it, and it ends
when the spell ends. If you hold nothing, Held points at nothing and the spell
ends at once.

A Move chasing a held selector's pick doesn't end when it arrives or is
blocked; it keeps chasing, sliding around obstacles, until its mana runs out.

### Inventory, Chosen and Target of

Every spell attached to you (one you cast that follows you and hasn't been
taken with Held) is in your **inventory**, listed top right. **Q/E** choose
one; until you do, the newest is chosen.

- **Chosen** is the spell you have chosen, as a noun: `Destroy Chosen`
  dispels exactly that spell.
- **Target of** *noun* is what that spell acts on *right now*, re-checked
  every tick: a selector's pick, the object a Move or Destroy acts on, or a
  Create's product (the newest object in its line, or the spell it created).
  It nests, and unlike Held it only looks: the spell stays in your inventory.
  `Move (Closest Stone) to (Target of Chosen)` with a held `Closest Player`
  chosen is a live tracker that leaves the selector free for other spells.
  Target of something that isn't a spell is nothing, so the spell ends.

### Spells that create spells

Choose **Spell** as Create's object to describe the spell to create (in the
editor, a nested sentence opens in brackets). Spells nest: the created spell
can itself be a Create Spell.

- **Create Spell makes 3 spells**, one at once and then one a second, in a
  line toward where it was cast, then ends. Like Create, it puts each in the
  nearest free place on the line, refilling the place of a spell that ended.
- **The creator carries the mana up front.** Casting a spell that creates
  others takes, besides its own fuel, a *reserve* of one *share* per spell it
  will make. A share is enough to run that spell for 60 s, plus that spell's
  own reserve, and so on down, so nesting multiplies the cost (3 x 3 spells
  for a Create Spell inside a Create Spell). If storage can't cover the
  reserve, the cast fails; with ordinary storage (30 per color) that rules
  most Create Spells out, so they're really for the infinite-mana sandbox.
- **A created spell is paid from its creator's reserve**, one share each,
  never from the caster's storage. It keeps what it must carry for its own
  created spells as its reserve and burns the rest.
- **A created spell sits where it was made** and doesn't follow the caster.
  Me still means the caster, It means the first spell created, and Target of
  the creator means the newest.
- Each spell drains only its own words. A spell that ends returns fuel and
  any unspent reserve to the world.
- There is no word limit; cost (drain plus reserve) is what keeps spells in check.

### Rules

Interaction rules: fire sets flammable things burning, and burning wood is
destroyed. Water destroys fire and puts out burning things. Anything moving
stops at stone. A fast, heavy solid object damages whatever it hits. Moves
add up: several Moves on one object combine their pushes (opposite ones
cancel), and a Move on a player adds to their walking. A spell
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
- **Create keeps creating until its mana runs out.** Each object is built in turn in a line toward where it was cast: Create Wood grows a wall, Create Fire lays a trail. Each new object goes in the nearest free place on the line, so a gap (an object destroyed or pushed away) is refilled before the line grows, and anything in the way is skipped. When the line is full up to the arena's edge, Create waits for space. While the spell lasts it sustains everything it made, so fire doesn't burn out. Building takes about 1.5 s for wood and 1 s for fire. Created objects stay after the spell ends, though fire then burns out after 10 s.
- **Mana storage is a limit per color** (30), and players start full. A cast infuses at most 10 of each color it needs.
- **Every block drains 0.2 mana per second** of its color, so a typical spell runs for 25–50 s. Colors follow the design doc's first sketch, and Wood, Me, It and Mana have colors assigned here.
- **Mana can be selected and moved but not created.** Create Mana would produce mana for less than it yields.
- **Mana crystals regrow:** one random crystal appears every 3 s, up to 12 in the world.
- **A selector picks one object**, the closest. A held selector feeds exactly one spell, the first that takes it with Held. "It" still refers to your last selector too, without taking it.
- **Spells are edited while the game is paused.** The editor is dropdowns that only offer blocks that fit the grammar. It stands in for a drag-and-drop block editor.
- **Objects are circles.** There are no boxes or height layers yet.
