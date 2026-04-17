# Plan: Graphical Card Image Display

## Context

The current `card_display.lsl` uses `llSetText` floating text for tricks and dummy's hand. The user wants physical card-image prims: clickable dummy card prims on the table (so the declarer can play dummy by clicking the table) and graphical clickable card prims on the HUD (replacing the `llDialog` card-selection flow for both own hand and dummy hand). Bidding dialogs stay as-is.

---

## Architecture Summary

| Where | Prims added | Who clicks | Effect |
|---|---|---|---|
| Table linkset | 4 trick slots + 13 dummy slots | Declarer clicks a dummy prim | Sends play response directly |
| HUD object | 13 hand slots + 13 dummy slots | Player clicks any card | Sends play response via private channel |

---

## Part 1 — Table: Physical Card Prims

### 1a. Build the Prims

Add to the table linkset (all linked into the same object as the root prim):

- **4 trick prims** — one per seat, showing the card played in the current trick. Name: `trick_N`, `trick_S`, `trick_E`, `trick_W`
- **13 dummy prims** — one per dummy hand slot, laid out above/near the dummy seat. Name: `dummy_0` through `dummy_12`

Total: 17 new prims.

### 1b. Upload Textures (into root prim inventory)

- 52 card face textures named `<rank><suit>`: `AS`, `KS`, `2C`, `TH`, etc.
  - Rank codes: `2 3 4 5 6 7 8 9 T J Q K A`
  - Suit codes: `C D H S`
  - Formula: `rank = card % 13`, `suit = card / 13`, name = `rankNames[rank] + suitNames[suit]`
- 1 card back texture named `purple_back`

### 1c. Modify `card_display.lsl`

**File: `/Users/ajhk/repos/lsl/bridge/card_display.lsl`**

#### Link discovery at startup

```lsl
list gTrickLinks   = [-1, -1, -1, -1];   // indexed by seat N=0 S=1 E=2 W=3
list gDummyLinks   = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; // 13 slots
list gDummyCards   = [];   // parallel to gDummyLinks: card integer at each slot (-1=empty)

discoverLinks() {
    list trickNames = ["trick_N","trick_S","trick_E","trick_W"];
    integer total = llGetNumberOfPrims();
    integer i;
    for (i = 1; i <= total; i++) {
        string n = llGetLinkName(i);
        integer ti = llListFindList(trickNames, [n]);
        if (ti != -1)
            gTrickLinks = llListReplaceList(gTrickLinks, [i], ti, ti);
        if (llGetSubString(n, 0, 5) == "dummy_") {
            integer slot = (integer)llGetSubString(n, 6, -1);
            if (slot >= 0 && slot < 13)
                gDummyLinks = llListReplaceList(gDummyLinks, [i], slot, slot);
        }
    }
}
```

#### Texture helpers (no ternary operators)

```lsl
list rankNames = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"];
list suitNames = ["C","D","H","S"];

string cardTextureName(integer card) {
    return llList2String(rankNames, card % 13)
         + llList2String(suitNames, card / 13);
}

setCardPrim(integer linkNum, integer card) {
    string texName;
    if (card == -1) texName = "purple_back";
    else            texName = cardTextureName(card);
    key texKey = llGetInventoryKey(texName);
    if (texKey == NULL_KEY) return;
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_TEXTURE, ALL_SIDES, texKey, <1.0,1.0,0.0>, ZERO_VECTOR, 0.0
    ]);
}

clearCardPrim(integer linkNum) {
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_COLOR, ALL_SIDES, ZERO_VECTOR, 0.0
    ]);
}
```

#### Dynamic dummy prim positioning

When `MSG_DUMMY_REVEAL` arrives, the 13 dummy prims reposition and reorient to cluster near the dummy's actual seat. Define 4 sets of layout constants in the script (builder adjusts for their table geometry):

```lsl
// Local-space layout for each dummy seat (N=0 S=1 E=2 W=3).
// basePos: position of the first card (local to root prim).
// spread:  per-card offset vector (direction × spacing).
// cardRot: rotation applied to all 13 cards for that seat.
//
// Defaults assume a 2m × 2m table, cards ~0.12m wide, 0.02m above surface.
list gDummyBasePos = [
    <-0.72, 1.10, 0.02>,    // North
    <-0.72,-1.10, 0.02>,    // South
    < 1.10,-0.72, 0.02>,    // East
    <-1.10,-0.72, 0.02>     // West
];
list gDummySpread = [
    < 0.12, 0.0, 0.0>,      // North: cards go +X
    < 0.12, 0.0, 0.0>,      // South: cards go +X
    < 0.0,  0.12, 0.0>,     // East:  cards go +Y
    < 0.0,  0.12, 0.0>      // West:  cards go +Y
];
list gDummyCardRot = [
    <0.0, 0.0, 0.0, 1.0>,   // North: no rotation (faces up, readable from South)
    <0.0, 0.0, 1.0, 0.0>,   // South: rotated 180° around Z
    <0.0, 0.0, 0.707, 0.707>,// East: rotated 90°
    <0.0, 0.0,-0.707, 0.707> // West: rotated -90°
];
```

