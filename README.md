# Bridge for Second Life

A full Rubber Bridge card game for a single Second Life table. Supports 1–4 human players; any empty seat is filled automatically by a bot.

---

## The Game

Bridge is a trick-taking card game for four players in two partnerships:
- **North & South** play together against **East & West**
- The game uses a standard 52-card deck
- Each hand consists of an auction (bidding) followed by 13 tricks of card play

This table plays **Rubber Bridge** — the classic social format. A rubber is won by the first side to win two games. A game is won by scoring 100 or more trick points below the line.

---

## Getting Started

1. Sit in any of the four seat prims (North, South, East, West)
2. You will automatically receive a **Bridge HUD** — attach it to your screen
3. Click the green **Ready** button on your HUD when you're ready to play
4. When your group is ready, **touch the table** and select **Start Game**
5. Bots fill any empty seats automatically

Game announcements (bids, plays, scores) are whispered privately to seated players only.

To leave mid-game, simply stand up. The bot for your seat will take over your hand.

---

## The HUD

The HUD is a linked object that displays your private hand as card images. Cards are arranged left-to-right in suit order (Spades → Clubs, high to low within each suit).

- **Ready button**: a green prim labelled **Ready** on the HUD. Click it before the deal to signal you're ready; it shows `[ Ready ]` in green. Clicking again un-readies. The button clears when your hand is dealt.
- **During bidding**: a dialog appears asking for your bid
- **During play**: click a card prim to highlight it (it lifts slightly and turns yellow). Click the same card again to play it. Click a different card to move the highlight.
- **Touch the table** at any time to open the table menu (Start Game, End Hand, Reset Table, Status)

### Playing for Dummy

When it is your turn to play for the dummy's hand, the HUD shows dummy's remaining cards. Select a card the same way — first click highlights, second click plays. Alternatively, click one of the dummy card prims floating on the table surface near the dummy seat.

---

## Bidding

The auction determines the contract — which suit is trump (or No Trump), how many tricks the declaring side commits to win, and who the declarer is.

### How to bid

When it is your turn, a dialog appears with a fixed 9-button grid:

```
[ levelC ] [ levelD ] [ levelH ]
[ levelS ] [ levelN ] [  Pass  ]
[ <<Prev ] [  Dbl   ] [ Next>> ]
```

- Suit and No Trump bids for the current level appear in the top two rows; invalid bids show **-**
- **Pass** is always available
- **Dbl** appears when you can legally double; **Rdbl** when you can redouble; otherwise **-**
- **Next >>** / **<< Prev** move between levels; **-** when there is nowhere to go
- Clicking **-** re-opens the same dialog
- The dialog opens at the lowest level where at least one bid is legal

### Bid levels

The level of a bid represents the number of tricks your side commits to take **beyond six** (the "book"). A bid of **3 Hearts** means your side will try to take 9 tricks with Hearts as trump.

### Suit ranking (low to high)

Clubs → Diamonds → Hearts → Spades → No Trump

A new bid must be strictly higher than the previous one — either a higher level, or the same level in a higher denomination.

### Ending the auction

The auction ends when three consecutive passes follow any real bid. The last real bid becomes the **contract**.

A passed-out hand (all four players pass immediately) is thrown in and re-dealt.

### The contract

After the auction, the table announces:
- The **level** and **suit** of the contract (e.g. *3 Hearts*)
- Whether it is **doubled** or **redoubled**
- The **declarer** — the player from the declaring side who first bid that suit

---

## Card Play

### Opening lead

The player to the **left of the declarer** makes the opening lead, face down. All other players see it at the same time.

### The dummy

After the opening lead, the **declarer's partner** (the **dummy**) lays their entire hand face-up on the table. The dummy's cards are shown above their seat for all to see, and update as cards are played. The declarer plays both their own hand and the dummy's hand for the rest of the deal. The dummy takes no further part in play.

### Playing cards

Play proceeds clockwise. When it is your turn, click a card on the HUD to highlight it, then click it again to play. The first click raises the card slightly and tints it yellow so you can see your selection before committing.

