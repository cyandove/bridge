# Setup Instructions

Technical guide for building and deploying the Bridge table in Second Life.

---

## Overview of Objects

| Object | Contains |
|---|---|
| **Bridge Table** (root prim + linked seat prims) | All engine scripts, seat scripts, card display |
| **Bridge HUD** (separate object, worn by players) | `hud_controller.lsl` |

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

`seat.lsl` is identical for all four seats — no editing required. Each seat prim is configured via a notecard named `seat_config` placed in that prim's inventory.

For each seat prim:

1. Open the corresponding seat prim's inventory and add `seat.lsl`
2. From the `notecards/` folder, drag the matching `seat_config.txt` into the prim's inventory and rename it to `seat_config`

| Seat | Notecard file | `seat` value |
|---|---|---|
| North | `notecards/North/seat_config.txt` | 0 |
| South | `notecards/South/seat_config.txt` | 1 |
| East  | `notecards/East/seat_config.txt`  | 2 |
| West  | `notecards/West/seat_config.txt`  | 3 |

If the script shows `(no seat_config)` in floating text, the notecard is missing or misnamed.

---

## Step 4 — Build the HUD

The HUD is a **multi-prim linked object**. See `plan-add-card-graphics.md` § "In-World Build" for the full build procedure (26 card prims + root prim). Quick summary:

1. Build the root prim, add `hud_controller.lsl` to its inventory
2. Add 13 `hcard_0`…`hcard_12` prims (player's hand), 13 `dcard_0`…`dcard_12` prims (dummy hand), and 1 green prim named `start` (the Ready button), then link them all — the original root must remain root
3. Upload 53 card textures (52 faces + `purple_back`) into the **same prim as `hud_controller.lsl`**
4. Name the object `Bridge HUD`
5. Place it in **each of the four seat prims** — `seat.lsl` calls `llGiveInventory` from the seat prim, so the HUD must be in each seat's inventory

No notecard is needed in the HUD itself. When the avatar sits (or attaches the HUD while already seated), the seat script sends `SEAT|N` to the HUD via `llRegionSayTo` on a fixed handshake channel (`-7769`). The HUD stores the seat ID and opens the correct private channel automatically.

---

## Step 5 — Add Card Prims to the Table

The table needs 17 additional prims for the graphical card display. See `plan-add-card-graphics.md` § "In-World Build" for detailed positioning. Quick summary:

- **4 trick prims** named `trick_N`, `trick_S`, `trick_E`, `trick_W` — laid flat near table centre, one per seat
- **13 dummy prims** named `dummy_0`…`dummy_12` — laid flat, starting positions don't matter (script repositions them at runtime)
- Upload 53 card textures into the **same prim as `card_display.lsl`**
- Link all new prims into the existing table linkset; original root prim must stay root
- Optionally create a `card_layout` notecard to tune dummy hand positions (see `plan-add-card-graphics.md`)

---

## Step 6 — Permissions

Set the table object's permissions:

- **Move**: owner only (prevent guests from shifting the table)
- **Scripts**: running
- Transfer permissions on the HUD objects should be set to **Copy** so players keep their HUD after receiving it

For the `llGiveInventory` call in `seat.lsl` to work, the HUD objects in the table's inventory must have **Copy + Transfer** permissions.

---

## Script Communication Reference

All scripts use `llMessageLinked(LINK_SET, num, str, ...)` on these message numbers. Most use `NULL_KEY` as the key parameter; exceptions are noted.

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
| `MSG_GAME_RESET`  | 108 | controller → all | Abort hand (0) or full reset (1) |
| `MSG_CHAT`        | 109 | any engine → controller | Chat routed to seated players only |
| `MSG_BID_REQUEST` | 200 | controller → seat | Request a bid |
| `MSG_PLAY_REQUEST` | 201 | controller → seat | Request a card |
| `MSG_HAND_UPDATE` | 202 | deck → seats/bot | New hand data |
| `MSG_BID_ADVANCE` | 203 | bidding → controller | Next bidder + auction state |
| `MSG_BID_MADE` | 205 | bidding → seats | A bid was made (for hover text) |
| `MSG_REMOVE_CARD` | 212 | play → deck/seat | Card played — remove from hand |
| `MSG_BOT_BID_REQUEST` | 220 | seat → bot | Seat is empty, bot bids |
| `MSG_BOT_PLAY_REQUEST` | 221 | seat → bot | Seat is empty, bot plays |
| `MSG_BID_RESPONSE` | 300 | seat/bot → bidding | Bid submitted |
| `MSG_PLAY_RESPONSE` | 301 | seat/bot → play | Card played |
| `MSG_SCORE_UPDATE` | 400 | scoring → controller | Score state |
| `MSG_DUMMY_REVEAL` | 401 | play → seat/display | Show dummy hand (seat updates hover text) |
| `MSG_TRICK_PLAYED` | 402 | play → display/bot | Card placed in trick |
| `MSG_SEAT_OCCUPIED` | 403 | seat → controller | Human sat down (key param = avatar key) |
| `MSG_SEAT_VACATED` | 404 | seat → controller | Human stood up |

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
- [ ] `seat.lsl` + correct `seat_config` notecard in each of the 4 seat prim inventories
- [ ] HUD built: root + 13 `hcard_*` + 13 `dcard_*` + `start` prim linked, named `Bridge HUD`
- [ ] 53 card textures in the prim containing `hud_controller.lsl`
- [ ] HUD object placed in **each of the 4 seat prim** inventories
- [ ] 4 trick prims + 13 dummy prims linked into table linkset
- [ ] 53 card textures in the prim containing `card_display.lsl`
- [ ] Table object permissions set appropriately
- [ ] HUD objects have Copy+Transfer permissions
- [ ] Verify table floating text shows "Bridge Table / Touch a seat to join" on rez
- [ ] Sit on a seat — verify HUD is given, name tag updates, and a private message says "Touch the table when all players are ready to start"
- [ ] Click Ready button on HUD — verify seat hover text turns green with "Ready"
- [ ] Touch table → Start Game — verify deal starts
- [ ] Touch table mid-hand → Status — verify status appears in private chat (not local chat)
