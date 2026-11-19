# Electric Floor

A standalone Factorio 2.1 mod that adds a single tile, **Electric floor**: a
concrete floor with an embedded grid pattern that conducts electricity. Anything
built on it is powered without poles.

The tile, item, recipe and technology integration are extracted from the
[Dectorio](https://github.com/jpanther/Dectorio) mod ("concrete grid").
The conductivity system is original.

## How the floor conducts

Tiles can never take part in the electric network - only entities can. So the
floor is made conductive by laying a **sparse network of invisible electric
poles** over it:

1. **Covering.** Every dirty 32x32 chunk is read, and its floor tiles are covered
   with the fewest possible square patches (a quadtree over a 2D prefix sum). One
   hidden pole is placed in the middle of each patch, sized so its supply area
   covers that patch exactly. A completely tiled chunk needs **one** pole.
2. **Wiring.** Poles are wired to every pole whose supply square touches theirs,
   which means the electric network follows the shape of the floor. Two separate
   floors never share power, and cutting a floor in half splits its network.
3. **Real poles.** Any electric pole whose supply area touches the floor joins
   the floor network - built next to it, standing on it, or already there when
   the floor is laid. A substation standing beside the floor reaches 9 tiles in,
   so it already powers the tiles at the floor's edge and therefore feeds the
   whole floor.

The hidden poles have an empty collision mask (they share the cell with the
machine they power), `maximum_wire_distance = 0` (the game never connects them on
its own) and are bought by script with `connect_to(target, false)` - the `false`
disables the reach check, because the floor itself is the conductor.

## Why it is cheap

* **Idle cost is nil.** Work is only queued when a floor tile appears or
  disappears. The queue is drained by a single `on_nth_tick` handler which does
  one table lookup and returns when there is nothing to do.
* **One pole per ~900 tiles.** A 200x200 floor needs 44 poles, not 40,000.
* **Diffed updates.** A chunk is only modified where its covering actually
  changed, so building a machine on the floor does not rebuild anything.
* **Batched.** A few chunks are wired per pass, so a large blueprint cannot stall
  a tick.

## Reacting to changes

* Placing a pole on an already conducting floor joins it **in the same tick**
  (the wire is made directly in the entity-built event).
* Laying or removing floor queues the affected chunk; the next update pass
  rewires it within `pass-interval` ticks (1 tick by default).
* If a pole is placed faster than the game initialises it - e.g. pulling a pole
  out and putting it straight back - the immediate attempt finds nothing to
  connect to, so the pole's chunk is queued as well and repaired by the next
  pass. Rebuilding is diffed, so this costs nothing when nothing changed.

## Settings

Both are runtime-global and can be changed on an existing save:

| Setting | Default | Meaning |
|---|---|---|
| `pass-interval` | 1 | Ticks between update passes. Higher = cheaper. |
| `chunks-per-pass` | 1 | Chunks wired up per pass. Lower = smoother. |

## Remote interface

* `remote.call("electric-floor", "rescan")` - rebuild the whole network, spread
  over ticks.
* `remote.call("electric-floor", "rescan_now")` - the same, but completes
  immediately. Use after adding the mod to an existing save with floor already
  placed.

The network is also rebuilt automatically when the mod version changes.

## Installation

The folder must be named `<name>_<version>`, e.g. `electric-floor_1.1.0`.

## Credits / License

The grid texture and icon are extracted from **Dectorio** by PantherX, licensed
under the **GNU GPLv3**. This mod redistributes those assets and is therefore
also distributed under the GNU GPLv3.
