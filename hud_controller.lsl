// hud_controller.lsl
// HUD object script for human players.
//
// When card prims are present in the HUD linkset (hcard_0..12 for the
// player's hand, dcard_0..12 for dummy's hand), card play is handled by
// clicking those prims directly — no llDialog is shown.  If the prims are
// absent the existing dialog-based fallback is used automatically.
//
// On attach, the HUD listens on a fixed handshake channel (-7769).
// When the player sits, the seat script sends "SEAT|N" on that channel via
// llRegionSayTo. The HUD records its seat ID, opens the private channel
// (-7770 - N), and closes the handshake listen.
//
// Commands received from table (via llRegionSayTo on private channel):
//   "HAND|seat|c0|c1|..."         new hand dealt
//   "DUMMY_HAND|seat|c0|c1|..."   dummy hand revealed / updated
//   "BID_PROMPT|seat|hb|dbl|hs|ds" show bidding dialog
//   "PLAY_PROMPT|forDummy"         enable card selection
//
// Commands sent to table:
//   "BID|bid_integer"
//   "PLAY|card_integer"

// ---------------------------------------------------------------------------
// Channels
// ---------------------------------------------------------------------------
integer HUD_HANDSHAKE_CHANNEL = -7769;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
integer gSeatID          = -1;
integer gChannel         = 0;
integer gHandshakeHandle = -1;
integer gListenHandle    = -1;

list    gHand          = [];
list    gDummyHand     = [];
integer gPlayingDummy  = FALSE;
integer gSelectMode    = FALSE;
integer gBidMode       = FALSE;
integer gBidPage       = 1;
integer gCardPage      = 0;
integer gPendingPlayPrompt = FALSE;
integer gReady         = FALSE;
integer gAuctionDealer = -1;
list    gAuctionLog    = [];

// Auction state
integer gHighBid     = 0;
integer gDoubled     = 0;
integer gHighSide    = -1;
integer gDoublerSide = -1;

integer BID_PASS     = 0;
integer BID_DOUBLE   = 1;
integer BID_REDOUBLE = 2;

// ---------------------------------------------------------------------------
// Card prim link numbers (populated by discoverLinks at startup)
// ---------------------------------------------------------------------------
list gHandLinks      = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; // hcard_0..12
list gDCardLinks     = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; // dcard_0..12
list gHandLinkCards  = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; // card at each hand slot
list gDCardLinkCards = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; // card at each dummy slot
integer gHasPrims     = FALSE;
integer gSelectedSlot = -1;   // highlighted card slot (-1 = none)
integer gStartLink    = -1;   // "start" ready-toggle prim

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

// Full sorted hand: S A..2, H A..2, D A..2, C A..2
list sortCardsForDisplay(list hand) {
    list result = [];
    integer s;
    for (s = 3; s >= 0; s--)
        result += sortedSuitCards(hand, s);
    return result;
}

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
// Prim link discovery
// ---------------------------------------------------------------------------
discoverLinks() {
    gHandLinks  = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
    gDCardLinks = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
    gHasPrims   = FALSE;
    gStartLink  = -1;
    integer total = llGetNumberOfPrims();
    integer i;
    for (i = 2; i <= total; i++) {
        string n = llGetLinkName(i);
        if (llGetSubString(n, 0, 5) == "hcard_") {
            integer slot = (integer)llGetSubString(n, 6, -1);
            if (slot >= 0 && slot < 13) {
                gHandLinks = llListReplaceList(gHandLinks, [i], slot, slot);
                gHasPrims  = TRUE;
            }
        } else if (llGetSubString(n, 0, 5) == "dcard_") {
            integer slot = (integer)llGetSubString(n, 6, -1);
            if (slot >= 0 && slot < 13)
                gDCardLinks = llListReplaceList(gDCardLinks, [i], slot, slot);
        } else if (n == "start") {
            gStartLink = i;
        }
    }
}

