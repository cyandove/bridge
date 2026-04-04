// deck_manager.lsl
// Manages the deck: shuffle, deal, hand storage, card queries.
// Communicates via llMessageLinked with the rest of the table scripts.
//
// Message types received:
//   MSG_GAME_START  (100) — shuffle and deal
//   MSG_CARD_QUERY  (210) — str="seat|card", reply MSG_CARD_OWNED (211)
//   MSG_REMOVE_CARD (212) — str="seat|card", remove card from hand
//   MSG_HAND_REQUEST(213) — str="seat", reply MSG_HAND_DATA (214)
//
// Message types sent:
//   MSG_DEAL_DONE   (101) — hands dealt, includes all 4 hands in str
//   MSG_HAND_UPDATE (202) — str="seat|c0|c1|..." sent once per seat
//   MSG_CARD_OWNED  (211) — str="seat|card|1or0"
//   MSG_HAND_DATA   (214) — str="seat|c0|c1|..."

// ---------------------------------------------------------------------------
// Constants (must match game_controller.lsl)
// ---------------------------------------------------------------------------
integer MSG_GAME_START   = 100;
integer MSG_DEAL_DONE    = 101;
integer MSG_HAND_UPDATE  = 202;
integer MSG_CARD_QUERY   = 210;
integer MSG_CARD_OWNED   = 211;
integer MSG_REMOVE_CARD  = 212;
integer MSG_HAND_REQUEST = 213;
integer MSG_HAND_DATA    = 214;

integer NORTH = 0;
integer SOUTH = 1;
integer EAST  = 2;
integer WEST  = 3;

// ---------------------------------------------------------------------------
// Hand storage — four lists, one per seat
// ---------------------------------------------------------------------------
list gHandN = [];
list gHandS = [];
list gHandE = [];
list gHandW = [];

// ---------------------------------------------------------------------------
// Card helpers
// ---------------------------------------------------------------------------

// Return suit (0-3) from card integer
integer cardSuit(integer card) { return card / 13; }

// Return rank (0-12) from card integer; 0=2 … 12=Ace
integer cardRank(integer card) { return card % 13; }

// Human-readable suit character
string suitChar(integer suit) {
    if (suit == 0) return "C";
    if (suit == 1) return "D";
    if (suit == 2) return "H";
    return "S";
}

// Human-readable rank
string rankStr(integer rank) {
    list names = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"];
    return llList2String(names, rank);
}

// Card as short string e.g. "AS", "TC", "2H"
string cardStr(integer card) {
    return rankStr(cardRank(card)) + suitChar(cardSuit(card));
}

// ---------------------------------------------------------------------------
// Fisher-Yates shuffle
// ---------------------------------------------------------------------------
list shuffleDeck() {
    // Build ordered deck 0-51
    list deck = [];
    integer i;
    for (i = 0; i < 52; i++) deck += [i];

    // Shuffle in-place using llFrand
    for (i = 51; i > 0; i--) {
        integer j = (integer)llFrand(i + 1);
        // Swap deck[i] and deck[j]
        integer tmp = llList2Integer(deck, i);
        deck = llListReplaceList(deck, [llList2Integer(deck, j)], i, i);
        deck = llListReplaceList(deck, [tmp], j, j);
    }
    return deck;
}

// ---------------------------------------------------------------------------
// Deal shuffled deck into 4 hands of 13
// ---------------------------------------------------------------------------
dealHands() {
    list deck = shuffleDeck();

    gHandN = llList2List(deck,  0, 12);
    gHandE = llList2List(deck, 13, 25);
    gHandS = llList2List(deck, 26, 38);
    gHandW = llList2List(deck, 39, 51);

    // Sort each hand by suit then rank for readability
    gHandN = sortHand(gHandN);
    gHandS = sortHand(gHandS);
    gHandE = sortHand(gHandE);
    gHandW = sortHand(gHandW);
}

// ---------------------------------------------------------------------------
// Sort a hand list by card integer value (groups by suit 0-3, rank 0-12)
// Simple insertion sort — 13 elements, fast enough
// ---------------------------------------------------------------------------
list sortHand(list hand) {
    integer n = llGetListLength(hand);
    integer i;
    for (i = 1; i < n; i++) {
        integer key = llList2Integer(hand, i);
        integer j = i - 1;
        while (j >= 0 && llList2Integer(hand, j) > key) {
            hand = llListReplaceList(hand, [llList2Integer(hand, j)], j + 1, j + 1);
            j--;
        }
        hand = llListReplaceList(hand, [key], j + 1, j + 1);
    }
    return hand;
}

