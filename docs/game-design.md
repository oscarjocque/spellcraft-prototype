# Game Design Document

> Snapshot of the team's live design doc, exported 2026-10-19. The live doc is the source of truth; refresh this copy when it changes.

Oct 19, 2026 · @Oscar

## Overview

One-line pitch: *\[Working title\] is a game where players invent their own magic, building spells from snap-together blocks like Scratch.*

| Field | Answer |
| --- | --- |
| Working title | TBD |
| Genre | TBD |
| Platforms | TBD |
| Target audience | TBD |
| Comparable games | Noita (wand building), Magicka (element combos), Scratch (block coding) |
| Unique hook | A magic system that is deep and expressive, yet intuitive: spells are built from scratch out of building blocks |

## Spellcrafting system

Spells are sentences. Each is built around a verb block, which takes required objects (what it acts on) and optional adverbs (how it acts).

### Spells are continuous objects

A cast spell is a world object that performs its verb every tick for as long as it is active. Every spell is continuous; some are just short, because they reach their goal at once (Destroy on a candle flame ends after one tick).

| Verb | Each tick while active | Ends when |
| --- | --- | --- |
| Create | Builds the new object up, bigger objects taking longer | The object is complete |
| Destroy | Wears down the target | The target is gone |
| Move | Pushes the target toward its destination | The target arrives or is blocked |
| Change | Shifts the target's material or property toward the new one | The change is complete, or a For N s adverb runs out |

Any spell also ends early when its mana runs out or another spell destroys it, since spells are objects that Destroy can target.

Every spell has a location, set by its anchor:

| Anchor | Where the spell is | Example |
| --- | --- | --- |
| Owner | Follows its caster | A shield that moves with the player |
| Another object | Follows the object it is attached to | Frost creeping over an enemy |
| Independent | Its own point in the world; other spells can move it | A fire trap left on the floor |

Design pillars:

- **Readable:** a spell reads like a sentence, e.g. "Move the boulder toward the gate, quickly."
- **Low floor:** a working spell is one verb plus its required objects.
- **High ceiling:** adverbs, conjunctions and the pronoun "it" let experts build combos nobody designed.
- **Grammar by shape:** like Scratch's slots, blocks only snap where they make grammatical sense, so a spell missing its object can't be built.
- **Fast feedback:** test any spell in a sandbox before using it for real.

### Core verbs

| Verb | Required objects | Common adverbs | Example |
| --- | --- | --- | --- |
| Create | What | Here/there, Large, Many, For N s | Create fire there, large |
| Destroy | What | Gradually, Completely, Nearby | Destroy the wall, gradually |
| Move | What · To where | Quickly, Toward, Away, Repeatedly | Move it toward the nearest enemy, quickly |
| Change | What · Into what | Slowly, Partly, For N s | Change the water into ice, slowly |

### Word types

| Word type | Role | Examples |
| --- | --- | --- |
| Verb (core) | The action | Create, Destroy, Move, Change |
| Noun (required) | What the verb acts on | Direct references (Me, It) or selectors (Nearest enemy); materials (Fire, Ice) for Create |
| Adverb (optional) | How, where, how much, how long | Quickly, Toward, Large, Many, For 3 s |
| Conjunction | Links sentences into longer spells | Then, When, While, If |

Adverbs fall into four groups: manner (quickly, gently, violently), place (toward, away, around me), amount (large, many, a little) and time (for N s, after N s, repeatedly). "It" refers to whatever the previous sentence created or touched, which is what lets sentences chain.

### Nouns: references and selectors

A verb's noun slot takes one of two things: a direct reference to an object, or a selector block that chooses objects for it.

| Noun kind | What it is | Examples |
| --- | --- | --- |
| Direct reference | Points at one specific object | Me, It, an object the player clicks on |
| Selector | A block that picks objects by a rule | Nearest enemy, Everything within 3 m, Anything flammable |

A selector is a spell in its own right. How it is cast decides when it chooses:

| Selector cast as | When it chooses | Result |
| --- | --- | --- |
| Part of a bigger spell | Once, when the bigger spell is cast | The verb locks onto that choice for its whole life |
| Its own independent spell | Every tick while active | Spells using it follow whatever it picks now |

Like any spell, an independent selector has a location, drains mana and can be destroyed, which cuts off every spell relying on it. Selectors cost mana of their color and take their own qualifiers, so they nest, e.g. "Nearest of (Anything flammable) within 5 m."

Closest is measured from the spell's own location, and a spell attached to an object ignores that object. A spell anchored to its caster therefore never selects the caster: cast by a player, Closest Player finds someone else.

Create's noun, and Change's "into what", are the exception: they name a material or kind (Fire, Ice, Stone), because the object doesn't exist yet.

### Example spell: Chain Frost

