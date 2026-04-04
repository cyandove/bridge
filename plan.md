# Bridge for Second Life — Implementation Plan

## Overview

Rubber Bridge for a single table of 4 players. All 4 seats are human seats; any vacant seat is filled by a bot. Bots live inside the table object — no separate avatar accounts required. Bot names and human display names float above their respective seat positions on the table surface.

## Game Variant

**Rubber Bridge** — play continues until one partnership wins 2 games (a rubber). Vulnerability is earned dynamically. Scores accumulate across hands within a rubber.

## Seat Model

- 4 seats: North, South, East, West
- Humans sit on seat prims; on sit they receive a HUD and take over from the bot
- On unsit, the bot reclaims the seat and inherits the remaining hand
- Floating text above each seat: bot name when vacant, avatar display name when occupied

## Data Model

### Cards
- Integer 0–51
- Suit: `card / 13` → 0=Clubs 1=Diamonds 2=Hearts 3=Spades
- Rank: `card % 13` → 0=2 1=3 … 9=Jack 10=Queen 11=King 12=Ace

### Bids
- Encoded as `level * 5 + suit` (0–34) where suit: 0=C 1=D 2=H 3=S 4=NT
- Special constants: PASS=35, DOUBLE=36, REDOUBLE=37

### Seats
- Integer constants: NORTH=0 SOUTH=1 EAST=2 WEST=3
- Partnerships: NS (0,1) vs EW (2,3)

### Game State
Managed by `game_controller.lsl`:
```
IDLE=0, WAITING=1, DEALING=2, BIDDING=3, PLAYING=4, SCORING=5
```

## Script Layout

| Script | Prim | Responsibility |
|---|---|---|
| `game_controller.lsl` | Table root | State machine, turn routing, message bus |
| `deck_manager.lsl` | Table | Shuffle, deal, hand storage, card lookup |
| `bidding_engine.lsl` | Table | Auction validation, contract determination |
| `play_engine.lsl` | Table | Trick validation, suit-following, trick winner, dummy |
| `scoring_engine.lsl` | Table | Rubber scoring, vulnerability, score display |
| `bot_ai.lsl` | Table | HCP bidding heuristics, basic card play for vacant seats |
| `seat.lsl` | Each seat prim (×4) | Sit/unsit, identity, floating name tag, HUD give |
| `card_display.lsl` | Table | Card textures for tricks and dummy hand |
| `hud_controller.lsl` | HUD object | Private hand, bidding UI, play card selection |

## Inter-Script Communication

All scripts in the same linked object communicate via `llMessageLinked`.

Message format: `num` = message type constant, `str` = pipe-delimited payload, `id` = NULL_KEY or sender key.

Key message types (defined as integer constants shared via notecard `MSG_CONSTANTS`):

```
// Game flow
MSG_GAME_START        = 100
MSG_DEAL_DONE         = 101
MSG_BIDDING_START     = 102
MSG_CONTRACT_SET      = 103
MSG_PLAY_START        = 104
MSG_TRICK_DONE        = 105
MSG_HAND_DONE         = 106
MSG_RUBBER_DONE       = 107

// Requests to seat/bot
MSG_BID_REQUEST       = 200   // str = "seat|auction_so_far"
MSG_PLAY_REQUEST      = 201   // str = "seat|hand|trick_so_far|trump|dummy_hand"
MSG_HAND_UPDATE       = 202   // str = "seat|card0|card1|..."

// Responses from seat/bot
MSG_BID_RESPONSE      = 300   // str = "seat|bid"
MSG_PLAY_RESPONSE     = 301   // str = "seat|card"

// Display
MSG_SCORE_UPDATE      = 400
MSG_DUMMY_REVEAL      = 401
MSG_TRICK_PLAYED      = 402
MSG_SEAT_OCCUPIED     = 403   // str = "seat|avatar_name"
MSG_SEAT_VACATED      = 404   // str = "seat"
```

Human players relay their HUD input via a private listen channel back to their seat script, which then sends `MSG_BID_RESPONSE` or `MSG_PLAY_RESPONSE` into the link message bus.

## Game Flow

```
IDLE
  └─ touch table → prompt for players, start timer
WAITING_FOR_PLAYERS
  └─ at least 1 human OR auto-start → DEALING
DEALING
  └─ shuffle, deal 13 to each seat, send MSG_HAND_UPDATE to all seats → BIDDING
BIDDING
  └─ send MSG_BID_REQUEST to current seat
  └─ seat (human or bot) responds MSG_BID_RESPONSE
  └─ validate bid, advance turn
  └─ 3 passes after real bid → emit MSG_CONTRACT_SET → PLAYING
PLAYING
  └─ reveal dummy after opening lead
  └─ send MSG_PLAY_REQUEST to current seat
  └─ seat responds MSG_PLAY_RESPONSE
  └─ validate card, add to trick
  └─ 4 cards played → determine winner, emit MSG_TRICK_DONE
  └─ 13 tricks done → emit MSG_HAND_DONE → SCORING
SCORING
  └─ calculate trick score, update rubber score
  └─ check for game/rubber completion
  └─ if rubber done → MSG_RUBBER_DONE → IDLE
  └─ else → rotate dealer → DEALING
```