In `MSG_DUMMY_REVEAL` handler, after populating `gDummyCards`, reposition all 13 prims:

```lsl
vector   base   = llList2Vector(gDummyBasePos, dummySeat);
vector   spread = llList2Vector(gDummySpread,  dummySeat);
rotation rot    = llList2Rot(gDummyCardRot,    dummySeat);
integer  i;
for (i = 0; i < 13; i++) {
    integer linkNum = llList2Integer(gDummyLinks, i);
    if (linkNum != -1) {
        vector pos = base + spread * (float)i;
        llSetLinkPrimitiveParamsFast(linkNum, [
            PRIM_POS_LOCAL, pos,
            PRIM_ROT_LOCAL, rot
        ]);
    }
}
```

Then texture each prim. Cards are arranged suit by suit (S H D C, high to low within suit), matching the hand display format — so the visual layout is consistent with the HUD.

#### Message handler updates

- **`MSG_TRICK_PLAYED`** (`str = "seat|card"`): call `setCardPrim(llList2Integer(gTrickLinks, seat), card)`
- **`MSG_TRICK_DONE`**: clear all 4 trick prims
- **`MSG_DUMMY_REVEAL`** (`str = "dummySeat|c0|c1|..."`): reposition dummy prims (see above), populate `gDummyCards`, call `setCardPrim` for each slot
- **`MSG_REMOVE_CARD`** (`str = "seat|card"`): if seat == dummy seat, find slot in `gDummyCards`, call `clearCardPrim`, set that slot to -1
- **`MSG_HAND_DONE`**: clear all trick and dummy prims, reset `gDummyCards`, hide dummy prims (move off-table or set transparent)

#### Clickable dummy prims (declarer plays by clicking the table)

Add new state variables:
```lsl
integer gWaitingForDummyPlay = FALSE;
integer gDeclarerSeat        = -1;
integer gDummySeat           = -1;
```

Set `gDeclarerSeat` and `gDummySeat` on `MSG_CONTRACT_SET` (`str = "declarer|level|suit|doubled"`).

Set `gWaitingForDummyPlay = TRUE` when `MSG_PLAY_REQUEST` arrives with `forDummy = 1`. Clear it when `MSG_PLAY_RESPONSE` is sent or a new request arrives.

In `touch_start`:
```lsl
touch_start(integer total) {
    if (!gWaitingForDummyPlay) return;
    integer linkNum = llDetectedLinkNumber(0);
    integer slot = llListFindList(gDummyLinks, [linkNum]);
    if (slot == -1) return;
    integer card = llList2Integer(gDummyCards, slot);
    if (card == -1) return;   // slot already empty
    gWaitingForDummyPlay = FALSE;
    llMessageLinked(LINK_SET, MSG_PLAY_RESPONSE,
        (string)gDeclarerSeat + "|" + (string)card, NULL_KEY);
}
```

Note: `play_engine.lsl` still validates legality — if the card is illegal (wrong suit when following suit is possible), the engine will re-request. The table display doesn't need to pre-validate.

---

## Part 2 — HUD: Graphical Card Prims

### 2a. Build the HUD Prims

The HUD currently has one prim. Expand it to a multi-prim linked object:

- **Root prim**: `hud_controller.lsl` stays here; handles all `touch_start` events for the whole HUD
- **13 hand prims**: showing the player's own cards. Name: `hcard_0` through `hcard_12`
- **13 dummy prims**: showing dummy's cards. Name: `dcard_0` through `dcard_12`

