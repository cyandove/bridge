// hud_controller.lsl
// HUD object script for human players.
// Displays the player's private hand, provides bidding UI (multi-page dialog),
// and card selection for play.
//
// On attach, the HUD listens on a fixed handshake channel (-7769).
// When the player sits, the seat script sends "SEAT|N" on that channel via
// llRegionSayTo. The HUD records its seat ID, opens the private channel
// (-7770 - N), and closes the handshake listen.
//
// Commands received from table (via llRegionSayTo on private channel):
//   "HAND|seat|c0|c1|..."   — new hand dealt, update display
//   "BID_PROMPT"            — show bidding dialog
//   "PLAY_PROMPT"           — enable card selection mode
//
// Commands sent to table (via llSay on private channel):
//   "BID|bid_integer"
//   "PLAY|card_integer"

// ---------------------------------------------------------------------------
// Channels
// ---------------------------------------------------------------------------
integer HUD_HANDSHAKE_CHANNEL = -7769;  // fixed; seat pushes SEAT|N here on sit
// Private channel is -7770 - SEAT_ID, set dynamically after handshake

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
integer gSeatID        = -1;   // -1 = not yet assigned
integer gChannel       = 0;    // private channel, set after handshake
integer gHandshakeHandle = -1;
integer gListenHandle  = -1;

list    gHand          = [];
integer gSelectMode    = FALSE;
integer gBidMode       = FALSE;
integer gBidPage       = 1;
integer gCardPage      = 0;

// Bid encoding matches bidding_engine.lsl
integer BID_PASS     = 0;
integer BID_DOUBLE   = 1;
integer BID_REDOUBLE = 2;

// ---------------------------------------------------------------------------
// Card helpers
// ---------------------------------------------------------------------------
integer cardSuit(integer card) { return card / 13; }
integer cardRank(integer card) { return card % 13; }

list rankNames   = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"];
list suitSymbols = ["C","D","H","S"];

string cardStr(integer card) {
    return llList2String(rankNames, cardRank(card))
         + llList2String(suitSymbols, cardSuit(card));
}

// ---------------------------------------------------------------------------
// Hand display
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
// Bidding dialog
// One level per page (5 suit buttons + Pass + Dbl + Rdbl + Prev/Next = 9-10)
// ---------------------------------------------------------------------------
list buildBidPage(integer level) {
    list buttons = [];
    list suitLabels = ["C","D","H","S","N"];
    integer suit;
    for (suit = 0; suit < 5; suit++) {
        buttons += [(string)level + llList2String(suitLabels, suit)];
    }
    buttons += ["Pass", "Dbl", "Rdbl"];
    if (level > 1) buttons += ["<< Prev"];
    if (level < 7) buttons += ["Next >>"];
    return buttons;
}

showBidDialog(integer level) {
    gBidPage = level;
    list buttons = buildBidPage(level);
    llDialog(llGetOwner(), "Your bid (Level " + (string)level + "):", buttons, gChannel);
}

// ---------------------------------------------------------------------------
// Card selection dialog
// ---------------------------------------------------------------------------
showCardDialog(integer page) {
    gCardPage = page;
    integer start = page * 11;
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
    return -1;
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
// Open handshake listen (waiting for seat to send SEAT|N)
// ---------------------------------------------------------------------------
openHandshake() {
    if (gHandshakeHandle != -1) llListenRemove(gHandshakeHandle);
    gHandshakeHandle = llListen(HUD_HANDSHAKE_CHANNEL, "", NULL_KEY, "");
}

// ---------------------------------------------------------------------------
// Called once seat ID is known — switch to private channel
// ---------------------------------------------------------------------------
assignSeat(integer seatID) {
    gSeatID  = seatID;
    gChannel = -7770 - seatID;

    // Close handshake, open private channel
    if (gHandshakeHandle != -1) {
        llListenRemove(gHandshakeHandle);
        gHandshakeHandle = -1;
    }
    if (gListenHandle != -1) llListenRemove(gListenHandle);
    gListenHandle = llListen(gChannel, "", NULL_KEY, "");

    list seatNames = ["North","South","East","West"];
    llSetText("Bridge HUD\n" + llList2String(seatNames, seatID), <0.5,1,0.5>, 1.0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gSeatID  = -1;
        gChannel = 0;
        gHand    = [];
        gBidMode    = FALSE;
        gSelectMode = FALSE;
        llSetText("Bridge HUD\nAttach & sit", <0.5,0.5,0.5>, 1.0);
        openHandshake();
    }

    attach(key avatarID) {
        if (avatarID != NULL_KEY) {
            // Attached — open handshake listen, reset state
            gSeatID  = -1;
            gHand    = [];
            gBidMode    = FALSE;
            gSelectMode = FALSE;
            llSetText("Bridge HUD\nSit to connect", <0.5,0.5,0.5>, 1.0);
            openHandshake();
        } else {
            // Detached — clean up listens
            if (gHandshakeHandle != -1) {
                llListenRemove(gHandshakeHandle);
                gHandshakeHandle = -1;
            }
            if (gListenHandle != -1) {
                llListenRemove(gListenHandle);
                gListenHandle = -1;
            }
        }
    }

    listen(integer channel, string name, key id, string message) {
        // Handshake: seat sends "SEAT|N" when avatar sits
        if (channel == HUD_HANDSHAKE_CHANNEL) {
            list parts = llParseString2List(message, ["|"], []);
            if (llList2String(parts, 0) == "SEAT") {
                assignSeat((integer)llList2String(parts, 1));
            }
            return;
        }

        // Private channel commands from the table
        if (channel != gChannel) return;

        if (llGetSubString(message, 0, 3) == "HAND") {
            // "HAND|seat|c0|c1|..."
            list parts = llParseString2List(message, ["|"], []);
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

        // Dialog button responses
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
                integer idx = llListFindList(gHand, [card]);
                if (idx != -1) gHand = llDeleteSubList(gHand, idx, idx);
                updateHandDisplay();
                llSay(gChannel, "PLAY|" + (string)card);
            }
        }
    }

    touch_start(integer total) {
        if (gBidMode)    showBidDialog(gBidPage);
        if (gSelectMode) showCardDialog(gCardPage);
    }
}
