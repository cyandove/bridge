# In-World Build Instructions: Card Image Prims

These steps must be completed in Second Life after the scripts are uploaded.
No scripting changes are needed — this is purely object-building work.

---

## 1. Card Textures

Upload 53 textures total. Use these exact names (case-sensitive):

### Card faces (52 textures)

Name format: `<rank><suit>` — e.g. `AS`, `KH`, `2C`, `TH`

| Rank codes | Suit codes |
|---|---|
| `2 3 4 5 6 7 8 9 T J Q K A` | `C D H S` |

Full list:
```
2C 3C 4C 5C 6C 7C 8C 9C TC JC QC KC AC
2D 3D 4D 5D 6D 7D 8D 9D TD JD QD KD AD
2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH AH
2S 3S 4S 5S 6S 7S 8S 9S TS JS QS KS AS
```

### Card back (1 texture)

Name: `purple_back`

### Where to put them

`llGetInventoryKey` only looks in the inventory of the prim the script is running in.
Upload the textures into:
- The prim containing **`card_display.lsl`** (wherever you place that script in the table linkset)
- The prim containing **`hud_controller.lsl`** (wherever you place that script in the HUD linkset)

---

## 2. Table Prims (17 new prims)

Link all new prims into the existing table linkset (same object as the root prim).

### Trick prims (4)

One prim per seat, showing the card played in the current trick.

| Prim name | Position (approximate) |
|---|---|
| `trick_N` | North side of centre |
| `trick_S` | South side of centre |
| `trick_E` | East side of centre |
| `trick_W` | West side of centre |

Suggested size: ~0.12m × 0.18m (standard card ratio), lying flat on the table surface.

### Dummy hand prims (13)

One prim per card slot.

Names: `dummy_0` through `dummy_12`

These prims are repositioned and retextured at runtime when dummy is revealed.
Their starting position does not matter — the script moves them into place.

Suggested size: same as trick prims (~0.12m × 0.18m), flat on the table.

### Linking

Select all 17 new prims plus the existing table object and link them (Ctrl+L).
The original table root prim must remain the root of the linkset.

---

## 3. HUD Prims (26 new prims)

The HUD is currently a single-prim object. Expand it to a multi-prim linked object.

### Hand prims (13)

Showing the player's own cards.

Names: `hcard_0` through `hcard_12`

Lay these out in a row (or arc) on the HUD face. Cards are assigned left-to-right in
suit order: S high→low, H high→low, D high→low, C high→low.

### Dummy prims (13)

Showing dummy's cards (visible to declarer only).

Names: `dcard_0` through `dcard_12`

Lay these out in a second row below the hand prims, or in a separate panel.

### Linking

Select all 26 new prims plus the existing HUD root prim and link them.
The original HUD root prim (containing `hud_controller.lsl`) must remain the root.

### Placing in seat prim inventories

`seat.lsl` runs inside each seat prim and calls `llGiveInventory` from there, so it
checks that prim's own inventory. After building the HUD, drag the completed HUD object
into **each of the four seat prims** individually (North, South, East, West).

---

## 4. Adjust Table Layout Constants

The dummy hand prims are positioned in local space relative to the table root prim.
The default values in `card_display.lsl` assume a 2m × 2m table with cards 0.02m above
the surface. Measure your actual table and adjust these constants (lines ~137–154):

```lsl
list DUMMY_BASE_POS = [
    <-0.72,  1.10, 0.02>,   // North seat — position of dummy_0
    <-0.72, -1.10, 0.02>,   // South seat
    < 1.10, -0.72, 0.02>,   // East seat
    <-1.10, -0.72, 0.02>    // West seat
];
list DUMMY_SPREAD = [
    <0.12, 0.0,  0.0>,      // North: each card offset +0.12m along X
    <0.12, 0.0,  0.0>,      // South
    <0.0,  0.12, 0.0>,      // East:  each card offset +0.12m along Y
    <0.0,  0.12, 0.0>       // West
];
list DUMMY_CARD_ROT = [
    <0.0,  0.0,  0.0,    1.0>,    // North: no rotation
    <0.0,  0.0,  1.0,    0.0>,    // South: 180 deg around Z
    <0.0,  0.0,  0.707,  0.707>,  // East:   90 deg around Z
    <0.0,  0.0, -0.707,  0.707>   // West:  -90 deg around Z
];
```

**How to find the right values:**

1. Rez a test prim on the table, note its local position (Edit > local coords).
2. Set `DUMMY_BASE_POS` for that seat to match where you want `dummy_0` to appear.
3. Set `DUMMY_SPREAD` to the card width + a small gap (e.g. `<0.13, 0, 0>` for 0.12m
   cards with 0.01m gaps).
4. `DUMMY_CARD_ROT` controls which way the card faces — the defaults orient each hand
   readable from the centre of the table.

---

## 5. Verification Checklist

After completing the build, run through these in-world tests:

- [ ] All four seats occupied (mix of humans and bots)
- [ ] Deal a hand — trick prims start blank, no errors in script debug
- [ ] Opening lead plays — trick prim for that seat shows the correct card face
- [ ] After 4 cards played, all trick prims clear automatically
- [ ] After opening lead, 13 dummy card prims appear near the dummy seat, face-up, readable
- [ ] As declarer: clicking a dummy prim submits that card as dummy's play
- [ ] As declarer: HUD shows own hand as card images in `hcard_*` prims
- [ ] As declarer: HUD shows dummy hand in `dcard_*` prims after dummy is revealed
- [ ] Clicking an `hcard_*` or `dcard_*` prim during play sends the card
- [ ] Playing a card removes it from the prim display (prim goes transparent)
- [ ] Bidding dialogs still work normally (no regression)
- [ ] After hand ends, all trick and dummy prims clear

### Fallback check

If `hcard_*` / `dcard_*` prims are absent from the HUD, the `llDialog` card-selection
flow should still work. Test this by temporarily removing one of the card prims from the
HUD linkset — the script should fall back to the dialog automatically.
