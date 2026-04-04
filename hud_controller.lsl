// hud_controller.lsl
// HUD object script for human players.
// Displays the player's private hand, provides bidding UI (multi-page dialog),
// and card selection for play.
//
// The HUD receives commands from the table over a private channel
// (listenChannel = -7770 - SEAT_ID) and sends responses back on the same channel.
//
// Commands received from table (via llSay on private channel):
//   "HAND|seat|c0|c1|..."   — new hand dealt, update display
//   "BID_PROMPT"            — show bidding dialog
//   "PLAY_PROMPT"           — enable card selection mode
//
// Commands sent to table (via llSay on private channel):
//   "BID|bid_integer"
//   "PLAY|card_integer"
//
// The HUD determines its seat ID and private channel at runtime by reading
// a notecard "HUD_CONFIG" placed in inventory with one line: "seat=N"
// where N is 0-3.  Falls back to 0 if not found.

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
integer gSeatID      = 0;
integer gChannel     = -7770;
integer gListenHandle = -1;

list    gHand        = [];   // current hand (card integers)
integer gSelectMode  = FALSE; // TRUE = waiting for card selection touch
integer gBidMode     = FALSE; // TRUE = bidding UI active
integer gBidPage     = 0;    // 0 = levels 1-4, 1 = levels 5-7

// Bid encoding matches bidding_engine.lsl
integer BID_PASS     = 0;
integer BID_DOUBLE   = 1;
integer BID_REDOUBLE = 2;

// Notecard reading state
integer gNcLine  = 0;
key     gNcQuery = NULL_KEY;

// ---------------------------------------------------------------------------
// Card helpers
// ---------------------------------------------------------------------------
integer cardSuit(integer card) { return card / 13; }
integer cardRank(integer card) { return card % 13; }

list rankNames = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"];
list suitSymbols = ["C","D","H","S"];

string cardStr(integer card) {
    return llList2String(rankNames, cardRank(card))
         + llList2String(suitSymbols, cardSuit(card));
}

// ---------------------------------------------------------------------------
// Hand display on HUD floating text
// Format: one row per suit, sorted high to low
// ---------------------------------------------------------------------------
updateHandDisplay() {
    if (llGetListLength(gHand) == 0) {
        llSetText("No hand", <0.5,0.5,0.5>, 1.0);
        return;
    }

    string display = "";
    list suitPrefixes = ["C: ", "D: ", "H: ", "S: "];
    integer s;
    for (s = 0; s < 4; s++) {
        // Collect cards of this suit, sort high to low
        list suitCards = [];
        integer i;
        for (i = 0; i < llGetListLength(gHand); i++) {
            integer c = llList2Integer(gHand, i);
            if (cardSuit(c) == s) suitCards += [c];
        }
        // Sort descending by rank (insertion sort)
        integer n = llGetListLength(suitCards);
        integer j;
        for (i = 1; i < n; i++) {
            integer val = llList2Integer(suitCards, i);
            j = i - 1;
            while (j >= 0 && cardRank(llList2Integer(suitCards,j)) < cardRank(val)) {
                suitCards = llListReplaceList(suitCards,
                    [llList2Integer(suitCards,j)], j+1, j+1);
                j--;
            }
            suitCards = llListReplaceList(suitCards, [val], j+1, j+1);
        }

        string row = llList2String(suitPrefixes, s);
        integer k;
        for (k = 0; k < llGetListLength(suitCards); k++) {
            row += llList2String(rankNames, cardRank(llList2Integer(suitCards,k)));
        }
        if (row != llList2String(suitPrefixes, s)) {
            display += row + "\n";
        }
    }

    if (gBidMode)    display += "\n[BIDDING - touch to bid]";
    if (gSelectMode) display += "\n[SELECT CARD - touch HUD]";

    llSetText(display, <1,1,1>, 1.0);
}

