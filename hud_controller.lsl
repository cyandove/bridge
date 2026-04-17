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
integer gPendingPlayPrompt = FALSE;

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
// Hand/card helpers
// ---------------------------------------------------------------------------

list sortedSuitCards(list hand, integer suit) {
    list result = [];
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        integer c = llList2Integer(hand, i);
        if (cardSuit(c) == suit) result += [c];
    }
    integer n = llGetListLength(result);
    integer j;
    for (i = 1; i < n; i++) {
        integer val = llList2Integer(result, i);
        j = i - 1;
        while (j >= 0 && cardRank(llList2Integer(result, j)) < cardRank(val)) {
            result = llListReplaceList(result,
                [llList2Integer(result, j)], j+1, j+1);
            j--;
        }
        result = llListReplaceList(result, [val], j+1, j+1);
    }
    return result;
}

// Build the "S: A K J\nH: Q T 9\n..." portion of a hand display string
string handSuitRows(list hand) {
    list suitLabels = ["C", "D", "H", "S"];
    string out = "";
    integer s;
    for (s = 3; s >= 0; s--) {
        list sc = sortedSuitCards(hand, s);
        string row = llList2String(suitLabels, s) + ": ";
        if (llGetListLength(sc) == 0) {
            row += "-";
        } else {
            integer k;
            for (k = 0; k < llGetListLength(sc); k++) {
                if (k > 0) row += " ";
                row += llList2String(rankNames, cardRank(llList2Integer(sc, k)));
            }
        }
        out += row + "\n";
    }
    return out;
}