A dialog fallback is available if card prims are absent — touch the HUD to open it. The dialog shows your hand in a grid; **Next >>** / **<< Prev** page through suits with more than two cards. Void suits and empty slots show **-**.

When you are playing the **dummy's hand**, the HUD flips to show dummy's cards. You can also click the floating dummy prims on the table surface directly.

**You must follow suit** if you hold a card of the suit led. If you have no cards of that suit, you may play any card — including a trump.

### Winning tricks

- The highest card of the **led suit** wins, unless a trump is played
- If any **trump** cards are played, the highest trump wins
- The winner of each trick leads to the next

### Winning the hand

The declarer's side needs to take at least `contract level + 6` tricks. For example, a contract of **4 Spades** requires 10 tricks.

---

## Scoring

Scores are sent privately to all seated players at the end of each hand.

### Trick points (below the line — count toward game)

| Suit | Points per trick |
|---|---|
| Clubs, Diamonds | 20 |
| Hearts, Spades | 30 |
| No Trump | 40 (first), 30 (each after) |

Doubled contracts score double; redoubled score four times.

**A game is won when a side accumulates 100+ trick points below the line.**

### Vulnerability

Once a side wins a game, they become **vulnerable**. Vulnerable sides score higher bonuses for making contracts — but pay heavier penalties for going down.

### Overtricks (above the line)

Extra tricks beyond the contract:
- Undoubled: face value of the suit
- Doubled: 100/trick (non-vulnerable) or 200/trick (vulnerable)
- Redoubled: 200/trick (non-vulnerable) or 400/trick (vulnerable)

### Undertricks (above the line, scored by opponents)

Tricks short of the contract:
- Undoubled: 50/trick (non-vul) or 100/trick (vul)
- Doubled non-vul: 100 / 200 / 200 (1st / 2nd / 3rd+)
- Doubled vul: 200 / 300 / 300 (1st / 2nd / 3rd+)
- Redoubled: double the doubled values

### Bonuses

| Bonus | Non-vul | Vul |
|---|---|---|
| Small slam (12 tricks) | 500 | 750 |
| Grand slam (13 tricks) | 1000 | 1500 |
| Winning rubber 2–0 | 700 | — |
| Winning rubber 2–1 | 500 | — |
| Making doubled contract | 50 | 50 |
| Making redoubled contract | 100 | 100 |

---

## The Bots

Any unoccupied seat is played by a bot. Bots are named **North Bot**, **South Bot**, **East Bot**, and **West Bot**, and their names appear above their seat on the table.

Bots use a simplified Standard American bidding system based on high card points (HCP), and apply classic card play principles: second hand low, third hand high, lead fourth-best, ruff when void. They are reasonable opponents for casual play.

Bots take a short pause before acting (roughly two-thirds of a second per turn, with a one-second pause between tricks) so the game does not fly by too fast.

You can sit down mid-rubber to take over a bot's seat and cards at any time.

---

## Seat Hover Text

Each seat prim shows a floating label above it:

- **Direction & name** — North/South/East/West and the player's name (or bot name)
- **Ready** — shown in green on a human seat that has clicked the Ready button (clears when play begins)
- **Last bid** — shown during the auction; replaced by the contract on the declarer's seat and **Dummy** on the dummy's seat when play begins
- **Trick score** — running NS / EW trick count shown on all seats during play
- **Dummy's hand** — the dummy's remaining cards are displayed live above the dummy seat
- **Green highlight** — the seat whose turn it currently is glows green; a Ready seat also glows green

---

## Quick Reference

| Action | How |
|---|---|
| Sit | Touch a seat prim |
| Receive HUD | Automatic on sit |
| Signal ready | Click the green Ready button on HUD |
| Start game | Touch table → Start Game |
| End hand / reset | Touch table → End Hand or Reset Table |
| Check game state | Touch table → Status |
| Play a card | Click card prim to highlight, click again to play |
| Play for dummy | Click dummy prim on HUD or on table |
| Leave | Stand up (bot takes over) |