// ---------------------------------------------------------------------------
// Bidding dialog — two pages
// Page 0: levels 1-4 (up to 20 bids) — shown as 3 rows of 4 suits + NT
// Page 1: levels 5-7
// Both pages include Pass, Dbl, Rdbl, and a Next/Prev button
//
// llDialog max 12 buttons.  Layout per page:
//   Row 1: 1C 1D 1H 1S 1N   (5 bids for that level)  — page 0
//   We show one level at a time with Prev/Next navigation.
//   Actually we'll use a compact layout: 3 bids per row, up to 4 levels.
//   Simplification: show all suits for two levels per page.
//
// Button labels encode the bid integer as text "BID:N" so we can decode.
// Visible label is human-readable like "1C".
// ---------------------------------------------------------------------------

// Build button list for a bid dialog page
// Shows 2 levels per page (each level = 5 buttons: 1C 1D 1H 1S 1N)
// Plus Pass, Dbl, Rdbl = 13 buttons — one too many for llDialog (max 12)
// So: show Pass+Dbl+Rdbl on every page, 3 suit bids per level, NT on next page
// Final layout (12 buttons):
//   [Pass] [Dbl] [Rdbl]
//   [L1C]  [L1D] [L1H]
//   [L1S]  [L1N] [L2C]
//   [L2D]  [L2H] [L2S]   <- L2N omitted, use [Next] instead?
// Simpler: split into level-per-page (5 + 3 special + next/prev = 8 buttons)

list buildBidPage(integer startLevel) {
    // 5 suit buttons + Pass + Dbl + Rdbl + Next/Prev = 9 buttons
    list buttons = [];
    list suitLabels = ["C","D","H","S","N"];
    integer suit;
    for (suit = 0; suit < 5; suit++) {
        integer bid = startLevel * 5 + suit;
        buttons += [(string)startLevel + llList2String(suitLabels, suit)];
    }
    buttons += ["Pass", "Dbl", "Rdbl"];
    if (startLevel > 1) buttons += ["<< Prev"];
    if (startLevel < 7) buttons += ["Next >>"];
    return buttons;
}

showBidDialog(integer level) {
    gBidPage = level;
    list buttons = buildBidPage(level);
    string prompt = "Your bid (Level " + (string)level + "):";
    llDialog(llGetOwner(), prompt, buttons, gChannel);
}

// ---------------------------------------------------------------------------
// Card selection dialog — show hand as buttons (max 12 at a time)
// Cards shown as "AS", "TC", etc.
// If hand > 12 cards, paginate (first deal: 13 cards — need 2 pages)
// ---------------------------------------------------------------------------
integer gCardPage = 0;

showCardDialog(integer page) {
    gCardPage = page;
    integer start = page * 11;  // 11 cards per page, leave room for Next
    integer end   = start + 10;
    if (end >= llGetListLength(gHand)) end = llGetListLength(gHand) - 1;

    list buttons = [];
    integer i;
    for (i = start; i <= end; i++) {
        buttons += [cardStr(llList2Integer(gHand, i))];
    }
    if (start > 0)                        buttons += ["<< Prev"];
    if (end < llGetListLength(gHand) - 1) buttons += ["Next >>"];

    llDialog(llGetOwner(), "Play a card:", buttons, gChannel);
}

// ---------------------------------------------------------------------------
// Parse bid from button label
// ---------------------------------------------------------------------------
integer parseBidButton(string label) {
    if (label == "Pass")   return BID_PASS;
    if (label == "Dbl")    return BID_DOUBLE;
    if (label == "Rdbl")   return BID_REDOUBLE;

    list suitMap = ["C","D","H","S","N"];
    integer level = (integer)llGetSubString(label, 0, 0);
    string suitChar = llGetSubString(label, 1, 1);
    integer suit = llListFindList(suitMap, [suitChar]);
    if (level >= 1 && level <= 7 && suit >= 0) {
        return level * 5 + suit;
    }
    return -1; // not a bid
}

// ---------------------------------------------------------------------------
// Parse card from button label (e.g. "AS" -> card integer)
// ---------------------------------------------------------------------------
integer parseCardButton(string label) {
    if (llStringLength(label) < 2) return -1;
    string rankChar = llGetSubString(label, 0, 0);
    string suitChar = llGetSubString(label, 1, 1);

    list rankMap  = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"];
    list suitMap2 = ["C","D","H","S"];

    integer rank = llListFindList(rankMap,  [rankChar]);
    integer suit = llListFindList(suitMap2, [suitChar]);
    if (rank < 0 || suit < 0) return -1;
    return suit * 13 + rank;
}