updateStartPrim() {
    if (gStartLink == -1) return;
    if (gReady)
        llSetLinkPrimitiveParamsFast(gStartLink, [
            PRIM_COLOR, ALL_SIDES, <0.2,1.0,0.2>, 1.0,
            PRIM_TEXT, "[ Ready ]", <0.3,1.0,0.3>, 1.0
        ]);
    else
        llSetLinkPrimitiveParamsFast(gStartLink, [
            PRIM_COLOR, ALL_SIDES, <0.2,0.6,0.2>, 1.0,
            PRIM_TEXT, "Ready", <1.0,1.0,1.0>, 1.0
        ]);
}

// ---------------------------------------------------------------------------
// Card prim texture helpers
// ---------------------------------------------------------------------------
setCardPrim(integer linkNum, integer card) {
    string texName;
    if (card == -1) texName = "purple_back";
    else texName = llList2String(rankNames, card % 13)
                 + llList2String(suitSymbols, card / 13);
    key texKey = llGetInventoryKey(texName);
    if (texKey == NULL_KEY) return;
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_TEXTURE, ALL_SIDES, texKey, <-1.0,-1.0,0.0>, ZERO_VECTOR, 0.0,
        PRIM_COLOR,   ALL_SIDES, <1.0,1.0,1.0>, 1.0
    ]);
}

setDummyCardPrim(integer linkNum, integer card) {
    string texName;
    if (card == -1) texName = "purple_back";
    else texName = llList2String(rankNames, card % 13)
                 + llList2String(suitSymbols, card / 13);
    key texKey = llGetInventoryKey(texName);
    if (texKey == NULL_KEY) return;
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_TEXTURE, ALL_SIDES, texKey, <-1.0,1.0,0.0>, ZERO_VECTOR, 0.0,
        PRIM_COLOR,   ALL_SIDES, <1.0,1.0,1.0>, 1.0
    ]);
}

clearCardPrim(integer linkNum) {
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_COLOR, ALL_SIDES, ZERO_VECTOR, 0.0
    ]);
}

// ---------------------------------------------------------------------------
// Prim hand display
// ---------------------------------------------------------------------------
updateHandPrims() {
    list sorted = sortCardsForDisplay(gHand);
    integer i;
    for (i = 0; i < 13; i++) {
        integer c  = -1;
        if (i < llGetListLength(sorted)) c = llList2Integer(sorted, i);
        gHandLinkCards = llListReplaceList(gHandLinkCards, [c], i, i);
        integer ln = llList2Integer(gHandLinks, i);
        if (ln != -1) {
            if (c == -1) clearCardPrim(ln);
            else         setCardPrim(ln, c);
        }
    }
}

updateDummyPrims() {
    list sorted = sortCardsForDisplay(gDummyHand);
    integer i;
    for (i = 0; i < 13; i++) {
        integer c  = -1;
        if (i < llGetListLength(sorted)) c = llList2Integer(sorted, i);
        gDCardLinkCards = llListReplaceList(gDCardLinkCards, [c], i, i);
        integer ln = llList2Integer(gDCardLinks, i);
        if (ln != -1) {
            if (c == -1) clearCardPrim(ln);
            else         setDummyCardPrim(ln, c);
        }
    }
}

clearAllCardPrims() {
    integer i;
    for (i = 0; i < 13; i++) {
        integer ln = llList2Integer(gHandLinks, i);
        if (ln != -1) clearCardPrim(ln);
        ln = llList2Integer(gDCardLinks, i);
        if (ln != -1) clearCardPrim(ln);
    }
    gHandLinkCards  = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
    gDCardLinkCards = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
}

