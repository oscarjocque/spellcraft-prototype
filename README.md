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
| 1–9, 0 | Cast that slot's spell toward the mouse |
| Shift+1–0 | Put that slot's spell in the typing bar, to change it before casting (or Ctrl+1–0 to save it back) |
| Enter | Type a spell to cast (see below) |
| Tab | Open or close the spellbook (pauses the simulation) |
| Left click | While typing a spell, cast it there; while picking This or There, pick |
| Esc | Cancel a cast that is waiting for picks (a right click does too), or close the typing bar |
| Space | Drop one of your attached spells (pick it in a window, or click it by you) |
| F1 | Show every word, colored by mana, with typed examples |
| F2 | Next level (the sandbox, then levels 1–6, then the sandbox again) |
| R | Restart the sandbox or level |

### Making spells fast

**Type them.** Press **Enter**, type the spell, and press **Enter** to cast
it toward the mouse, or **click** where to cast it.

- **Short words.** Any prefix that fits where it stands: `mo cl st to me` is
  `Move (Closest Stone) to Me`.
- **Left-out words.** A thing on its own is the closest one (`destroy fire`).
  A verb with no noun acts on what the mouse is on (`de` is `Destroy This`,
  so `de` and a click destroys what you click), and Move with no place moves
  to the mouse (`mo st`). A noun on its own holds it (`closest player`).
  Parentheses, commas, "of", "to" and "m" are optional; plurals are fine.
- **Slips and everyday words.** One wrong, missing, extra or swapped letter is
  forgiven (`mvoe stoen`). `make a fire`, `kill the nearest rock`, `grab every
  rock`, `pull stone` (Move it to Me) and `put the rock there` work, and "a",
  "an" and "the" are skipped.
- **Help as you type.** Up to five next words are suggested (**Tab** takes the
  first, which shows faintly after the caret). The spell is shown as it was
  read, colored by the mana each word costs, with its cost. The world rings
  what it would act on now, and a line says how much, or that it would wait.
- **Repeat and keep.** **Enter** on the empty bar casts the last spell again;
  **↑/↓** go through earlier ones, kept between plays. **Shift+Enter** casts and keeps the bar open
  for the next, **Shift+click** keeps the spell ready to click onto more
  things, and **Ctrl+1–0** saves it to that slot.

Pointing at something shows the words that describe it (Stone · moving ·
mine); pointing at a spell shows what it's doing and the mana it has left.

**Or cast them from your slots.** Number keys cast them toward the mouse;
**Shift** with a number key puts that slot's spell in the typing bar, to
change a word or two and cast it (or save it back with **Ctrl** and the
number). Pointing at a slot's line in the list rings what it would act on
now, and clicking it opens it in the spellbook.