Same card textures as the table (53 textures in the HUD's root prim inventory, or same names — SL allows each object to have its own inventory).

Place the HUD object in the table root prim's inventory so `seat.lsl` can give it out on sit.

### 2b. Modify `hud_controller.lsl`

#### Link discovery (same pattern as card_display.lsl)

```lsl
list gHandLinks  = [];   // 13 entries, link numbers for hcard_0..12
list gDCardLinks = [];   // 13 entries, link numbers for dcard_0..12
list gHandLinkCards  = [];   // parallel: card integer at each hand slot (-1=empty)
list gDCardLinkCards = [];   // parallel: card integer at each dummy slot

discoverLinks() { /* same pattern: scan llGetLinkName() for hcard_N and dcard_N */ }
```

#### Replace card-play dialog with prim display

When `HAND|seat|c0|c1|...` is received:
- Store `gHand` as before
- Map cards to `gHandLinks` slots (sort by suit high-to-low as the dialog does)
- Call `setCardPrim` for each occupied slot; `clearCardPrim` for empties

When `DUMMY_HAND|str` is received:
- Map dummy cards to `gDCardLinks` slots
- Call `setCardPrim` for each slot

When `PLAY_PROMPT|0` (own hand): set `gSelectMode = TRUE`, `gPlayingDummy = FALSE` — prims are now clickable
When `PLAY_PROMPT|1` (dummy hand): set `gSelectMode = TRUE`, `gPlayingDummy = TRUE`

#### touch_start (root prim handles all prim touches)

```lsl
touch_start(integer total) {
    if (!gSelectMode) return;
    integer linkNum = llDetectedLinkNumber(0);
    integer slot = -1;
    integer card = -1;

    if (!gPlayingDummy) {
        slot = llListFindList(gHandLinks, [linkNum]);
        if (slot != -1) card = llList2Integer(gHandLinkCards, slot);
    } else {
        slot = llListFindList(gDCardLinks, [linkNum]);
        if (slot != -1) card = llList2Integer(gDCardLinkCards, slot);
    }

    if (card == -1) return;
    gSelectMode = FALSE;
    llSay(gChannel, "PLAY|" + (string)card);
}
```

When `MSG_REMOVE_CARD` arrives (forwarded via `seat.lsl` on the private channel as a new `CARD_PLAYED|seat|card` message, or handled differently — see note below):
- Remove that card from the appropriate prim slot and call `clearCardPrim`

#### Text display

Keep `updateHandDisplay()` for the floating HUD text label (direction + suit rows). It serves as a visual reference even when prims are the primary interaction method.

Do **not** call `showCardDialog()` when `PLAY_PROMPT` arrives — interaction is now via prim clicks.

#### Bidding

No change — `BID_PROMPT` still opens `llDialog`. Touch on the HUD root prim re-shows the bid dialog when `gBidMode = TRUE`.

---

## Seat/Table Changes Required

`seat.lsl` currently forwards `MSG_REMOVE_CARD` to the dummy seat's hover text. The HUD also needs to know when a card is removed from dummy's hand. Add to `seat.lsl`'s `MSG_REMOVE_CARD` handler: if this seat is the **dummy's partner** (declarer), also send the remove message to the declarer's HUD:

```lsl
// In MSG_REMOVE_CARD handler in seat.lsl:
if (gIsHuman && gSeatID == (dummySeat ^ 1)) {
    llRegionSayTo(gAvatarKey, listenChannel(),
        "CARD_PLAYED|" + llList2String(parts, 0) + "|" + llList2String(parts, 1));
}
```

The HUD listens for `CARD_PLAYED|seat|card` and clears the appropriate dummy prim slot.

---

## Fallback

If link discovery fails (prims missing or misnamed), `gHandLinks` / `gDCardLinks` will contain -1 entries. Guard all `setCardPrim` calls with `if (linkNum != -1)`. The `llDialog` path can remain as a fallback: if no hand prims are found, `showCardDialog()` is called as before.

---

## Files to Modify

- `/Users/ajhk/repos/lsl/bridge/card_display.lsl` — major rewrite
- `/Users/ajhk/repos/lsl/bridge/hud_controller.lsl` — replace card dialog with prim display
- `/Users/ajhk/repos/lsl/bridge/seat.lsl` — add `CARD_PLAYED` forward to declarer HUD

---

## Verification

1. Build table card prims (17), link them, name them, upload textures to root prim
2. Build HUD card prims (26 + root), link, name, upload textures
3. Deal a hand — trick prims appear blank; dummy hand populates after opening lead
4. As declarer: click a dummy card prim on the table — card plays, prim clears
5. As any human: HUD shows own hand as card images; clicking a card during play sends it
6. As declarer: HUD shows dummy hand; clicking a dummy card on HUD also sends the play
7. Play an illegal card — `play_engine` re-requests; HUD/table re-enables click mode
