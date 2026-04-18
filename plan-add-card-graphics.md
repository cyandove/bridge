# add-card-graphics Branch

## What Was Built

| Feature | Script | Status |
|---|---|---|
| Trick card prims on table (trick_N/S/E/W) | card_display.lsl | Done |
| Dummy hand prims on table (dummy_0..12) | card_display.lsl | Done |
| Notecard-configurable dummy layout (card_layout) | card_display.lsl | Done |
| HUD hand card prims (hcard_0..12) | hud_controller.lsl | Done |
| HUD dummy card prims (dcard_0..12) | hud_controller.lsl | Done |
| Two-click card selection (highlight → play) | hud_controller.lsl, card_display.lsl | Done |
| "start" prim Ready button on HUD | hud_controller.lsl | Done |
| HUD flip for dummy hand (Y-axis rotation) | hud_controller.lsl | Disabled (infra kept) |
| Inter-trick and end-of-hand pause delays | game_controller.lsl | Done |
| Suit-violation re-prompt fix (dummy plays) | play_engine.lsl | Done |
| Dummy HUD card texture orientation | hud_controller.lsl | **Pending** |

## Pending: Dummy HUD Texture Fix

`setDummyCardPrim` in `hud_controller.lsl` currently uses `<-1.0, 1.0, 0.0>` repeats. The correct value needs to be verified in-world. Candidates to try (in order):

1. `<-1.0, -1.0, 0.0>` — same as `setCardPrim` (hcards), no rotation compensation
2. `<1.0, -1.0, 0.0>` — flip Y only
3. `<1.0, 1.0, 0.0>` — no flip

Once the correct value is confirmed, update `setDummyCardPrim` in `hud_controller.lsl`.

---

## In-World Build Reference

### Card Textures

Upload **53 textures** total. Names are case-sensitive.

**Card faces (52):** format `<rank><suit>`

```
2C 3C 4C 5C 6C 7C 8C 9C TC JC QC KC AC
2D 3D 4D 5D 6D 7D 8D 9D TD JD QD KD AD
2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH AH
2S 3S 4S 5S 6S 7S 8S 9S TS JS QS KS AS
```

**Card back (1):** `purple_back`

**Where to put them:** `llGetInventoryKey` only finds items in the same prim as the script.
- Textures for the table → prim containing `card_display.lsl`
- Textures for the HUD → prim containing `hud_controller.lsl`

---

### Table Prims (17 new prims)

Link all into the existing table linkset. Original root prim must stay root.

**Trick prims (4)** — one per seat, show the card played in the current trick:

| Name | Position |
|---|---|
| `trick_N` | North side of table centre |
| `trick_S` | South side of table centre |
| `trick_E` | East side of table centre |
| `trick_W` | West side of table centre |

Suggested size: ~0.12 × 0.18 m (card ratio), lying flat.

**Dummy hand prims (13)** — named `dummy_0` through `dummy_12`

Starting position doesn't matter — script repositions them at runtime. Same size as trick prims.

---

### HUD Prims (27 new prims)

Link all into the HUD linked object. The original root prim (with `hud_controller.lsl`) must stay root.

**Hand prims (13):** `hcard_0` through `hcard_12` — player's own cards, left-to-right in suit order (S→C, high→low)

**Dummy prims (13):** `dcard_0` through `dcard_12` — dummy's cards, shown on HUD when playing for dummy

**Ready prim (1):** `start` — green prim button; shows "Ready" floating text on attach, "[ Ready ]" in bright green when clicked. Text clears when the deal arrives.

After building, place the complete HUD object into **each of the four seat prim inventories** (seat.lsl gives it from the seat prim, not the root prim).

---

### Dummy Layout Notecard (optional)

Create a notecard named `card_layout` in the prim containing `card_display.lsl`. Use `#` for comments.

```
# card_layout
north_base=<-0.72, 1.10, 0.02>
north_spread=<0.12, 0.0, 0.0>
north_rot=<0.0, 0.0, 0.0, 1.0>

south_base=<-0.72, -1.10, 0.02>
south_spread=<0.12, 0.0, 0.0>
south_rot=<0.0, 0.0, 1.0, 0.0>

east_base=<1.10, -0.72, 0.02>
east_spread=<0.0, 0.12, 0.0>
east_rot=<0.0, 0.0, 0.707, 0.707>

west_base=<-1.10, -0.72, 0.02>
west_spread=<0.0, 0.12, 0.0>
west_rot=<0.0, 0.0, -0.707, 0.707>
```

To find the right values: rez a test prim on the table surface, note its local position (Edit > local coords). Use a debug script on `dummy_0` to print `llGetLocalPos()` and `llGetLocalRot()` on click.

---

### Verification Checklist

- [ ] Deal a hand — trick prims start blank
- [ ] Opening lead plays — correct card face appears on the trick prim
- [ ] After 4 cards played, trick prims stay visible for ~3 seconds then clear
- [ ] After opening lead, 13 dummy prims appear near the dummy seat, face-up
- [ ] As declarer: clicking a dummy prim highlights it; second click plays the card
- [ ] As declarer: HUD shows own hand as card images
- [ ] As declarer after dummy reveal: dummy cards appear in HUD same panel as own hand
- [ ] Two-click selection works on HUD card prims
- [ ] Playing a card removes it from the display (prim goes transparent)
- [ ] After hand ends, all trick and dummy prims clear
- [ ] Bidding dialogs still work (no regression)
- [ ] Fallback: removing hcard prims from HUD falls back to llDialog
