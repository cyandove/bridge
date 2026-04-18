// card_display.lsl
// Graphical card display for the table surface.
//
// Looks for linked prims named trick_N / trick_S / trick_E / trick_W
// (one per seat, shows the card played in the current trick) and dummy_0
// through dummy_12 (dummy hand, positioned near the dummy seat on reveal).
//
// Card textures must be in the root prim inventory, named <rank><suit>:
//   ranks: 2 3 4 5 6 7 8 9 T J Q K A
//   suits: C D H S
//   back:  purple_back
//
// Dummy hand layout (position, spread, rotation) is loaded from a notecard
// named "card_layout" in the same prim.  See card_layout.example for format.
// Hardcoded defaults are used if the notecard is absent.
//
// Falls back to llSetText when the named prims are absent.
//
// Clicking a dummy prim while dummy play is pending submits that card
// as MSG_PLAY_RESPONSE on behalf of the declarer.
//
// Messages received:
//   MSG_CONTRACT_SET  (103) -- str="declarer|level|suit|doubled"
//   MSG_TRICK_DONE    (105) -- str="winner|ns|ew"
//   MSG_HAND_DONE     (106) -- clear all displays
//   MSG_PLAY_REQUEST  (201) -- str="seat|forDummy"
//   MSG_REMOVE_CARD   (212) -- str="seat|card"
//   MSG_DUMMY_REVEAL  (401) -- str="seat|c0|c1|..."
//   MSG_TRICK_PLAYED  (402) -- str="seat|card"
//   MSG_SEAT_OCCUPIED (403) -- str="seat|name"
//   MSG_SEAT_VACATED  (404) -- str="seat"

// ---------------------------------------------------------------------------
// Message constants
// ---------------------------------------------------------------------------
integer MSG_CONTRACT_SET  = 103;
integer MSG_TRICK_DONE    = 105;
integer MSG_HAND_DONE     = 106;
integer MSG_PLAY_REQUEST  = 201;
integer MSG_PLAY_RESPONSE = 301;
integer MSG_REMOVE_CARD   = 212;
integer MSG_DUMMY_REVEAL  = 401;
integer MSG_TRICK_PLAYED  = 402;
integer MSG_SEAT_OCCUPIED = 403;
integer MSG_SEAT_VACATED  = 404;

// ---------------------------------------------------------------------------
// Card helpers
// ---------------------------------------------------------------------------
list rankNames   = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"];
list suitSymbols = ["C","D","H","S"];

string cardTextureName(integer card) {
    return llList2String(rankNames, card % 13)
         + llList2String(suitSymbols, card / 13);
}

string cardStr(integer card) {
    return llList2String(rankNames, card % 13)
         + llList2String(suitSymbols, card / 13);
}

// Sort cards for display: S high->low, H high->low, D high->low, C high->low
list sortCardsForDisplay(list cards) {
    list result = [];
    integer s;
    for (s = 3; s >= 0; s--) {
        list sc = [];
        integer i;
        for (i = 0; i < llGetListLength(cards); i++) {
            integer c = llList2Integer(cards, i);
            if (c / 13 == s) sc += [c];
        }
        integer n = llGetListLength(sc);
        integer j;
        for (i = 1; i < n; i++) {
            integer val = llList2Integer(sc, i);
            j = i - 1;
            while (j >= 0 && llList2Integer(sc, j) % 13 < val % 13) {
                sc = llListReplaceList(sc, [llList2Integer(sc, j)], j + 1, j + 1);
                j--;
            }
            sc = llListReplaceList(sc, [val], j + 1, j + 1);
        }
        result += sc;
    }
    return result;
}

// ---------------------------------------------------------------------------
// Prim link numbers (populated by discoverLinks at startup)
// ---------------------------------------------------------------------------
list gTrickLinks = [-1, -1, -1, -1];                         // N=0 S=1 E=2 W=3
list gDummyLinks = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; // slots 0..12

discoverLinks() {
    list trickNames = ["trick_N","trick_S","trick_E","trick_W"];
    integer total   = llGetNumberOfPrims();
    integer i;
    for (i = 2; i <= total; i++) {
        string n  = llGetLinkName(i);
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

// ---------------------------------------------------------------------------
// Texture helpers
// ---------------------------------------------------------------------------
setCardPrim(integer linkNum, integer card) {
    string texName;
    if (card == -1) texName = "purple_back";
    else            texName = cardTextureName(card);
    key texKey = llGetInventoryKey(texName);
    if (texKey == NULL_KEY) return;
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_TEXTURE, ALL_SIDES, texKey, <1.0,1.0,0.0>, ZERO_VECTOR, 0.0,
        PRIM_COLOR,   ALL_SIDES, <1.0,1.0,1.0>, 1.0
    ]);
}

