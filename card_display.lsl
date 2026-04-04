// card_display.lsl
// Manages all visual card output on the table surface:
//   - Dummy hand (13 cards face-up after opening lead)
//   - Current trick (up to 4 cards, one per seat position)
//   - Clears trick display between tricks
//   - Seat name tags (bot/human floating text above each seat prim)
//
// This script runs in the table root prim alongside the other engine scripts.
// It does NOT directly manipulate child prims (which would require llSetLinkPrimitiveParamsFast
// with link numbers). Instead it uses llSetText on itself for a text-based
// display of the current trick, and broadcasts dummy hand details via llSay
// on a public-ish channel so seat prims can render them if desired.
//
// For a full graphical implementation the builder would replace the llSetText
// calls here with llSetLinkPrimitiveParamsFast calls targeting specific card
// display prims in the link set.
//
// Messages received:
//   MSG_TRICK_PLAYED (402) — str="seat|card"      a card was played this trick
//   MSG_TRICK_DONE   (105) — str="winner|ns|ew"   trick complete, clear display
//   MSG_DUMMY_REVEAL (401) — str="seat|c0|c1|..."  show dummy hand
//   MSG_HAND_DONE    (106) — any str               clear all card displays
//   MSG_SEAT_OCCUPIED(403) — str="seat|name"       update seat name tag
//   MSG_SEAT_VACATED (404) — str="seat"            revert seat to bot name tag

// ---------------------------------------------------------------------------
// Message constants
// ---------------------------------------------------------------------------
integer MSG_TRICK_DONE    = 105;
integer MSG_HAND_DONE     = 106;
integer MSG_TRICK_PLAYED  = 402;
integer MSG_DUMMY_REVEAL  = 401;
integer MSG_SEAT_OCCUPIED = 403;
integer MSG_SEAT_VACATED  = 404;

// ---------------------------------------------------------------------------
// Card display helpers
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
// Seat display names
// ---------------------------------------------------------------------------
list gSeatNames = ["North", "South", "East", "West"];
list BOT_NAMES  = ["North Bot", "South Bot", "East Bot", "West Bot"];
list gIsHuman   = [0, 0, 0, 0];
list gHumanNames = ["", "", "", ""];

// Current trick: [seat, card, seat, card, ...]
list gTrick = [];

// Dummy hand (card list)
list gDummyHand = [];
integer gDummySeat = -1;

// ---------------------------------------------------------------------------
// Render the current state as floating text on the root prim
// Layout:
//
//   NORTH: [name tag]            DUMMY or played card
//   WEST:  [card]    [trick area]  EAST: [card]
//   SOUTH: [name tag]            played card
//
// We use a simple text block since we don't know link numbers at script time.
// ---------------------------------------------------------------------------
updateDisplay() {
    string north = llList2String(gIsHuman, 0)
        ? llList2String(gHumanNames, 0)
        : llList2String(BOT_NAMES, 0);
    string south = llList2String(gIsHuman, 1)
        ? llList2String(gHumanNames, 1)
        : llList2String(BOT_NAMES, 1);
    string east  = llList2String(gIsHuman, 2)
        ? llList2String(gHumanNames, 2)
        : llList2String(BOT_NAMES, 2);
    string west  = llList2String(gIsHuman, 3)
        ? llList2String(gHumanNames, 3)
        : llList2String(BOT_NAMES, 3);

    // Find each seat's played card in current trick
    list cardPlayed = ["--", "--", "--", "--"];
    integer i;
    for (i = 0; i < llGetListLength(gTrick); i += 2) {
        integer seat = llList2Integer(gTrick, i);
        integer card = llList2Integer(gTrick, i + 1);
        cardPlayed = llListReplaceList(cardPlayed, [cardStr(card)], seat, seat);
    }

    string display =
        "     " + north + "\n"
      + "     [" + llList2String(cardPlayed, 0) + "]\n"
      + west + " [" + llList2String(cardPlayed, 3) + "]"
      + "   [" + llList2String(cardPlayed, 2) + "] " + east + "\n"
      + "     [" + llList2String(cardPlayed, 1) + "]\n"
      + "     " + south + "\n";

    // Dummy hand
    if (llGetListLength(gDummyHand) > 0) {
        display += "\nDummy (" + llList2String(gSeatNames, gDummySeat) + "): ";
        string suitRow = "";
        integer s;
        for (s = 0; s < 4; s++) {
            string row = llList2String(suitSymbols, s) + ":";
            integer k;
            for (k = 0; k < llGetListLength(gDummyHand); k++) {
                integer c = llList2Integer(gDummyHand, k);
                if (cardSuit(c) == s) {
                    row += llList2String(rankNames, cardRank(c));
                }
            }
            if (row != llList2String(suitSymbols, s) + ":") {
                suitRow += row + " ";
            }
        }
        display += suitRow;
    }

    llSetText(display, <1,1,0.8>, 1.0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gTrick     = [];
        gDummyHand = [];
        gDummySeat = -1;
        updateDisplay();
    }

    link_message(integer sender, integer num, string str, key id) {

        if (num == MSG_TRICK_PLAYED) {
            // str = "seat|card"
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer card = (integer)llList2String(parts, 1);
            gTrick += [seat, card];
            updateDisplay();

        } else if (num == MSG_TRICK_DONE) {
            // Clear trick after brief pause (so players can see last card)
            gTrick = [];
            updateDisplay();

        } else if (num == MSG_DUMMY_REVEAL) {
            // str = "seat|c0|c1|..."
            list parts = llParseString2List(str, ["|"], []);
            gDummySeat = (integer)llList2String(parts, 0);
            gDummyHand = [];
            integer i;
            for (i = 1; i < llGetListLength(parts); i++) {
                gDummyHand += [(integer)llList2String(parts, i)];
            }
            updateDisplay();

        } else if (num == MSG_HAND_DONE) {
            // Clear everything between hands
            gTrick     = [];
            gDummyHand = [];
            gDummySeat = -1;
            updateDisplay();

        } else if (num == MSG_SEAT_OCCUPIED) {
            // str = "seat|avatar_name"
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            string  name = llList2String(parts, 1);
            gIsHuman    = llListReplaceList(gIsHuman,   [1],    seat, seat);
            gHumanNames = llListReplaceList(gHumanNames,[name], seat, seat);
            updateDisplay();

        } else if (num == MSG_SEAT_VACATED) {
            integer seat = (integer)str;
            gIsHuman    = llListReplaceList(gIsHuman,   [0],  seat, seat);
            gHumanNames = llListReplaceList(gHumanNames,[""], seat, seat);
            updateDisplay();
        }
    }
}