// ---------------------------------------------------------------------------
// Hover text display
// ---------------------------------------------------------------------------
updateHandDisplay() {
    list dirs = ["North","South","East","West"];
    string dir = llList2String(dirs, gSeatID);

    if (llGetListLength(gHand) == 0) {
        llSetText("Bridge HUD\n" + dir, <0.5,1,0.5>, 1.0);
        return;
    }

    string display = "Bridge HUD\n" + dir + "\n";
    if (gSelectMode && gPlayingDummy) display += "[PLAY FOR DUMMY]\n";
    display += "\n" + handSuitRows(gHand);

    if (gBidMode)                      display += "[BIDDING - touch to bid]";
    if (gSelectMode && !gPlayingDummy) display += "[SELECT CARD]";

    llSetText(display, <1,1,1>, 1.0);
}

// ---------------------------------------------------------------------------
// Bidding dialog
// ---------------------------------------------------------------------------
integer minBidLevel() {
    integer m = (gHighBid + 1) / 5;
    if (m < 1) m = 1;
    if (m > 7) m = 7;
    return m;
}

// Fixed 9-button grid (bottom-to-top, left-to-right):
//   Row 2 (top):    [ levelC ] [ levelD ] [ levelH ]
//   Row 1 (mid):    [ levelS ] [ levelN ] [  Pass  ]
//   Row 0 (bottom): [ <<Prev ] [  Dbl   ] [ Next>> ]
list buildBidPage(integer level) {
    integer myPartnership = gSeatID / 2;

    string cBtn = "-"; string dBtn = "-"; string hBtn = "-";
    string sBtn = "-"; string nBtn = "-";
    if (level * 5 + 0 > gHighBid) cBtn = (string)level + "C";
    if (level * 5 + 1 > gHighBid) dBtn = (string)level + "D";
    if (level * 5 + 2 > gHighBid) hBtn = (string)level + "H";
    if (level * 5 + 3 > gHighBid) sBtn = (string)level + "S";
    if (level * 5 + 4 > gHighBid) nBtn = (string)level + "N";

    string dblBtn = "-";
    if (gHighBid > 0 && gDoubled == 0 && gHighSide != -1 && gHighSide != myPartnership)
        dblBtn = "Dbl";
    if (gDoubled == 1 && gDoublerSide != -1 && gDoublerSide != myPartnership)
        dblBtn = "Rdbl";

    integer minLevel = minBidLevel();
    string prevBtn = "-";
    string nextBtn = "-";
    if (level > minLevel) prevBtn = "<< Prev";
    if (level < 7)        nextBtn = "Next >>";

    return [prevBtn, dblBtn, nextBtn, sBtn, nBtn, "Pass", cBtn, dBtn, hBtn];
}

string auctionHistoryStr() {
    if (gAuctionDealer == -1) return "";
    list leftOfMap = [2, 3, 1, 0]; // indexed by seat: N→E, S→W, E→S, W→N
    integer first = llList2Integer(leftOfMap, gAuctionDealer);
    // Column order: first bidder → clockwise
    list colSeats = [];
    integer s = first;
    integer i;
    for (i = 0; i < 4; i++) {
        colSeats += [s];
        s = llList2Integer(leftOfMap, s);
    }
    list initials = ["N","S","E","W"]; // indexed by seat ID (0=N,1=S,2=E,3=W)
    string out = "";
    for (i = 0; i < 4; i++) {
        string h = llList2String(initials, llList2Integer(colSeats, i));
        if (i < 3) out += llGetSubString(h + "    ", 0, 3) + " ";
        else        out += h;
    }
    out += "\n";
    integer n = llGetListLength(gAuctionLog);
    integer row = 0;
    while (row * 4 < n) {
        for (i = 0; i < 4; i++) {
            integer bidIdx = row * 4 + i;
            string cell = "";
            if (bidIdx < n) {
                integer bid = llList2Integer(gAuctionLog, bidIdx);
                if      (bid == 0) cell = "-";
                else if (bid == 1) cell = "Dbl";
                else if (bid == 2) cell = "Rdb";
                else {
                    list suits = ["C","D","H","S","N"];
                    cell = (string)(bid / 5) + llList2String(suits, bid % 5);
                }
            }
            if (i < 3) out += llGetSubString(cell + "    ", 0, 3) + " ";
            else if (cell != "") out += cell;
        }
        out += "\n";
        row++;
    }
    return out;
}