**Or click them together.** **Tab** opens the spellbook: your ten slots on the left,
the selected one on the right, where you can type it the same way or click its
words. Each word opens a menu of at most five choices (longer lists are split
into submenus: Pick ▸ Closest, Farthest, Random, All), "+" adds optional parts
(adjectives, "within", "up to", "at"), and optional parts have Remove.
Clicking into the text selects it, so typing replaces the spell, and
**Ctrl+Z** undoes the last change (a bout of typing counts as one). Your ten
slots are saved (in Godot's user folder) and come back next time; the
spellbook's "Reset all ten to the presets" brings the presets back.

In the sandbox the player has **infinite mana**: casting never takes from
storage, but each spell still gets its usual fuel and reserve. To turn it
off, remove the `infinite_mana` tag in `scripts/sandbox.gd`. Then walk over
the colored diamonds to collect mana. **Fountains**, one per color, well up a
crystal of their color every 2 s (keeping up to 3 crystals' worth around
them); they can't be moved by spells or by what runs into them, but they are
Things. **Mana of one color flows together**: orbs that come within a few
pixels of each other merge into one, holding the sum, bigger and heavier
(size and weight follow the amount, so a big orb costs more to Move). A
player or a spell takes only what it has room for, so a big orb is drained
partly and shrinks.

### Levels

**F2** goes from the sandbox through six test levels; the goal and how it's
going show at the top, and **R** restarts. In levels 1–3 mana is real but
plentiful, and each needs more spellcraft than the last.

1. **Onto the pad**: get a stone onto the gold pad. One spell, with picks:
   `move stone to there`, clicking the pad.
2. **Clear the ring**: get every log out of the gold ring. Pickers and Away
   from: `move all logs within 3 of there away from there`, clicking the
   middle (or one spell per log).
3. **Firebreak**: fires creep in on a wooden house from every side, a new one
   every 3 s; keep 2 of its 3 logs for 40 s. Casting `destroy fire` by hand
   works if you keep it up every couple of seconds; a live tracker does it in
   two casts: `hold all fire`, then `destroy target of this`, clicking the
   held spell by you. Or the other way round: `destroy target of this`, and
   while it asks for This, type `hold all fire`; the Hold becomes its This.

In levels 4–6 you start with **no mana**, no wild crystals appear, and what
lies around decides which words you can afford (F1 shows each word's color):

4. **Only green**: the stone onto the pad again, with two green crystals.
   Closest, This and Me are violet, so `move stone to there` can't be cast.
   `move aimed to there` is all green: walk until the stone is between you
   and the pad, then cast it at the pad.
5. **No violet**: burn the barricade behind a wall of stone. No violet means
   no Destroy, and no walking round. `create fire at there` costs red and
   one green word, and there's exactly one green crystal.
6. **Over the wall**: put out three bonfires. They're too big to Destroy on
   the 5 violet you'll find, but water puts fire out at once, and red and
   blue only well up beyond a wall. Mana passes through stone, so spend
   your green and violet pulling crystals over (`move this to me`, clicking
   one), then `create water at there, up to 1` on each bonfire.

## What's in Prototype 1

| Block family | In the prototype |
| --- | --- |
| Verbs | Create, Destroy, Move, Mark, Hold *(a noun on its own)*, Alternate [*slot or attached spell*] [*slot or attached spell*] |
| Create's objects | Fire, Water, Wood, Stone, or Spell [*another spell*]; optionally *at (noun)*: right in front of it, then the closest free spots around |
| Qualifiers | Thing *(any physical object)*, Fire, Water, Wood, Stone, Spell, Player, Mana |
| Pickers | Closest, Farthest, Random, All |
| Adjectives | Moving, Burning, Mine, Theirs, Marked |
| Picked when casting | This *(click a thing or a spell, or cast a spell then and there)*, There *(click a place)* |
| Other nouns | Me, Here *(the spell's location)*, Aimed, It *(inside an Alternate)*, Self *(the spell itself)* |
| Connectives | Move … to …, Move … away from … |
| Adverbs | up to N *(1, 2, 3 or 5)* |
| Relations | Target of, Caster of, Maker of, Products of |

The preset slots (keys 1–9 and 0):

| Slot | Spell | Name |
| --- | --- | --- |
| 1 | Create Fire. | |
| 2 | Alternate [spell 5] [spell 6]. | Juggle |
| 3 | Create Wood. | Barrier |
| 4 | Destroy (Closest Fire). | Extinguish |
| 5 | Move (Closest Stone) to Me. | Pull |
| 6 | Move (Closest Stone) to (Closest Player). | Boulder throw |
| 7 + 8 | Hold (Closest Player), then Move (Closest Stone) to (Target of This). | Live tracker |
| 9 | Create Spell [Destroy (Closest Fire)]. | Fire warden |
| 0 | Move This to There. | Telekinesis |

To try the live tracker, cast 7, then 8 and pick the held selector in the
window. The stone chases whichever other player is closest to you, switching
targets as you move.

### Nouns

A noun says what a spell acts on. Spells read like sentences:
`Move (All Moving Stone within 3 m of There) to Me`.

- **Pickers** choose by distance: **Closest**, **Farthest**, **Random** or
  **All** of a qualifier, narrowed by any number of **adjectives** (Moving,
  Burning, Mine = made by your spells, Theirs = someone else's, Marked = by
  your Mark). Distance is measured from the spell, or **to** another noun
  (`Closest Stone to There`), and can be limited **within** 1–5 m (of the
  spell, or of a noun). A spell attached to you never picks you. Inside a
  spell a picker chooses once, at cast; a held one (Hold) chooses again
  every tick, and Random sticks with its pick while it still fits.
- **Picked when casting:** **This** (any object or spell: click a thing or a
  spell's diamond, in the world or attached to you, or cast a spell right
  then, with a number key or the typing bar, and that new spell is the
  This) and **There** (a spot; it becomes an invisible place marker
  for as long as the spell lasts). Each use is picked separately, in reading
  order; the game keeps running while you
  pick, and Esc cancels the cast. The first pick comes from where you're
  already aiming: a first This is the thing or spell under the mouse when you cast
  (if there is one), a first There is the mouse's spot, so `Create Fire at
  There` lands at the cursor at once; later ones are clicked.
- **Aimed** is the first object along the line from the spell toward where
  you cast it. **Me** is you. **Here** is the spell's own location: where you
  are for a spell you cast, or where a created spell sits, so
  `Create Wood at Here` or `(All Fire within 2 m of Here)`.
- **Relations** are re-read every tick: **Target of** a spell is what it acts
  on now (a held noun's value, a Create's newest product, what a Move or
  Destroy acts on); **Caster of** is who cast it; **Maker of** an object is
  the spell that created it; **Products of** a Create is everything it made.
  They nest: `(Target of (Target of This))`.
- **It**, inside an Alternate, is what the *other* spell acted on in its last
  turn; each of the two spells has its own It. Outside an Alternate it means
  nothing.

Acting on several targets (All, Products of) drains the spell's mana once per
target per tick.

### Adverbs

Any spell, nested ones included, can take an adverb from the adverb picker
at the end of its sentence. The first is **up to N**, which sets how much:

| Verb | Up to N |
| --- | --- |
| Create | makes at most N objects, then only sustains them |
| Create Spell | makes N spells instead of 3 (and carries mana for N) |
| Destroy | acts on the N nearest at a time; ends once it has destroyed N |
| Move | moves only the N nearest |
| Mark | marks at most N, then ends |
| Hold | holds at most N picks |
| Alternate | runs N turns, then ends |

It reads as `Destroy (All Fire), up to 2.` and, like any word, costs mana.

### Hold, inventory and This

Casting a noun on its own (**Hold**, e.g. `Hold (Closest Player)`) doesn't do
anything by itself: it stays attached to you and keeps re-reading its noun
while its mana lasts. Every spell attached to you is in your **inventory**,
listed top right, and **This** lets another spell use one (or any spell in
the world): `Destroy This` dispels it, and `Move (Closest Stone) to (Target
of This)` follows what a held selector picks now. Several spells can use the same held
noun.

Attached spells are diamonds in a ring around you, numbered as in the list,
in their verb's color, with lines to what they act on. A hollow diamond is
waiting for something to act on; a faded one is waiting for its turn in an
Alternate. Point at one to see its words, what it's doing and its mana.

**Space** drops one of your attached spells, picked in a window while the
game keeps running: it stays where it is, stops following you, and leaves
your inventory. Since it's no longer attached to you, its pickers can pick
you, and its Here is where you dropped it.

### Away from and Self

**Create … up to N** stops once it has made N things, unless they'd expire
without it (fire): then it stays to sustain them. Fire and water aren't
solid, so Create puts them right on whatever they're made at.

**Move** *X* **away from** *Y* pushes *X* straight away from *Y* until it's
5 m off (letting go in time to coast the rest), and keeps it at least that far;
`push X` is Move X away from Me. **Self** is the spell itself, as an object:
`Destroy Self` ends it, and `Move Self to There` sends the spell there (a
spell moving itself leaves its caster, so it stops following them).

### Mark

**Mark** *noun* marks what the noun means, for you: the adjective **Marked**
then picks it, as in `Destroy (All Marked Thing)`. It's done once it has
marked something, unless it follows a spell's target, in which case it marks
each new one.

### Alternate

**Alternate** [*A*] [*B*] runs two spells attached to itself, one at a time,
switching when the running one is done, or after 3 s if it isn't. Each side
is either:

- **a spell slot** (`spell 5`): the spell in that slot is copied in when you
  cast, and cast fresh each turn, paid for by the Alternate. A slot that
  leads back to the Alternate itself is rejected.
- **an attached spell** (**This**, picked when casting): the Alternate takes
  it over. It leaves your inventory, runs only on its turns (paused, using no
  mana, in between), keeps paying its own way, and ends with the Alternate.

If one side has nothing left to run, the other keeps going; the Alternate
ends when its mana runs out, or after its "up to" turns. Inside it, **It** is
what the other side acted on in its last turn. The Juggle preset (slot 2) is
`Alternate [spell 5] [spell 6]`: pull the closest stone to you, throw the
closest stone at the closest player, and again.

### Spells wait for a target

A spell with nothing to act on doesn't end: it waits, still draining mana,
and looks again every tick for anything its nouns can mean. `Destroy
(Closest Fire)` cast with no fire around destroys the next fire that appears.
A spell still ends when it reaches its goal (what a Destroy locked onto is
gone), when a spell it follows is destroyed (it's cut off), or when its mana
runs out. A Move whose object or destination is destroyed looks for another,
and a Destroy following a selector goes on to the selector's next pick.

### Spells that create spells

Choose **Spell** as Create's object to describe the spell to create (in the
spellbook, a nested sentence opens in brackets). Spells nest: the created spell
can itself be a Create Spell.

- **Create Spell makes 3 spells**, one at once and then one a second, then
  ends. Like Create, it puts each in the closest free spot to where it aims,
  refilling the spot of a spell that ended.
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
  Me still means the caster, Target of the creator means the newest spell
  it made, and Products of means all of them.
- Each spell drains only its own words. A spell that ends returns fuel and
  any unspent reserve to the world.
- There is no word limit; cost (drain plus reserve) is what keeps spells in check.

### Rules

Interaction rules: fire sets flammable things burning, and burning wood is
destroyed. Water destroys fire and puts out burning things. Anything moving
stops at still stone. When two solid objects collide, each takes damage
once, from the other's mass times the speed they closed at, if that's high
enough: a thrown stone hurts a player (and a little itself), a player walking
into a wall hurts nothing, and something pressed against you hits only when
it first arrives.

**Move pushes.** It puts a steady force on what it moves, and everything has
the same drag, a resistance growing with speed, so a push tops out at Move's
speed (140 px/s) whatever is pushed. Weight shows in getting there and in
stopping: a stone takes about a second and a half to get up to speed and
coasts a while after the push ends, a player a fraction of that, wood and
fire hardly at all. Moved to something solid, a thing rams into it at speed;
moved to a place (There) or something that isn't solid, Move lets go in time
for it to coast to a stop right there. **A Move doesn't end when things get
there**: it stops pushing what's at its goal (and drains only its listed
rate meanwhile), and pushes it again once it's knocked, or its goal moves,
more than 8 px off. So `Move Stone to Me` keeps the stone with you as you
walk, and a Move to another spell's target keeps chasing it. Something in
the way is pushed against, so a thing slides around obstacles where it can.
It lasts until its mana runs out. Things keep their momentum when they
hit: a moving stone shoves a player or wood along, sharing its momentum, and
still stone stops them dead. Pushes add up: several Moves on one object
combine (opposite ones cancel), and a Move on a player adds to their walking,
which itself stays instant.

**Weight.** Every object has one: fire 0.1, a spell 1, a mana crystal 2,
water 20, wood 30, a player 70, stone 200. Besides how sluggish it is to push,
weight sets what moving it costs: while a Move pushes, its drain is scaled by
the total weight it pushes, per 70 (a player). Moving a stone drains about
three times the listed rate, wood under half, fire next to nothing; while it
has nothing to push, a Move drains its listed rate. Pointing at something
shows its weight, and the typing bar says what a Move would push and the
factor. A spell
draws in mana within 1 m of it (a faint circle around a spell loose in the
world) into its own fuel, up to its limit and only in colors it uses, so
`Move (Closest Mana) to It` can top up a running spell.

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
  spells/spell_parser.gd  reads typed spells; suggests the next word
  ui/hud.gd, ui/spell_editor.gd (the spellbook), ui/spell_chips.gd (clickable
  words), ui/spell_input.gd + ui/quick_cast.gd (typing), ui/spell_text.gd
  sandbox.gd       test arena and preset spells
  spellbook.gd     saves and loads the ten slots
  cast_flow.gd     a cast's picks (This, There), then the queue to send
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

`tests/soak.gd` plays a long random session through the real game (it needs
a display) to catch runtime errors: `godot --path . --script res://tests/soak.gd`.

## Decisions made for the prototype

These are open questions in the design doc. The prototype picks a simple
answer for each so it can be playtested. Every value can be tuned through the
constants at the top of each script.

- **Create places its object in front of the caster**, toward the cursor, so it needs no Where.
- **Create keeps creating until its mana runs out.** Each new object goes in the free spot closest to where Create aims: just in front of you toward where you cast, or with *at*, right in front of what it's at (on it, for There). Spots are tried outward from there, your side first, so objects gather around that point, and a gap (an object destroyed or pushed away) is refilled first. With no free spot within reach (6 object widths), Create waits. While the spell lasts it sustains everything it made, so fire doesn't burn out. Building takes about 1.5 s for wood and 1 s for fire. Created objects stay after the spell ends, though fire then burns out after 10 s.
- **Mana storage is a limit per color** (30), and players start full.
- **A spell holds at most 60 s of its own drain** in each color, plus the reserve for the spells it creates (each of them full, counting what they create in turn), so its limits grow with what it consumes. Casting fills it from storage up to that; a spell drawing in mana tops up only to its limit, and only in colors it uses; a created spell starts full. Pointing at a spell shows its mana against its limits, and the typing bar shows what a spell holds.
- **Blocks that change the world drain 0.2 mana per second** of their color (verbs, and what Create makes), **structural blocks 0.05** (pickers, things picked, adjectives, nouns, relations, within, at, away from, up to): a typical spell runs for 30–60 s, and a Hold, which changes nothing, is cheap. Colors follow the design doc's first sketch, and Wood, Me, It and Mana have colors assigned here.
- **Mana can be selected and moved but not created.** Create Mana would produce mana for less than it yields.
- **Mana crystals regrow:** one random crystal appears every 3 s, while the world holds less than 12 crystals' worth.
- **Picks are stored in the spell.** What you click for This and There is written into the cast spell, so the server can check it: This must be an existing object or spell (not the spell itself; that's Self), There inside the arena.
- **Spells are edited in the spellbook while the game is paused, or typed while it runs.** The word menus only offer words that fit the grammar.
- **Objects are circles.** There are no boxes or height layers yet.
- **Move is a force against drag** (`Simulation.DRAG`, `Spell.MOVE_SPEED`): drag is the same for every object rather than growing with weight, so every object tops out at the same speed and only heavier ones are slower to get going and to stop. Collisions are fully inelastic along the line between the two objects: no bouncing.
