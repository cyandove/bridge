# Future Work

Ideas for branches after `add-card-graphics`.

---

## Near-term

**Touch table for menu**
Replace "touch to start" with a proper menu: Start Game, End Game, Reset Game. Avoids accidental starts and gives a clean way to abort a rubber.

**Ready button on HUD**
Add a "Ready" button players press before each deal starts. The table waits until all humans have clicked Ready (or a timeout) before dealing. Removes the need to touch the table.

**Reset game if last player stands**
If all human players stand up mid-rubber, automatically reset the table to IDLE so the next group doesn't inherit a broken game state.

---

## Medium-term

**Show hand point count**
Automatically calculate and display HCP (high card points) on the HUD when the hand is dealt. Saves players from counting mentally every hand.

**HUD flip for dummy hand**
The infrastructure for flipping the HUD 180° around the Y axis (to show dummy cards on the back face) is in `setHudFace()` in `hud_controller.lsl` — currently disabled. Re-enable once the back-panel dcard prims are correctly positioned and the texture orientation is confirmed.

**Better HUD hand vs dummy distinction**
Clearer visual separation between the player's own hand panel and dummy's hand panel — distinct background colour, label, or border.

---

## Polish / UX

**Red X on invalid bid buttons**
Instead of blanking invalid bid slots with `-`, show a distinct red marker. Makes it immediately obvious which bids are unavailable without having to read each button.

**Bid history in menu text**
When a player touches the table for status, include the full auction sequence so far (who bid what) in the chat output.
