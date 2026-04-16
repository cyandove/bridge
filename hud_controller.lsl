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
list    gDummyHand     = [];
integer gPlayingDummy  = FALSE;
integer gSelectMode    = FALSE;
integer gBidMode       = FALSE;
integer gBidPage       = 1;
integer gCardPage      = 0;

// Auction state for bid filtering (updated each time BID_PROMPT arrives)
integer gHighBid     = 0;   // 0 = no bid yet; 5..39 otherwise
integer gDoubled     = 0;   // 0=none 1=doubled 2=redoubled
integer gHighSide    = -1;  // partnership(high bidder): 0=NS 1=EW -1=none
integer gDoublerSide = -1;  // partnership(doubler):     0=NS 1=EW -1=none

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

    if (gBidMode)                      display += "\n[BIDDING - touch to bid]";
    if (gSelectMode && !gPlayingDummy) display += "\n[SELECT CARD - touch HUD]";
    if (gSelectMode &&  gPlayingDummy) display += "\n[PLAY FOR DUMMY - touch HUD]";

    llSetText(display, <1,1,1>, 1.0);
}

// ---------------------------------------------------------------------------
// Bidding dialog
// One level per page (5 suit buttons + Pass + Dbl + Rdbl + Prev/Next = 9-10)
// ---------------------------------------------------------------------------
integer minBidLevel() {
    integer m = (gHighBid + 1) / 5;
    if (m < 1) m = 1;
    if (m > 7) m = 7;
    return m;
}

list buildBidPage(integer level) {
    integer myPartnership = gSeatID / 2;
    list buttons = [];

    // Suits high-to-low: NT S H D C
    list suitLabels  = ["N", "S", "H", "D", "C"];
    list suitIndices = [4,    3,   2,   1,   0];
    integer i;
    for (i = 0; i < 5; i++) {
        integer bid = level * 5 + llList2Integer(suitIndices, i);
        if (bid > gHighBid)
            buttons += [(string)level + llList2String(suitLabels, i)];
    }

    buttons += ["Pass"];

    if (gHighBid > 0 && gDoubled == 0 && gHighSide != -1 && gHighSide != myPartnership)
        buttons += ["Dbl"];

    if (gDoubled == 1 && gDoublerSide != -1 && gDoublerSide != myPartnership)
        buttons += ["Rdbl"];

    integer minLevel = minBidLevel();
    if (level > minLevel) buttons += ["<< Prev"];
    if (level < 7)        buttons += ["Next >>"];
    return buttons;
}

showBidDialog(integer level) {
    integer minLevel = minBidLevel();
    if (level < minLevel) level = minLevel;
    if (level > 7)        level = 7;
    gBidPage = level;
    list buttons = buildBidPage(level);
    llDialog(llGetOwner(), "Your bid (Level " + (string)level + "):", buttons, gChannel);
}

// ---------------------------------------------------------------------------
// Card selection dialog
// ---------------------------------------------------------------------------
showCardDialog(integer page) {
    list hand = gHand;
    if (gPlayingDummy) hand = gDummyHand;
    gCardPage = page;
    integer start = page * 11;
    integer end   = start + 10;
    if (end >= llGetListLength(hand)) end = llGetListLength(hand) - 1;

    list buttons = [];
    integer i;
    for (i = start; i <= end; i++) {
        buttons += [cardStr(llList2Integer(hand, i))];
    }
    if (start > 0)                       buttons += ["<< Prev"];
    if (end < llGetListLength(hand) - 1) buttons += ["Next >>"];

    string prompt = "Play a card:";
    if (gPlayingDummy) prompt = "Play a card (dummy):";
    llDialog(llGetOwner(), prompt, buttons, gChannel);
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
    gSeatID      = seatID;
    gChannel     = -7770 - seatID;
    gHighBid     = 0;
    gDoubled     = 0;
    gHighSide    = -1;
    gDoublerSide = -1;
    gDummyHand   = [];
    gPlayingDummy = FALSE;

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
            // Announce to seat in case avatar is already sitting
            llRegionSay(HUD_HANDSHAKE_CHANNEL,
                "HUD_READY|" + (string)llGetOwner());
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
            gDummyHand    = [];
            gPlayingDummy = FALSE;
            gBidMode      = FALSE;
            gSelectMode   = FALSE;
            updateHandDisplay();
            return;
        }

        if (llGetSubString(message, 0, 9) == "DUMMY_HAND") {
            // "DUMMY_HAND|seat|c0|c1|..."
            list parts = llParseString2List(message, ["|"], []);
            gDummyHand = [];
            integer i;
            for (i = 2; i < llGetListLength(parts); i++) {
                gDummyHand += [(integer)llList2String(parts, i)];
            }
            return;
        }

        if (llGetSubString(message, 0, 9) == "BID_PROMPT") {
            // "BID_PROMPT|seat|high_bid|doubled|high_side|doubler_side"
            list parts   = llParseString2List(message, ["|"], []);
            gHighBid     = (integer)llList2String(parts, 2);
            gDoubled     = (integer)llList2String(parts, 3);
            gHighSide    = (integer)llList2String(parts, 4);
            gDoublerSide = (integer)llList2String(parts, 5);
            gBidMode    = TRUE;
            gSelectMode = FALSE;
            updateHandDisplay();
            showBidDialog(minBidLevel());
            return;
        }

        if (llGetSubString(message, 0, 10) == "PLAY_PROMPT") {
            // "PLAY_PROMPT|forDummy"
            list parts    = llParseString2List(message, ["|"], []);
            gPlayingDummy = (integer)llList2String(parts, 1);
            gSelectMode   = TRUE;
            gBidMode      = FALSE;
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
                showBidDialog(gBidPage - 1);
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
                if (gPlayingDummy) {
                    integer idx = llListFindList(gDummyHand, [card]);
                    if (idx != -1) gDummyHand = llDeleteSubList(gDummyHand, idx, idx);
                } else {
                    integer idx = llListFindList(gHand, [card]);
                    if (idx != -1) gHand = llDeleteSubList(gHand, idx, idx);
                }
                gPlayingDummy = FALSE;
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