1. Create ice, small.
2. Move it toward the nearest enemy, quickly.
3. When it hits, Change the target into frozen, for 2 s.
4. Then Create ice, small, many, and Move it toward nearby enemies.

### Mana colors

Mana comes in several colors, and every block costs one specific color. Each color mixes word types, owning one verb plus a few nouns and adverbs, so most spells draw on more than one color.

A first sketch with one color per verb, to be tuned:

| Color | Verb | Nouns | Adverbs |
| --- | --- | --- | --- |
| Red | Create | Fire, Light | Quickly, Large |
| Blue | Change | Water, Ice | Slowly, For N s |
| Green | Move | Stone, Wind | Toward, Away |
| Violet | Destroy | Nearest enemy, The target | Gradually, Completely |

Why it adds depth: Chain Frost now needs Red (Create), Blue (Ice, Change), Green (Move, Toward) and Violet (Nearest enemy), so a player low on Green has to redesign it, e.g. drop Move and anchor the frost to themselves instead.

### Mana economy

Mana is a world object, not a hidden meter. It lies in the world in its color, and players collect it into limited storage, so they are pushed to build spells from whichever colors are around them.

1. **Collect:** the player picks up mana objects until their storage is full.
2. **Infuse:** casting a spell moves mana from storage into the spell. The player chooses how much, which sets how long the spell can last; the default is as long as possible with the mana available.
3. **Drain:** each tick, the spell spends mana of each block's color.
4. **Release:** when a spell ends with mana left, for example because Destroy finished its target early, that mana drops back into the world at the spell's location as mana objects.

This creates play beyond spellcasting: released mana can be grabbed by anyone, so destroying an enemy's long-running spell can hand you its mana.

### Balance levers

- Each block drains mana of its color every tick the spell is active; adverbs like Large raise the drain.
- The slot limit counts words, starting at 6 and growing to about 20, which doubles as progression.
- Repeatedly and While raise the cooldown, so loops can't run forever.

## World objects

Everything in the world is one kind of thing: a world object. Players, items, obstacles, spells and spell effects differ only in which properties they carry, so the four verbs work on all of them alike: Move can push a crate, a player or another spell.

| Property | What it holds | Example |
| --- | --- | --- |
| Tags | Kinds it belongs to | player, item, flammable, conductive |
| Transform | Position, rotation, size | 2 m tall, facing north |
| Physics | Mass, velocity, solid or not, shape | a boulder: 500 kg, solid |
| Material | What it is made of; drives reactions | wood, stone, water, fire |
| State | Health, temperature, charge, statuses | 40/100 health, burning |
| Behavior | Logic that runs each tick | player input, enemy AI, a spell's sentences |
| Lifetime | How long it exists | fireball: 3 s; wall: until destroyed |

| Object type | Defining properties | Example |
| --- | --- | --- |
| Player | Behavior from input, health, mana, inventory | the caster |
| Item | Can be picked up and carried | a key, a potion |
| Obstacle | Solid, has a material, may be movable | a wooden door, a boulder |
| Spell | Performs its verb every tick while active; anchored to its owner, another object, or independent | a fire bolt in flight |
| Spell effect | A spell anchored to another object; may merge into the Spell type | Frozen for 2 s on an enemy |
| Mana | Has a color and an amount; can be collected, infused into spells, and released | A red mana crystal, mana released by a broken shield |

Rules are written against properties, not object types: "anything flammable touching fire starts burning", never "crates burn". That keeps interactions emergent, since a new object works with every rule as soon as it has the right properties.

## Simulation engine

One engine updates every world object on a fixed tick (e.g. 20 to 30 per second, on the server), in the same order every time.

*(A diagram of the simulation tick sits here in the live doc. Prototype 1 runs each tick in this order: inputs and casts → spells act → movement and collisions → contact rules → statuses and lifetimes → cleanup and mana release.)*

Interactions are where emergence happens: the engine checks contacts against material rules, not hand-written cases.

| When this | Touches this | Result |
| --- | --- | --- |
| Fire | Anything flammable | Target starts burning |
| Fire | Ice | Ice becomes water |
| Water | Fire | Fire is destroyed |
| Lightning | Anything conductive or wet | Charge spreads to touching objects |
| A fast solid object | Anything | Push and damage, scaled by mass and speed |

These are a starting set to tune, not final rules.

Engine principles:

- **Verbs are engine operations:** Create spawns an object, Destroy removes it, Move sets its position or velocity, Change edits its properties or material.
- **Events link ticks:** contacts and damage emit events that fire When and On hit triggers on the next tick, so chain reactions run one step per tick and can't loop forever inside one frame.
- **Deterministic:** the same inputs always give the same result, which makes the spell sandbox exact and helps if multiplayer comes later.
- **Rendering is separate:** the engine never draws; the renderer reads object state after each tick.

### Decided: 2D top-down, multiplayer preferred