clearCardPrim(integer linkNum) {
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_COLOR, ALL_SIDES, ZERO_VECTOR, 0.0
    ]);
}

// ---------------------------------------------------------------------------
// Dummy prim selection highlight
// ---------------------------------------------------------------------------
vector DUMMY_SELECT_OFFSET = <0.0, 0.0, 0.05>;  // lift off table surface

selectDummyPrim(integer linkNum) {
    list p = llGetLinkPrimitiveParams(linkNum, [PRIM_POS_LOCAL]);
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_POS_LOCAL, llList2Vector(p, 0) + DUMMY_SELECT_OFFSET,
        PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 0.5>, 1.0
    ]);
}

deselectDummyPrim(integer linkNum) {
    list p = llGetLinkPrimitiveParams(linkNum, [PRIM_POS_LOCAL]);
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_POS_LOCAL, llList2Vector(p, 0) - DUMMY_SELECT_OFFSET,
        PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 1.0>, 1.0
    ]);
}

clearDummySelection() {
    if (gSelectedDummySlot == -1) return;
    integer ln = llList2Integer(gDummyLinks, gSelectedDummySlot);
    if (ln != -1) deselectDummyPrim(ln);
    gSelectedDummySlot = -1;
}

// ---------------------------------------------------------------------------
// Dummy prim layout -- loaded from "card_layout" notecard, with defaults.
// Local space, relative to root prim. N=0 S=1 E=2 W=3.
// ---------------------------------------------------------------------------
list gDummyBasePos = [
    <-0.72,  1.10, 0.02>,   // North seat
    <-0.72, -1.10, 0.02>,   // South seat
    < 1.10, -0.72, 0.02>,   // East seat
    <-1.10, -0.72, 0.02>    // West seat
];
list gDummySpread = [
    <0.12, 0.0,  0.0>,      // North: spread along +X
    <0.12, 0.0,  0.0>,      // South: spread along +X
    <0.0,  0.12, 0.0>,      // East:  spread along +Y
    <0.0,  0.12, 0.0>       // West:  spread along +Y
];
list gDummyCardRot = [
    <0.0,  0.0,  0.0,    1.0>,    // North: no rotation
    <0.0,  0.0,  1.0,    0.0>,    // South: 180 deg around Z
    <0.0,  0.0,  0.707,  0.707>,  // East:   90 deg around Z
    <0.0,  0.0, -0.707,  0.707>   // West:  -90 deg around Z
];

// ---------------------------------------------------------------------------
// Notecard loading
// ---------------------------------------------------------------------------
string  LAYOUT_NOTECARD = "card_layout";
key     gNotecardQuery  = NULL_KEY;
integer gNotecardLine   = 0;

loadNotecard() {
    if (llGetInventoryType(LAYOUT_NOTECARD) != INVENTORY_NOTECARD) return;
    gNotecardLine  = 0;
    gNotecardQuery = llGetNotecardLine(LAYOUT_NOTECARD, 0);
}

parseLayoutLine(string line) {
    if (line == "" || llGetSubString(line, 0, 0) == "#") return;
    integer eq = llSubStringIndex(line, "=");
    if (eq == -1) return;
    string k = llGetSubString(line, 0, eq - 1);
    string v = llGetSubString(line, eq + 1, -1);

    integer seat  = -1;
    string  field = "";
    if (llGetSubString(k, 0, 4) == "north") { seat = 0; field = llGetSubString(k, 6, -1); }
    else if (llGetSubString(k, 0, 4) == "south") { seat = 1; field = llGetSubString(k, 6, -1); }
    else if (llGetSubString(k, 0, 3) == "east")  { seat = 2; field = llGetSubString(k, 5, -1); }
    else if (llGetSubString(k, 0, 3) == "west")  { seat = 3; field = llGetSubString(k, 5, -1); }
    if (seat == -1) return;

    if (field == "base")
        gDummyBasePos = llListReplaceList(gDummyBasePos, [(vector)v],   seat, seat);
    else if (field == "spread")
        gDummySpread  = llListReplaceList(gDummySpread,  [(vector)v],   seat, seat);
    else if (field == "rot")
        gDummyCardRot = llListReplaceList(gDummyCardRot, [(rotation)v], seat, seat);
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
integer gDeclarerSeat        = -1;
integer gDummySeat           = -1;
integer gWaitingForDummyPlay = FALSE;
integer gSelectedDummySlot   = -1;   // highlighted dummy prim slot (-1 = none)

// gDummyCards: card integer at each dummy prim slot (-1 = empty/not yet placed)
list gDummyCards = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];

list gTrick     = [];
list gDummyHand = [];   // raw dummy hand (for text fallback)

// Seat names for text fallback
list gIsHuman    = [0, 0, 0, 0];
list gHumanNames = ["", "", "", ""];
list BOT_NAMES   = ["North Bot", "South Bot", "East Bot", "West Bot"];

