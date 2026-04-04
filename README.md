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

1. Approach the Bridge table and touch any of the four seat prims (North, South, East, West)
2. A dialog will appear — confirm the seat you want
3. You will automatically receive a **Bridge HUD** — attach it to your screen
4. The game starts automatically once at least one player is seated (bots fill the remaining seats)

To leave mid-game, simply stand up. The bot for your seat will take over your hand.

---

## The HUD

The HUD displays your private hand, sorted by suit:

```
S: AKJT
H: Q975
D: 83
C: KJ4
```

- **During bidding**: a dialog appears asking for your bid
- **During play**: a dialog appears listing your legal cards to play
- **Touch the HUD** at any time to re-open a dialog you may have missed

---

## Bidding

The auction determines the contract — which suit is trump (or No Trump), how many tricks the declaring side commits to win, and who the declarer is.

### How to bid

When it is your turn, a dialog appears. Select your bid:

- **1C through 7NT** — a contract bid (level × suit)
- **Pass** — decline to bid
- **Dbl** — double the opponents' last bid (increases the stakes)
- **Rdbl** — redouble after being doubled (increases stakes further)

Use **Next >>** and **<< Prev** to page through bid levels.

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

After the opening lead, the **declarer's partner** (the **dummy**) lays their entire hand face-up on the table. The declarer plays both their own hand and the dummy's hand for the rest of the deal. The dummy takes no further part in play.

### Playing cards

Play proceeds clockwise. When it is your turn, a dialog lists your playable cards. Select the card you wish to play.

**You must follow suit** if you hold a card of the suit led. If you have no cards of that suit, you may play any card — including a trump.

### Winning tricks

- The highest card of the **led suit** wins, unless a trump is played
- If any **trump** cards are played, the highest trump wins
- The winner of each trick leads to the next

### Winning the hand

The declarer's side needs to take at least `contract level + 6` tricks. For example, a contract of **4 Spades** requires 10 tricks.

---

## Scoring

Scores are posted to chat at the end of each hand.

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

You can sit down mid-rubber to take over a bot's seat and cards at any time.

---

## Quick Reference

| Action | How |
|---|---|
| Sit | Touch a seat prim |
| Receive HUD | Automatic on sit |
| Open bid/play dialog | Automatic on your turn; touch HUD to re-open |
| Leave | Stand up (bot takes over) |
| Re-start | Touch table when idle |