- **2D physics:** objects are simple shapes (circles and boxes) on a flat plane with no gravity, so Move is the main force in the world.
- **Height as a layer:** a simple property (ground, low, air) lets a spell fly over a wall or a boulder block a bolt, without real 3D.
- **Server-authoritative:** players send inputs; the server runs the ticks and sends back object state, so no client can fake a result.
- **Spells checked on the server:** mana cost and slot limits are validated when a spell is cast, which blocks cheated spells.
- **Tick rate:** a networked game may run the simulation at 20 to 30 ticks per second, with clients smoothing movement between ticks.

Still open: how many players per session, and co-op, PvP, or both?

## Core gameplay loop

The loop is what the player does every 30 seconds to 5 minutes, and why they keep doing it.

1. Player does: fights or solves puzzles with their current spells
2. Game responds: enemies and puzzles that reward specific spell designs
3. Player earns: new blocks and more spell slots
4. Player spends or upgrades: rebuilds spells in the editor, then back to step 1

Why it stays fun after an hour: every new block multiplies the spells you can build, so discovery never runs out.

## Mechanics & systems

| Mechanic | What it does | Priority |
| --- | --- | --- |
| Movement | TBD | Must have |
| Spellcrafting | Build and cast spells from blocks (see Spellcrafting system) | Must have |
| Progression | TBD | Should have |
| Economy / resources | TBD | Nice to have |

Win and fail conditions: TBD

## Story, setting & characters

Premise in two sentences: TBD

Setting (time, place, tone): TBD

| Character | Role | Want | Notes |
| --- | --- | --- | --- |
| Player character | Protagonist | TBD | TBD |
| TBD | Antagonist | TBD | TBD |

## World & level design

Structure: linear levels, hub world, open world, or procedural (TBD).

| Level / area | Goal | New mechanic introduced | Est. playtime |
| --- | --- | --- | --- |
| Tutorial | Teach the core loop | TBD | TBD |
| Area 1 | TBD | TBD | TBD |

## Art & audio direction

- Visual style (pixel, low-poly, hand-drawn, realistic): TBD
- Color palette and mood: TBD
- Reference images or games: TBD
- Music style: TBD
- Key sound effects: TBD

## UI/UX & controls

| Action | Keyboard / mouse | Controller | Touch |
| --- | --- | --- | --- |
| Move | TBD | TBD | TBD |
| Main action | TBD | TBD | TBD |
| Pause / menu | Esc | Start | TBD |

HUD shows: TBD

## Scope, milestones & tech

Engine and tools: TBD. Team size: TBD. Target length of the finished game: TBD.

- [ ] Prototype: core loop playable with placeholder art
- [ ] Vertical slice: one polished level
- [ ] Alpha: all features in, content incomplete
- [ ] Beta: content complete, bug fixing
- [ ] Release

### Prototype 1 scope

The first prototype proves the core idea: three verbs, four materials and one selector are enough to build spells that interact.

| Block family | In the prototype |
| --- | --- |
| Verbs | Create, Destroy, Move |
| World objects | Fire, Water, Wood, Stone, plus spells and the player |
| Qualifiers | One per object type: Fire, Water, Wood, Stone, Spell, Player |
| Selectors | Closest (takes a qualifier, e.g. Closest Wood) |

Out of scope for now: Change, adverbs, conjunctions and other selectors.

Interaction rules needed, all between in-scope materials:

| When this | Touches this | Result |
| --- | --- | --- |
| Fire | Wood | Wood burns, then is destroyed |
| Water | Fire | Fire is destroyed |
| Anything moving | Stone | Stopped; stone blocks movement |

Spells the prototype can express:

- **Barrier:** Create Wood.
- **Extinguish:** Destroy (Closest Fire).
- **Boulder throw:** Move (Closest Stone) to (Closest Player).
- **Dispel:** Destroy (Closest Spell), which releases its mana.
- **Live tracker:** cast Closest Player as an independent selector, then Move (Closest Stone) to it, so the stone chases its target.

## Open questions & idea parking lot

- [ ] What makes this game different from its closest comparable?
- [ ] Are spells built mid-combat, or only between encounters?
- [ ] How do players unlock blocks: found, bought, or researched?
- [ ] Can players share or trade spells?
- [ ] Combat-focused, puzzle-focused, or both?
- [ ] Does Create need a Where, or default to in front of the caster?
- [ ] Can Change alter properties (size, speed, weight) or only materials?
- [ ] Should there be more core verbs (e.g. Sense, Bind), or keep it to four?
- [ ] Do created objects stay after their Create spell ends, or vanish with it?
- [ ] Where does mana appear in the world, and does it regrow? Is storage one shared limit or a limit per color? Can colors be converted?
- [ ] How far can a spell reach from its location to its target? Does a selector pick one object or all that match? Can one independent selector feed several spells?

* Ideas to revisit later: TBD