showBidDialog(integer level) {
    integer minLevel = minBidLevel();
    if (level < minLevel) level = minLevel;
    if (level > 7)        level = 7;
    gBidPage = level;
    list buttons = buildBidPage(level);
    string msg = auctionHistoryStr() + "Your bid (Level " + (string)level + "):";
    llDialog(llGetOwner(), msg, buttons, gChannel);
}

// ---------------------------------------------------------------------------
// Card selection dialog (fallback when no prims)
// Fixed 4x3 grid (bottom-to-top, left-to-right):
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

    list buttons = [c0, c1, prevBtn, d0, d1, "-", h0, h1, "-", s0, s1, nextBtn];

    string title = "Play a card:";
    if (gPlayingDummy) title = "Play for Dummy:";
    title += "\n" + handSuitRows(hand);
    llDialog(llGetOwner(), title, buttons, gChannel);
}

// ---------------------------------------------------------------------------
// Parse bid/card button labels
// ---------------------------------------------------------------------------
integer parseBidButton(string label) {
    if (label == "Pass")   return BID_PASS;
    if (label == "Dbl")    return BID_DOUBLE;
    if (label == "Rdbl")   return BID_REDOUBLE;
    list suitMap = ["C","D","H","S","N"];
    integer level = (integer)llGetSubString(label, 0, 0);
    string suitChar = llGetSubString(label, 1, 1);
    integer suit = llListFindList(suitMap, [suitChar]);
    if (level >= 1 && level <= 7 && suit >= 0)
        return level * 5 + suit;
    return -1;
}

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
// Card prim selection highlight
// ---------------------------------------------------------------------------
vector HUD_SELECT_OFFSET = <0.0, 0.0, 0.01>;  // move up on screen (Z = vertical axis)

selectCardPrim(integer linkNum) {
    list p = llGetLinkPrimitiveParams(linkNum, [PRIM_POS_LOCAL]);
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_POS_LOCAL, llList2Vector(p, 0) + HUD_SELECT_OFFSET,
        PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 0.5>, 1.0
    ]);
}

deselectCardPrim(integer linkNum) {
    list p = llGetLinkPrimitiveParams(linkNum, [PRIM_POS_LOCAL]);
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_POS_LOCAL, llList2Vector(p, 0) - HUD_SELECT_OFFSET,
        PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 1.0>, 1.0
    ]);
}

// Must be called BEFORE changing gPlayingDummy so the right link array is used
clearSelection() {
    if (gSelectedSlot == -1) return;
    list linkArr;
    if (!gPlayingDummy) linkArr = gHandLinks;
    else                linkArr = gDCardLinks;
    integer ln = llList2Integer(linkArr, gSelectedSlot);
    if (ln != -1) deselectCardPrim(ln);
    gSelectedSlot = -1;
}

// ---------------------------------------------------------------------------
// HUD face control (infrastructure for future dummy-hand panel flip)
// ---------------------------------------------------------------------------
setHudFace(integer showDummy) {
    // HUD flip disabled for now — dummy cards shown in same panel as own hand
    llSetLocalRot(ZERO_ROTATION);
}

// ---------------------------------------------------------------------------
// Handshake / seat assignment
// ---------------------------------------------------------------------------
openHandshake() {
    if (gHandshakeHandle != -1) llListenRemove(gHandshakeHandle);
    gHandshakeHandle = llListen(HUD_HANDSHAKE_CHANNEL, "", NULL_KEY, "");
}