// ---------------------------------------------------------------------------
// Return the hand list for a given seat integer
// ---------------------------------------------------------------------------
list getHand(integer seat) {
    if (seat == NORTH) return gHandN;
    if (seat == SOUTH) return gHandS;
    if (seat == EAST)  return gHandE;
    return gHandW;
}

// Store a modified hand back
storeHand(integer seat, list hand) {
    if (seat == NORTH) gHandN = hand;
    else if (seat == SOUTH) gHandS = hand;
    else if (seat == EAST)  gHandE = hand;
    else gHandW = hand;
}

// ---------------------------------------------------------------------------
// Serialise hand to pipe-delimited string "seat|c0|c1|..."
// ---------------------------------------------------------------------------
string serialiseHand(integer seat) {
    list hand = getHand(seat);
    string s = (string)seat;
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        s += "|" + (string)llList2Integer(hand, i);
    }
    return s;
}

// ---------------------------------------------------------------------------
// Broadcast each hand via MSG_HAND_UPDATE
// ---------------------------------------------------------------------------
broadcastHands() {
    integer seat;
    for (seat = 0; seat < 4; seat++) {
        llMessageLinked(LINK_SET, MSG_HAND_UPDATE, serialiseHand(seat), NULL_KEY);
    }
    llMessageLinked(LINK_SET, MSG_DEAL_DONE, "", NULL_KEY);
}

// ---------------------------------------------------------------------------
// Remove a card from a seat's hand (called after card is played)
// ---------------------------------------------------------------------------
removeCard(integer seat, integer card) {
    list hand = getHand(seat);
    integer idx = llListFindList(hand, [card]);
    if (idx != -1) {
        hand = llDeleteSubList(hand, idx, idx);
        storeHand(seat, hand);
    }
}

// ---------------------------------------------------------------------------
// Check if seat holds a card: reply MSG_CARD_OWNED "seat|card|1or0"
// ---------------------------------------------------------------------------
checkCardOwned(integer seat, integer card) {
    list hand = getHand(seat);
    integer found = (llListFindList(hand, [card]) != -1);
    llMessageLinked(LINK_SET, MSG_CARD_OWNED,
        (string)seat + "|" + (string)card + "|" + (string)found,
        NULL_KEY);
}

// ---------------------------------------------------------------------------
// Check if seat holds any card of given suit
// Used by play_engine to enforce suit-following
// Sent as MSG_SUIT_CHECK_RESPONSE (215)
// ---------------------------------------------------------------------------
integer MSG_SUIT_CHECK        = 215;
integer MSG_SUIT_CHECK_RESPONSE = 216;

checkHasSuit(integer seat, integer suit) {
    list hand = getHand(seat);
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        if (cardSuit(llList2Integer(hand, i)) == suit) {
            llMessageLinked(LINK_SET, MSG_SUIT_CHECK_RESPONSE,
                (string)seat + "|" + (string)suit + "|1", NULL_KEY);
            return;
        }
    }
    llMessageLinked(LINK_SET, MSG_SUIT_CHECK_RESPONSE,
        (string)seat + "|" + (string)suit + "|0", NULL_KEY);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        llSetText("Deck Manager Ready", <0,1,0>, 1.0);
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == MSG_GAME_START) {
            dealHands();
            broadcastHands();

        } else if (num == MSG_CARD_QUERY) {
            // str = "seat|card"
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer card = (integer)llList2String(parts, 1);
            checkCardOwned(seat, card);

        } else if (num == MSG_REMOVE_CARD) {
            // str = "seat|card"
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer card = (integer)llList2String(parts, 1);
            removeCard(seat, card);

        } else if (num == MSG_HAND_REQUEST) {
            // str = "seat"
            integer seat = (integer)str;
            llMessageLinked(LINK_SET, MSG_HAND_DATA, serialiseHand(seat), NULL_KEY);

        } else if (num == MSG_SUIT_CHECK) {
            // str = "seat|suit"
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer suit = (integer)llList2String(parts, 1);
            checkHasSuit(seat, suit);
        }
    }
}