## Bidding Rules

- Bid must be strictly higher than current contract (higher level, or same level higher suit)
- Double: only when opponents hold current contract and it is undoubled
- Redouble: only when own side holds current contract and it is doubled
- Auction ends when 3 consecutive passes follow a real bid
- Opening bid of 1NT+ by either side starts vulnerability considerations

## Play Rules

- Declarer's LHO makes opening lead (face down until dummy revealed)
- After opening lead, dummy hand is laid face-up; declarer plays both hands
- Must follow suit if possible
- If void in led suit, may play any card (including trump)
- Trick won by highest trump, or highest card of led suit if no trump played
- Trick winner leads next trick

## Scoring (Rubber Bridge)

**Trick scores** (below the line):
- Clubs / Diamonds: 20 per trick
- Hearts / Spades: 30 per trick
- No Trump: 40 first trick, 30 each subsequent
- Doubled: ×2; Redoubled: ×4

**Game**: first side to accumulate 100+ trick points wins a game. Score resets below the line; both sides retain above-the-line scores.

**Vulnerability**: a side that has won one game is vulnerable.

**Overtricks** (above the line):
- Undoubled: suit value per trick
- Doubled non-vul: 100 per trick; doubled vul: 200 per trick
- Redoubled: ×2 of doubled values

**Undertricks** (above the line, to opponents):
- Undoubled non-vul: 50 each; undoubled vul: 100 each
- Doubled non-vul: 100/200/200… (first/second/third+)
- Doubled vul: 200/300/300…
- Redoubled: ×2

**Bonuses** (above the line):
- Winning rubber 2–0: 700
- Winning rubber 2–1: 500
- Slam (12 tricks) non-vul: 500; vul: 750
- Grand slam (13 tricks) non-vul: 1000; vul: 1500
- Honors (4 or 5 trump honors in one hand): 100 / 150

## Bot AI

### Bidding (`bot_ai.lsl`)

Simplified Standard American:

1. Count HCP: A=4 K=3 Q=2 J=1
2. Add distribution points for long suits (1 pt per card beyond 4)
3. Opening:
   - 15–17 balanced → 1NT
   - 12–21 unbalanced → 1-of-longest-suit
   - <12 → pass (or preempt with 7-card suit)
4. Response to partner's opening:
   - 0–5 → pass
   - 6–9 → raise or 1-level response
   - 10–12 → 2-level response or jump raise
   - 13+ → game forcing bid
5. Subsequent bids: simple limit bids toward game in best fit

### Card Play (`bot_ai.lsl`)

- **Opening lead vs NT**: 4th-best of longest suit; top of interior sequence
- **Opening lead vs suit**: top of doubleton; singleton (to get ruff); top of sequence
- **Second seat**: play low (unless holding top honors over dummy)
- **Third seat**: play high (finesse if possible)
- **Declarer play**: draw trump first if in suit contract; establish long suit

## Bot Name Tags

`card_display.lsl` (or `seat.lsl`) uses `llSetText` on each seat prim:
- Vacant: e.g., `"North\n[Bot]"` in light gray
- Occupied: e.g., `"North\nAvatarName"` in white

## HUD Design

Three panels on the HUD object:
1. **Hand panel**: 13 card slots sorted by suit (C D H S left to right), rank low to high. Touch a card to select it for play.
2. **Bid panel**: shown during bidding. Two pages via dialog:
   - Page 1: levels 1–4 (buttons: 1C 1D 1H 1S 1N 2C 2D 2H 2S 2N 3C … Pass Dbl Rdbl)
   - Page 2: levels 5–7
3. **Info panel**: current contract, vulnerability, trick count, whose turn

## LSL Memory Budget

| Script | Estimated size |
|---|---|
| game_controller.lsl | ~20 KB |
| deck_manager.lsl | ~12 KB |
| bidding_engine.lsl | ~18 KB |
| play_engine.lsl | ~20 KB |
| scoring_engine.lsl | ~14 KB |
| bot_ai.lsl | ~20 KB |
| seat.lsl (each) | ~8 KB |
| card_display.lsl | ~10 KB |
| hud_controller.lsl | ~18 KB |

All under the 64 KB per-script LSL limit.

## Implementation Order

1. `deck_manager.lsl` — foundation, testable standalone
2. `game_controller.lsl` — state machine skeleton
3. `seat.lsl` — sit/unsit, identity, name tags
4. `bidding_engine.lsl` + HUD bid UI
5. `play_engine.lsl` + HUD card UI
6. `scoring_engine.lsl`
7. `bot_ai.lsl`
8. `card_display.lsl`
9. `hud_controller.lsl` polish

## Assets Required

- 52 card face textures (upload to SL inventory)
- 1 card back texture
- Table mesh with 4 seat positions
- HUD object with 3 display panels
- (Optional) felt/green texture for table surface