// ---------------------------------------------------------------------------
// Hand display
// ---------------------------------------------------------------------------
updateHandDisplay() {
    list dirs = ["North","South","East","West"];
    string dir = llList2String(dirs, gSeatID);

    if (llGetListLength(gHand) == 0) {
        llSetText("Bridge HUD\n" + dir, <0.5,1,0.5>, 1.0);
        return;
    }

    string display = "Bridge HUD\n" + dir + "\n";
    if (gSelectMode && gPlayingDummy) display += "[PLAY FOR DUMMY - touch HUD]\n";
    display += "\n" + handSuitRows(gHand);

    if (gBidMode)                       display += "[BIDDING - touch to bid]";
    if (gSelectMode && !gPlayingDummy)  display += "[SELECT CARD - touch HUD]";

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

// Fixed 9-button grid for bidding.
// Layout (llDialog fills bottom-to-top, left-to-right):
//   Row 2 (top):    [ levelC ] [ levelD ] [ levelH ]
//   Row 1 (middle): [ levelS ] [ levelN ] [  Pass  ]
//   Row 0 (bottom): [ <<Prev ] [  Dbl   ] [ Next>> ]
list buildBidPage(integer level) {
    integer myPartnership = gSeatID / 2;

    // Suit bids: show label if valid, else "-"
    string cBtn = "-"; string dBtn = "-"; string hBtn = "-";
    string sBtn = "-"; string nBtn = "-";
    if (level * 5 + 0 > gHighBid) cBtn = (string)level + "C";
    if (level * 5 + 1 > gHighBid) dBtn = (string)level + "D";
    if (level * 5 + 2 > gHighBid) hBtn = (string)level + "H";
    if (level * 5 + 3 > gHighBid) sBtn = (string)level + "S";
    if (level * 5 + 4 > gHighBid) nBtn = (string)level + "N";

    // Dbl / Rdbl / "-"
    string dblBtn = "-";
    if (gHighBid > 0 && gDoubled == 0 && gHighSide != -1 && gHighSide != myPartnership)
        dblBtn = "Dbl";
    if (gDoubled == 1 && gDoublerSide != -1 && gDoublerSide != myPartnership)
        dblBtn = "Rdbl";

    // Nav buttons
    integer minLevel = minBidLevel();
    string prevBtn = "-";
    string nextBtn = "-";
    if (level > minLevel) prevBtn = "<< Prev";
    if (level < 7)        nextBtn = "Next >>";

    // button[0]=bottom-left → button[8]=top-right
    return [prevBtn, dblBtn, nextBtn, sBtn, nBtn, "Pass", cBtn, dBtn, hBtn];
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
// Card selection dialog — fixed 4x3 grid, 2 cards per suit per page.
// Layout (bottom-to-top, left-to-right):
//   Row 3 (top):    [ S[0] ] [ S[1] ] [ Next>> ]
//   Row 2:          [ H[0] ] [ H[1] ] [   -    ]
//   Row 1:          [ D[0] ] [ D[1] ] [   -    ]
//   Row 0 (bottom): [ C[0] ] [ C[1] ] [ <<Prev ]
// ---------------------------------------------------------------------------
showCardDialog(integer page) {
    list hand = gHand;
    if (gPlayingDummy) hand = gDummyHand;
    gCardPage = page;

    list sCards = sortedSuitCards(hand, 3);
    list hCards = sortedSuitCards(hand, 2);
    list dCards = sortedSuitCards(hand, 1);
    list cCards = sortedSuitCards(hand, 0);

    integer base = page * 2;

    string s0 = "-"; string s1 = "-";
    string h0 = "-"; string h1 = "-";
    string d0 = "-"; string d1 = "-";
    string c0 = "-"; string c1 = "-";
    if (base     < llGetListLength(sCards)) s0 = cardStr(llList2Integer(sCards, base));
    if (base + 1 < llGetListLength(sCards)) s1 = cardStr(llList2Integer(sCards, base + 1));
    if (base     < llGetListLength(hCards)) h0 = cardStr(llList2Integer(hCards, base));
    if (base + 1 < llGetListLength(hCards)) h1 = cardStr(llList2Integer(hCards, base + 1));
    if (base     < llGetListLength(dCards)) d0 = cardStr(llList2Integer(dCards, base));
    if (base + 1 < llGetListLength(dCards)) d1 = cardStr(llList2Integer(dCards, base + 1));
    if (base     < llGetListLength(cCards)) c0 = cardStr(llList2Integer(cCards, base));
    if (base + 1 < llGetListLength(cCards)) c1 = cardStr(llList2Integer(cCards, base + 1));

    string prevBtn = "-";
    string nextBtn = "-";
    if (page > 0) prevBtn = "<< Prev";
    integer nextBase = (page + 1) * 2;
    if (nextBase < llGetListLength(sCards) || nextBase < llGetListLength(hCards) ||
        nextBase < llGetListLength(dCards) || nextBase < llGetListLength(cCards))
        nextBtn = "Next >>";

    // button[0]=bottom-left → button[11]=top-right
    list buttons = [c0, c1, prevBtn, d0, d1, "-", h0, h1, "-", s0, s1, nextBtn];

    string title = "Play a card:";
    if (gPlayingDummy) title = "Play for Dummy:";
    title += "\n" + handSuitRows(hand);
    llDialog(llGetOwner(), title, buttons, gChannel);
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
        gBidMode           = FALSE;
        gSelectMode        = FALSE;
        gPendingPlayPrompt = FALSE;
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
            // Full reset only on a new deal (13-card hand); mid-play updates leave modes intact
            if (llGetListLength(gHand) == 13) {
                gDummyHand         = [];
                gPlayingDummy      = FALSE;
                gBidMode           = FALSE;
                gSelectMode        = FALSE;
                gPendingPlayPrompt = FALSE;
            }
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
            if (gPendingPlayPrompt) {
                gPendingPlayPrompt = FALSE;
                showCardDialog(0);
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
            gPendingPlayPrompt = FALSE;
            updateHandDisplay();
            if (gPlayingDummy && llGetListLength(gDummyHand) == 0) {
                gPendingPlayPrompt = TRUE;
            } else {
                showCardDialog(0);
            }
            return;
        }

        // Dialog button responses
        if (gBidMode) {
            if (message == "-") { showBidDialog(gBidPage); return; }
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
            if (message == "-") { showCardDialog(gCardPage); return; }
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
                gSelectMode   = FALSE;
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
