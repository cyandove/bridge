# Setup Instructions

Technical guide for building and deploying the Bridge table in Second Life.

---

## Overview of Objects

| Object | Contains |
|---|---|
| **Bridge Table** (root prim + linked seat prims) | All engine scripts, seat scripts, card display |
| **Bridge HUD** (separate object, worn by players) | `hud_controller.lsl` + `HUD_CONFIG` notecard |

All engine scripts communicate via `llMessageLinked` and must be inside the **same linked object**.

---

## Step 1 — Build the Table

Create a linked object with the following prims:

- **1 root prim** — the table surface (engine scripts go here)
- **4 seat prims** — one each for North, South, East, West, positioned around the table

Arrange seat prims so avatars face the table center when seated. Apply `llSitTarget` offsets are already set in `seat.lsl` (`<0, 0, 0.5>`) — adjust the vector if your seat geometry differs.

**Link order**: the root prim should be the table surface. Seat prims can be any link number; they do not need to be in a specific order since scripts communicate by message type, not link number.

---

## Step 2 — Add Scripts to the Table (Root Prim)

Place all of the following scripts into the **root prim's** inventory:

- `game_controller.lsl`
- `deck_manager.lsl`
- `bidding_engine.lsl`
- `play_engine.lsl`
- `scoring_engine.lsl`
- `bot_ai.lsl`
- `card_display.lsl`

In Second Life, open the root prim's inventory (Edit → Contents) and drag each script in.

---

## Step 3 — Configure and Add Seat Scripts

`seat.lsl` is a template. You need **four copies**, one per seat, each with a different `SEAT_ID`.

For each seat prim:

1. Open `seat.lsl` in a text editor
2. Change the line at the top:
   ```lsl
   integer SEAT_ID = 0;  // 0=North 1=South 2=East 3=West
   ```
3. Save the file with a distinct name (e.g. `seat_north.lsl`, `seat_south.lsl`, etc.)
4. Open the corresponding seat prim's inventory and add the script

Seat ID assignments:

| Seat | SEAT_ID |
|---|---|
| North | 0 |
| South | 1 |
| East | 2 |
| West | 3 |

---

## Step 4 — Build the HUD

Create a single HUD object to be worn as a HUD attachment. You only need **one HUD** — the seat pushes its ID to the HUD automatically when the avatar sits, so no per-seat configuration is required.

1. Add `hud_controller.lsl` to the HUD object's inventory
2. Name the object `Bridge HUD`
3. Place it in the **table root prim's inventory** — `seat.lsl` calls `llGiveInventory` when a player sits

No notecard is needed. When the avatar sits, the seat script sends `SEAT|N` to the HUD via `llRegionSayTo` on a fixed handshake channel (`-7769`). The HUD stores the seat ID and opens the correct private channel automatically.

The `notecards/` folder in this repo is no longer needed.

---

## Step 5 — Card Textures (Optional)

The current `card_display.lsl` uses floating text for the trick display and dummy hand. For a graphical card display using prim faces or card prims:

1. Upload 52 card face textures and 1 card back texture to your SL inventory
2. Name them consistently, e.g. `card_2C`, `card_AS`, `card_TH`
3. Modify `card_display.lsl` to call `llSetLinkPrimitiveParamsFast` targeting specific card display prims in the link set, passing `PRIM_TEXTURE` with the appropriate texture UUID

Card integer → texture name mapping:
```
suit = card / 13   (0=C 1=D 2=H 3=S)
rank = card % 13   (0=2 1=3 … 8=T 9=J 10=Q 11=K 12=A)
ranks = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"]
suits = ["C","D","H","S"]
name  = "card_" + rank + suit   // e.g. "card_AS", "card_2C"
```

---

## Step 6 — Permissions

Set the table object's permissions:

- **Move**: owner only (prevent guests from shifting the table)
- **Scripts**: running
- Transfer permissions on the HUD objects should be set to **Copy** so players keep their HUD after receiving it

For the `llGiveInventory` call in `seat.lsl` to work, the HUD objects in the table's inventory must have **Copy + Transfer** permissions.

---

## Script Communication Reference

All scripts use `llMessageLinked(LINK_SET, num, str, NULL_KEY)` on these message numbers:

| Constant | Value | Direction | Meaning |
|---|---|---|---|
| `MSG_GAME_START` | 100 | controller → deck | Shuffle and deal |
| `MSG_DEAL_DONE` | 101 | deck → controller | Hands dealt |
| `MSG_BIDDING_START` | 102 | controller → bidding | Reset auction |
| `MSG_CONTRACT_SET` | 103 | bidding → controller/scoring | Contract finalised |
| `MSG_PLAY_START` | 104 | controller → play | Begin card play |
| `MSG_TRICK_DONE` | 105 | play → controller/display | Trick complete |
| `MSG_HAND_DONE` | 106 | controller → scoring/display | All 13 tricks done |
| `MSG_RUBBER_DONE` | 107 | scoring → controller | Rubber complete |
| `MSG_BID_REQUEST` | 200 | controller → seat | Request a bid |
| `MSG_PLAY_REQUEST` | 201 | controller → seat | Request a card |
| `MSG_HAND_UPDATE` | 202 | deck → seats/bot | New hand data |
| `MSG_BID_ADVANCE` | 203 | bidding → controller | Next bidder |
| `MSG_BID_RESPONSE` | 300 | seat/bot → bidding | Bid submitted |
| `MSG_PLAY_RESPONSE` | 301 | seat/bot → play | Card played |
| `MSG_SCORE_UPDATE` | 400 | scoring → controller | Score state |
| `MSG_DUMMY_REVEAL` | 401 | play → display | Show dummy hand |
| `MSG_TRICK_PLAYED` | 402 | play → display/bot | Card placed in trick |
| `MSG_SEAT_OCCUPIED` | 403 | seat → controller/display | Human sat down |
| `MSG_SEAT_VACATED` | 404 | seat → controller/display | Human stood up |
| `MSG_BOT_BID_REQUEST` | 220 | seat → bot | Seat is empty, bot bids |
| `MSG_BOT_PLAY_REQUEST` | 221 | seat → bot | Seat is empty, bot plays |

---

## Private Listen Channels

Each seat uses a private listen channel for HUD ↔ table communication:

| Seat | Channel |
|---|---|
| North (0) | -7770 |
| South (1) | -7771 |
| East  (2) | -7772 |
| West  (3) | -7773 |

These are hardcoded in `seat.lsl` as `-7770 - SEAT_ID`. Change both `seat.lsl` and `hud_controller.lsl` if you need different channels.

---

## Checklist

- [ ] Table object built with root prim + 4 seat prims, all linked
- [ ] 7 engine scripts in root prim inventory
- [ ] 4 seat scripts (SEAT_ID 0–3) in corresponding seat prim inventories
- [ ] 1 HUD object built with `hud_controller.lsl`, named `Bridge HUD`
- [ ] HUD object placed in root prim inventory
- [ ] Table object permissions set appropriately
- [ ] HUD objects have Copy+Transfer permissions
- [ ] Touch table to verify scripts reset cleanly (floating text shows "Bridge Table")
- [ ] Sit on a seat to verify HUD is given and name tag updates