assignSeat(integer seatID) {
    gSeatID      = seatID;
    gChannel     = -7770 - seatID;
    gHighBid     = 0;
    gDoubled     = 0;
    gHighSide    = -1;
    gDoublerSide = -1;
    gDummyHand    = [];
    gPlayingDummy = FALSE;
    gReady        = FALSE;
    clearSelection();
    gSelectedSlot = -1;

    if (gHandshakeHandle != -1) {
        llListenRemove(gHandshakeHandle);
        gHandshakeHandle = -1;
    }
    if (gListenHandle != -1) llListenRemove(gListenHandle);
    gListenHandle = llListen(gChannel, "", NULL_KEY, "");

    list seatNames = ["North","South","East","West"];
    llSetText("Bridge HUD\n" + llList2String(seatNames, seatID), <0.5,1,0.5>, 1.0);
    updateStartPrim();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gSeatID            = -1;
        gChannel           = 0;
        gHand              = [];
        gBidMode           = FALSE;
        gSelectMode        = FALSE;
        gPendingPlayPrompt = FALSE;
        gReady             = FALSE;
        gAuctionDealer     = -1;
        gAuctionLog        = [];
        gSelectedSlot      = -1;
        gHandLinkCards     = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
        gDCardLinkCards    = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
        discoverLinks();
        llSetText("Bridge HUD\nAttach & sit", <0.5,0.5,0.5>, 1.0);
        updateStartPrim();
        openHandshake();
    }

    attach(key avatarID) {
        if (avatarID != NULL_KEY) {
            gSeatID            = -1;
            gHand              = [];
            gBidMode           = FALSE;
            gSelectMode        = FALSE;
            gPendingPlayPrompt = FALSE;
            gReady             = FALSE;
            gAuctionDealer     = -1;
            gAuctionLog        = [];
            clearSelection();
            gSelectedSlot      = -1;
            if (gHasPrims) clearAllCardPrims();
            llSetText("Bridge HUD\nSit to connect", <0.5,0.5,0.5>, 1.0);
            updateStartPrim();
            openHandshake();
            llRegionSay(HUD_HANDSHAKE_CHANNEL,
                "HUD_READY|" + (string)llGetOwner());
        } else {
            setHudFace(FALSE);
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
        if (channel == HUD_HANDSHAKE_CHANNEL) {
            list parts = llParseString2List(message, ["|"], []);
            if (llList2String(parts, 0) == "SEAT") {
                assignSeat((integer)llList2String(parts, 1));
            }
            return;
        }

        if (channel != gChannel) return;

        if (llGetSubString(message, 0, 3) == "HAND") {
            // "HAND|seat|c0|c1|..."
            list parts = llParseString2List(message, ["|"], []);
            gHand = [];
            integer i;
            for (i = 2; i < llGetListLength(parts); i++)
                gHand += [(integer)llList2String(parts, i)];

            if (llGetListLength(gHand) == 13) {
                // New deal — full reset
                clearSelection();
                setHudFace(FALSE);
                gDummyHand         = [];
                gPlayingDummy      = FALSE;
                gBidMode           = FALSE;
                gSelectMode        = FALSE;
                gPendingPlayPrompt = FALSE;
                gReady             = FALSE;
                gAuctionDealer     = -1;
                gAuctionLog        = [];
                gSelectedSlot      = -1;
                if (gStartLink != -1)
                    llSetLinkPrimitiveParamsFast(gStartLink, [PRIM_TEXT, "", ZERO_VECTOR, 0.0]);

                if (gHasPrims) clearAllCardPrims();
            }
            if (gHasPrims) updateHandPrims();
            updateHandDisplay();
            return;
        }

        if (llGetSubString(message, 0, 9) == "DUMMY_HAND") {
            // "DUMMY_HAND|seat|c0|c1|..."
            integer prevLen = llGetListLength(gDummyHand);
            list parts = llParseString2List(message, ["|"], []);
            gDummyHand = [];
            integer i;
            for (i = 2; i < llGetListLength(parts); i++)
                gDummyHand += [(integer)llList2String(parts, i)];

            if (gHasPrims) updateDummyPrims();

            // A dummy card was removed while we were in dummy select mode — exit it
            if (gSelectMode && gPlayingDummy && llGetListLength(gDummyHand) < prevLen) {
                clearSelection();
                setHudFace(FALSE);
                gSelectMode   = FALSE;
                gPlayingDummy = FALSE;
                gSelectedSlot = -1;
                updateHandDisplay();
            }

            if (gPendingPlayPrompt) {
                gPendingPlayPrompt = FALSE;
                setHudFace(TRUE);
                if (!gHasPrims) showCardDialog(0);
            }
            return;
        }

        if (llGetSubString(message, 0, 9) == "BID_PROMPT") {
            // "BID_PROMPT|seat|high_bid|doubled|high_side|doubler_side|dealer|bid0|..."
            list parts   = llParseString2List(message, ["|"], []);
            gHighBid     = (integer)llList2String(parts, 2);
            gDoubled     = (integer)llList2String(parts, 3);
            gHighSide    = (integer)llList2String(parts, 4);
            gDoublerSide = (integer)llList2String(parts, 5);
            if (llGetListLength(parts) > 6) {
                gAuctionDealer = (integer)llList2String(parts, 6);
                gAuctionLog = [];
                integer ai;
                for (ai = 7; ai < llGetListLength(parts); ai++)
                    gAuctionLog += [(integer)llList2String(parts, ai)];
            }
            gBidMode     = TRUE;
            gSelectMode  = FALSE;
            updateHandDisplay();
            showBidDialog(minBidLevel());
            return;
        }

        if (llGetSubString(message, 0, 10) == "PLAY_PROMPT") {
            // "PLAY_PROMPT|forDummy"
            clearSelection();  // before gPlayingDummy changes
            list parts    = llParseString2List(message, ["|"], []);
            gPlayingDummy = (integer)llList2String(parts, 1);
            gSelectMode   = TRUE;
            gBidMode      = FALSE;
            gPendingPlayPrompt = FALSE;
            if (gPlayingDummy && llGetListLength(gDummyHand) == 0) {
                gPendingPlayPrompt = TRUE;
                // Wait for DUMMY_HAND before flipping or showing dialog
            } else {
                setHudFace(gPlayingDummy);
                if (!gHasPrims) showCardDialog(0);
            }
            updateHandDisplay();
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
                setHudFace(FALSE);
                updateHandDisplay();
                llSay(gChannel, "PLAY|" + (string)card);
            }
        }
    }

    touch_start(integer total) {
        integer linkNum = llDetectedLinkNumber(0);

        if (gSelectMode) {
            list linkArr;
            list cardArr;
            if (!gPlayingDummy) { linkArr = gHandLinks;  cardArr = gHandLinkCards;  }
            else                { linkArr = gDCardLinks; cardArr = gDCardLinkCards; }

            integer slot = llListFindList(linkArr, [linkNum]);
            integer card = -1;
            if (slot != -1) card = llList2Integer(cardArr, slot);

            if (card == -1) {
                if (!gHasPrims) showCardDialog(gCardPage);
                return;
            }

            if (slot == gSelectedSlot) {
                // Second click on same card -- play it
                deselectCardPrim(linkNum);
                gSelectedSlot = -1;
                gSelectMode   = FALSE;
                gPlayingDummy = FALSE;
                setHudFace(FALSE);
                updateHandDisplay();
                llSay(gChannel, "PLAY|" + (string)card);
            } else {
                // Switch highlight to this card
                if (gSelectedSlot != -1) {
                    integer prevLn = llList2Integer(linkArr, gSelectedSlot);
                    if (prevLn != -1) deselectCardPrim(prevLn);
                }
                gSelectedSlot = slot;
                selectCardPrim(linkNum);
            }
            return;
        }

        if (gBidMode) showBidDialog(gBidPage);

        // "start" prim touch → toggle ready state
        if (linkNum == gStartLink && gStartLink != -1 && gSeatID != -1) {
            gReady = !gReady;
            llSay(gChannel, "READY|" + (string)gReady);
            updateStartPrim();
        }
    }
}