// ---------------------------------------------------------------------------
// Config notecard reading
// ---------------------------------------------------------------------------
readConfig() {
    if (llGetInventoryType("HUD_CONFIG") == INVENTORY_NOTECARD) {
        gNcLine  = 0;
        gNcQuery = llGetNotecardLine("HUD_CONFIG", gNcLine);
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gSeatID  = 0;
        gChannel = -7770;
        readConfig();
        llSetText("Bridge HUD\nWaiting...", <0.5,0.5,0.5>, 1.0);
    }

    dataserver(key query, string data) {
        if (query != gNcQuery) return;
        if (data == EOF) return;

        // Parse "seat=N"
        list parts = llParseString2List(data, ["="], []);
        if (llList2String(parts, 0) == "seat") {
            gSeatID  = (integer)llList2String(parts, 1);
            gChannel = -7770 - gSeatID;
        }

        gNcLine++;
        gNcQuery = llGetNotecardLine("HUD_CONFIG", gNcLine);

        // Open listen after config loaded
        if (gListenHandle != -1) llListenRemove(gListenHandle);
        gListenHandle = llListen(gChannel, "", NULL_KEY, "");
    }

    attach(key id) {
        if (id != NULL_KEY) {
            // HUD was attached — open listen channel
            if (gListenHandle != -1) llListenRemove(gListenHandle);
            gListenHandle = llListen(gChannel, "", NULL_KEY, "");
            readConfig();
        } else {
            if (gListenHandle != -1) {
                llListenRemove(gListenHandle);
                gListenHandle = -1;
            }
        }
    }

    listen(integer channel, string name, key id, string message) {
        if (channel != gChannel) return;

        // Commands from the table
        if (llGetSubString(message, 0, 3) == "HAND") {
            // "HAND|seat|c0|c1|..."
            list parts = llParseString2List(message, ["|"], []);
            // parts[0]="HAND", parts[1]=seat, parts[2..]=cards
            gHand = [];
            integer i;
            for (i = 2; i < llGetListLength(parts); i++) {
                gHand += [(integer)llList2String(parts, i)];
            }
            gBidMode    = FALSE;
            gSelectMode = FALSE;
            updateHandDisplay();
            return;
        }

        if (message == "BID_PROMPT") {
            gBidMode    = TRUE;
            gSelectMode = FALSE;
            updateHandDisplay();
            showBidDialog(1);
            return;
        }

        if (message == "PLAY_PROMPT") {
            gSelectMode = TRUE;
            gBidMode    = FALSE;
            updateHandDisplay();
            showCardDialog(0);
            return;
        }

        // Responses from dialog buttons
        if (gBidMode) {
            if (message == "Next >>") {
                integer nextPage = gBidPage + 1;
                if (nextPage > 7) nextPage = 7;
                showBidDialog(nextPage);
                return;
            }
            if (message == "<< Prev") {
                integer prevPage = gBidPage - 1;
                if (prevPage < 1) prevPage = 1;
                showBidDialog(prevPage);
                return;
            }
            integer bid = parseBidButton(message);
            if (bid >= 0) {
                gBidMode = FALSE;
                updateHandDisplay();
                llSay(gChannel, "BID|" + (string)bid);
            }
            return;
        }

        if (gSelectMode) {
            if (message == "Next >>") {
                showCardDialog(gCardPage + 1);
                return;
            }
            if (message == "<< Prev") {
                showCardDialog(gCardPage - 1);
                return;
            }
            integer card = parseCardButton(message);
            if (card >= 0) {
                gSelectMode = FALSE;
                // Remove card from local hand display
                integer idx = llListFindList(gHand, [card]);
                if (idx != -1) gHand = llDeleteSubList(gHand, idx, idx);
                updateHandDisplay();
                llSay(gChannel, "PLAY|" + (string)card);
            }
        }
    }

    touch_start(integer total) {
        // Touch HUD to re-show current dialog if missed
        if (gBidMode)    showBidDialog(gBidPage);
        if (gSelectMode) showCardDialog(gCardPage);
    }
}