// ---------------------------------------------------------------------------
// Text fallback display (used only when trick prims are absent)
// ---------------------------------------------------------------------------
updateDisplay() {
    if (llList2Integer(gTrickLinks, 0) != -1) return;  // prims present, skip

    string n_name;
    if (llList2Integer(gIsHuman, 0)) n_name = llList2String(gHumanNames, 0);
    else n_name = llList2String(BOT_NAMES, 0);
    string s_name;
    if (llList2Integer(gIsHuman, 1)) s_name = llList2String(gHumanNames, 1);
    else s_name = llList2String(BOT_NAMES, 1);
    string e_name;
    if (llList2Integer(gIsHuman, 2)) e_name = llList2String(gHumanNames, 2);
    else e_name = llList2String(BOT_NAMES, 2);
    string w_name;
    if (llList2Integer(gIsHuman, 3)) w_name = llList2String(gHumanNames, 3);
    else w_name = llList2String(BOT_NAMES, 3);

    list cardPlayed = ["--","--","--","--"];
    integer i;
    for (i = 0; i < llGetListLength(gTrick); i += 2) {
        integer seat = llList2Integer(gTrick, i);
        integer card = llList2Integer(gTrick, i + 1);
        cardPlayed = llListReplaceList(cardPlayed, [cardStr(card)], seat, seat);
    }

    string d =
        "     " + n_name + "\n"
      + "     [" + llList2String(cardPlayed, 0) + "]\n"
      + w_name + " [" + llList2String(cardPlayed, 3) + "]"
      + "   [" + llList2String(cardPlayed, 2) + "] " + e_name + "\n"
      + "     [" + llList2String(cardPlayed, 1) + "]\n"
      + "     " + s_name;

    if (llGetListLength(gDummyHand) > 0) {
        d += "\nDummy:";
        integer s;
        for (s = 3; s >= 0; s--) {
            string row = " " + llList2String(suitSymbols, s) + ":";
            integer hasAny = FALSE;
            integer k;
            for (k = 0; k < llGetListLength(gDummyHand); k++) {
                integer c = llList2Integer(gDummyHand, k);
                if (c / 13 == s) {
                    row += llList2String(rankNames, c % 13);
                    hasAny = TRUE;
                }
            }
            if (hasAny) d += row;
        }
    }

    llSetText(d, <1.0,1.0,0.8>, 1.0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gTrick               = [];
        gDummyHand           = [];
        gDummySeat           = -1;
        gDeclarerSeat        = -1;
        gWaitingForDummyPlay = FALSE;
        gSelectedDummySlot   = -1;
        gDummyCards          = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
        discoverLinks();
        integer i;
        for (i = 0; i < 13; i++) {
            integer ln = llList2Integer(gDummyLinks, i);
            if (ln != -1) clearCardPrim(ln);
        }
        loadNotecard();
        updateDisplay();
    }

    changed(integer change) {
        if (change & CHANGED_LINK)      llResetScript();   // new prims added — rediscover
        if (change & CHANGED_INVENTORY) loadNotecard();    // notecard updated — reload layout
    }

    dataserver(key query_id, string data) {
        if (query_id != gNotecardQuery) return;
        if (data == EOF) return;
        parseLayoutLine(data);
        gNotecardLine++;
        gNotecardQuery = llGetNotecardLine(LAYOUT_NOTECARD, gNotecardLine);
    }

    touch_start(integer total) {
        if (!gWaitingForDummyPlay) return;
        integer linkNum = llDetectedLinkNumber(0);
        integer slot    = llListFindList(gDummyLinks, [linkNum]);
        if (slot == -1) return;
        integer card = llList2Integer(gDummyCards, slot);
        if (card == -1) return;

        if (slot == gSelectedDummySlot) {
            // Second click on same card -- play it
            deselectDummyPrim(linkNum);
            gSelectedDummySlot   = -1;
            gWaitingForDummyPlay = FALSE;
            llMessageLinked(LINK_SET, MSG_PLAY_RESPONSE,
                (string)gDeclarerSeat + "|" + (string)card, NULL_KEY);
        } else {
            // Switch highlight to this card
            if (gSelectedDummySlot != -1) {
                integer prevLn = llList2Integer(gDummyLinks, gSelectedDummySlot);
                if (prevLn != -1) deselectDummyPrim(prevLn);
            }
            gSelectedDummySlot = slot;
            selectDummyPrim(linkNum);
        }
    }

    link_message(integer sender, integer num, string str, key id) {

        if (num == MSG_CONTRACT_SET) {
            list parts    = llParseString2List(str, ["|"], []);
            gDeclarerSeat = (integer)llList2String(parts, 0);
            gDummySeat    = gDeclarerSeat ^ 1;
            gWaitingForDummyPlay = FALSE;

        } else if (num == MSG_PLAY_REQUEST) {
            list parts       = llParseString2List(str, ["|"], []);
            integer forDummy = (integer)llList2String(parts, 1);
            if (forDummy) {
                gWaitingForDummyPlay = TRUE;
            } else {
                clearDummySelection();
                gWaitingForDummyPlay = FALSE;
            }

        } else if (num == MSG_TRICK_PLAYED) {
            list parts   = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer card = (integer)llList2String(parts, 1);
            gTrick += [seat, card];
            integer ln = llList2Integer(gTrickLinks, seat);
            if (ln != -1) setCardPrim(ln, card);
            else          updateDisplay();

        } else if (num == MSG_TRICK_DONE) {
            clearDummySelection();
            gTrick               = [];
            gWaitingForDummyPlay = FALSE;
            integer i;
            for (i = 0; i < 4; i++) {
                integer ln = llList2Integer(gTrickLinks, i);
                if (ln != -1) clearCardPrim(ln);
            }
            updateDisplay();

        } else if (num == MSG_DUMMY_REVEAL) {
            list parts = llParseString2List(str, ["|"], []);
            gDummySeat = (integer)llList2String(parts, 0);
            gDummyHand = [];
            integer i;
            for (i = 1; i < llGetListLength(parts); i++)
                gDummyHand += [(integer)llList2String(parts, i)];

            list sorted = sortCardsForDisplay(gDummyHand);

            if (llList2Integer(gDummyLinks, 0) != -1) {
                vector   base   = llList2Vector(gDummyBasePos, gDummySeat);
                vector   spread = llList2Vector(gDummySpread,  gDummySeat);
                rotation rot    = llList2Rot(gDummyCardRot,    gDummySeat);
                for (i = 0; i < 13; i++) {
                    integer ln = llList2Integer(gDummyLinks, i);
                    integer c  = -1;
                    if (i < llGetListLength(sorted))
                        c = llList2Integer(sorted, i);
                    gDummyCards = llListReplaceList(gDummyCards, [c], i, i);
                    if (ln != -1) {
                        vector pos = base + spread * (float)i;
                        llSetLinkPrimitiveParamsFast(ln, [
                            PRIM_POS_LOCAL, pos,
                            PRIM_ROT_LOCAL, rot
                        ]);
                        if (c == -1) clearCardPrim(ln);
                        else         setCardPrim(ln, c);
                    }
                }
            } else {
                for (i = 0; i < 13; i++) {
                    integer c = -1;
                    if (i < llGetListLength(sorted))
                        c = llList2Integer(sorted, i);
                    gDummyCards = llListReplaceList(gDummyCards, [c], i, i);
                }
                updateDisplay();
            }

        } else if (num == MSG_REMOVE_CARD) {
            list parts   = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer card = (integer)llList2String(parts, 1);
            if (seat == gDummySeat) {
                integer slot = llListFindList(gDummyCards, [card]);
                if (slot != -1) {
                    gDummyCards = llListReplaceList(gDummyCards, [-1], slot, slot);
                    integer hidx = llListFindList(gDummyHand, [card]);
                    if (hidx != -1)
                        gDummyHand = llDeleteSubList(gDummyHand, hidx, hidx);
                    integer ln = llList2Integer(gDummyLinks, slot);
                    if (ln != -1) clearCardPrim(ln);
                    else          updateDisplay();
                }
            }

        } else if (num == MSG_HAND_DONE) {
            clearDummySelection();
            gTrick               = [];
            gDummyHand           = [];
            gDummySeat           = -1;
            gDeclarerSeat        = -1;
            gWaitingForDummyPlay = FALSE;
            gDummyCards          = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
            integer i;
            for (i = 0; i < 4; i++) {
                integer ln = llList2Integer(gTrickLinks, i);
                if (ln != -1) clearCardPrim(ln);
            }
            for (i = 0; i < 13; i++) {
                integer ln = llList2Integer(gDummyLinks, i);
                if (ln != -1) clearCardPrim(ln);
            }
            updateDisplay();

        } else if (num == MSG_SEAT_OCCUPIED) {
            list parts   = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            string  name = llList2String(parts, 1);
            gIsHuman    = llListReplaceList(gIsHuman,    [1],    seat, seat);
            gHumanNames = llListReplaceList(gHumanNames, [name], seat, seat);
            updateDisplay();

        } else if (num == MSG_SEAT_VACATED) {
            integer seat = (integer)str;
            gIsHuman    = llListReplaceList(gIsHuman,    [0],  seat, seat);
            gHumanNames = llListReplaceList(gHumanNames, [""], seat, seat);
            updateDisplay();
        }
    }
}
