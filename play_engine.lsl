// play_engine.lsl
// Manages card play: validates plays, tracks the current trick,
// determines trick winners, and manages dummy hand visibility.
//
// Messages received:
//   MSG_PLAY_START    (104) — str="declarer|level|suit|doubled|lead_seat"
//   MSG_PLAY_REQUEST  (201) — str="seat" (from game_controller)
//   MSG_PLAY_RESPONSE (301) — str="seat|card"
//   MSG_SUIT_CHECK_RESPONSE (216) — str="seat|suit|1or0" (from deck_manager)
//   MSG_HAND_DATA     (214) — str="seat|c0|c1|..." (from deck_manager, for dummy)
//
// Messages sent:
//   MSG_PLAY_REQUEST  (201) — re-sent to seat when play is invalid
//   MSG_TRICK_DONE    (105) — str="winner|tricks_ns|tricks_ew"
//   MSG_DUMMY_REVEAL  (401) — str="seat|c0|c1|..." reveal dummy hand to table
//   MSG_TRICK_PLAYED  (402) — str="seat|card" a card was played to table display
//   MSG_SUIT_CHECK    (215) — str="seat|suit" ask deck_manager if seat holds suit
//   MSG_HAND_REQUEST  (213) — str="seat" request dummy hand from deck_manager
//   MSG_REMOVE_CARD   (212) — str="seat|card" tell deck_manager card was played

// ---------------------------------------------------------------------------
// Message constants
// ---------------------------------------------------------------------------
integer MSG_PLAY_START      = 104;
integer MSG_TRICK_DONE      = 105;
integer MSG_PLAY_REQUEST    = 201;
integer MSG_PLAY_RESPONSE   = 301;
integer MSG_DUMMY_REVEAL    = 401;
integer MSG_TRICK_PLAYED    = 402;

integer MSG_REMOVE_CARD     = 212;
integer MSG_HAND_REQUEST    = 213;
integer MSG_HAND_DATA       = 214;
integer MSG_SUIT_CHECK      = 215;
integer MSG_SUIT_CHECK_RESPONSE = 216;

// ---------------------------------------------------------------------------
// Card helpers
// ---------------------------------------------------------------------------
integer cardSuit(integer card) { return card / 13; }
integer cardRank(integer card) { return card % 13; }

integer NORTH = 0;
integer SOUTH = 1;
integer EAST  = 2;
integer WEST  = 3;

integer partnership(integer seat) {
    if (seat == NORTH || seat == SOUTH) return 0;
    return 1;
}

string seatName(integer seat) {
    list names = ["North","South","East","West"];
    return llList2String(names, seat);
}

list rankNames = ["2","3","4","5","6","7","8","9","T","J","Q","K","A"];
list suitChars = ["C","D","H","S"];

string cardStr(integer card) {
    return llList2String(rankNames, cardRank(card))
         + llList2String(suitChars, cardSuit(card));
}

// ---------------------------------------------------------------------------
// Game state
// ---------------------------------------------------------------------------
integer gDeclarer      = -1;
integer gDummy         = -1;   // declarer's partner
integer gTrump         = -1;   // 0-3 = suit, 4 = NT (-1 uninitialised)
integer gContractLevel = 0;
integer gDoubled       = 0;

// Current trick: list of [seat, card, seat, card, ...] pairs (up to 8 entries)
list    gTrick         = [];
integer gLedSuit       = -1;   // suit of first card in current trick
integer gLeader        = -1;   // who leads this trick

// Trick counts
integer gTricksNS      = 0;
integer gTricksEW      = 0;
integer gTricksTotal   = 0;

// Opening lead played flag (dummy revealed after first card)
integer gOpeningLeadDone = FALSE;
integer gDummyRevealed   = FALSE;

// Pending play validation — waiting for suit check response
integer gPendingPlaySeat = -1;
integer gPendingPlayCard = -1;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

integer leftOf(integer seat) {
    list next = [2, 3, 1, 0]; // N→E→S→W→N
    return llList2Integer(next, seat);
}

// Whose turn in current trick? Count cards already played.
integer currentTrickSeat() {
    integer played = llGetListLength(gTrick) / 2;
    // Rotate from leader
    integer seat = gLeader;
    integer i;
    for (i = 0; i < played; i++) seat = leftOf(seat);
    return seat;
}

// When declarer is on lead for dummy's hand, declarer still physically clicks
// but the card comes from dummy's hand. We check: if the seat whose turn it is
// is gDummy, the request is forwarded to gDeclarer's seat/HUD.
// In practice game_controller sends MSG_PLAY_REQUEST to gDummy but seat.lsl
// for dummy does nothing — declarer's seat.lsl intercepts dummy requests.
// (Handled in seat.lsl via a DUMMY_MODE flag set by MSG_DUMMY_REVEAL.)

// ---------------------------------------------------------------------------
// Determine trick winner
// Returns winning seat
// ---------------------------------------------------------------------------
integer trickWinner() {
    integer winningSeat = llList2Integer(gTrick, 0);
    integer winningCard = llList2Integer(gTrick, 1);
    integer winningRank = cardRank(winningCard);
    integer winningIsTrump = (gTrump < 4 && cardSuit(winningCard) == gTrump);

    integer i;
    for (i = 2; i < llGetListLength(gTrick); i += 2) {
        integer seat = llList2Integer(gTrick, i);
        integer card = llList2Integer(gTrick, i + 1);
        integer suit = cardSuit(card);
        integer rank = cardRank(card);
        integer isTrump = (gTrump < 4 && suit == gTrump);

        if (isTrump && !winningIsTrump) {
            // Trump beats non-trump
            winningSeat    = seat;
            winningCard    = card;
            winningRank    = rank;
            winningIsTrump = TRUE;
        } else if (isTrump && winningIsTrump && rank > winningRank) {
            // Higher trump wins
            winningSeat = seat;
            winningCard = card;
            winningRank = rank;
        } else if (!isTrump && !winningIsTrump && suit == gLedSuit && rank > winningRank) {
            // Higher card of led suit wins (no trump involved)
            winningSeat = seat;
            winningCard = card;
            winningRank = rank;
        }
        // Off-suit non-trump never wins
    }
    return winningSeat;
}

// ---------------------------------------------------------------------------
// Finalise trick
// ---------------------------------------------------------------------------
finaliseTrick() {
    integer winner = trickWinner();
    integer p      = partnership(winner);

    if (p == 0) gTricksNS++;
    else        gTricksEW++;
    gTricksTotal++;

    llSay(0, seatName(winner) + " wins trick "
        + (string)gTricksTotal
        + " (NS " + (string)gTricksNS
        + " / EW " + (string)gTricksEW + ")");

    // Reset trick state
    gTrick   = [];
    gLedSuit = -1;
    gLeader  = winner;

    llMessageLinked(LINK_SET, MSG_TRICK_DONE,
        (string)winner + "|" + (string)gTricksNS + "|" + (string)gTricksEW,
        NULL_KEY);
}

// ---------------------------------------------------------------------------
// Accept a validated play
// ---------------------------------------------------------------------------
acceptPlay(integer seat, integer card) {
    // Remove card from hand
    llMessageLinked(LINK_SET, MSG_REMOVE_CARD,
        (string)seat + "|" + (string)card, NULL_KEY);

    // Record in trick
    if (llGetListLength(gTrick) == 0) {
        gLedSuit = cardSuit(card);
    }
    gTrick += [seat, card];

    llSay(0, seatName(seat) + " plays " + cardStr(card));
    llMessageLinked(LINK_SET, MSG_TRICK_PLAYED,
        (string)seat + "|" + (string)card, NULL_KEY);

    // Reveal dummy after opening lead
    if (!gOpeningLeadDone) {
        gOpeningLeadDone = TRUE;
        revealDummy();
    }

    // If trick is complete (4 cards), finalise; otherwise request next player
    if (llGetListLength(gTrick) == 8) {
        finaliseTrick();
    } else {
        integer nextSeat = currentTrickSeat();
        integer forDummy = 0;
        if (nextSeat == gDummy) { nextSeat = gDeclarer; forDummy = 1; }
        llMessageLinked(LINK_SET, MSG_PLAY_REQUEST,
            (string)nextSeat + "|" + (string)forDummy, NULL_KEY);
    }
}

// ---------------------------------------------------------------------------
// Reveal dummy hand
// ---------------------------------------------------------------------------
revealDummy() {
    gDummyRevealed = TRUE;
    // Request dummy's hand from deck_manager to broadcast to display
    llMessageLinked(LINK_SET, MSG_HAND_REQUEST, (string)gDummy, NULL_KEY);
}

// ---------------------------------------------------------------------------
// Validate a play attempt — may be async (needs suit check)
// ---------------------------------------------------------------------------
validatePlay(integer seat, integer card) {
    // Is it actually this seat's turn?
    integer expected = currentTrickSeat();
    // Declarer plays dummy's cards when dummy is on lead
    if (expected == gDummy) expected = gDeclarer;
    if (seat != expected) {
        llSay(0, seatName(seat) + ": not your turn.");
        return;
    }

    // For the actual card seat (dummy's cards played by declarer)
    integer cardSeat = seat;
    if (seat == gDeclarer && expected == gDeclarer && currentTrickSeat() == gDummy) {
        cardSeat = gDummy;
    }

    // If leading (first card in trick), any card is legal
    if (llGetListLength(gTrick) == 0) {
        acceptPlay(cardSeat, card);
        return;
    }

    // Must follow suit — ask deck_manager asynchronously
    gPendingPlaySeat = cardSeat;
    gPendingPlayCard = card;
    llMessageLinked(LINK_SET, MSG_SUIT_CHECK,
        (string)cardSeat + "|" + (string)gLedSuit, NULL_KEY);
    // Completion in MSG_SUIT_CHECK_RESPONSE handler below
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gDeclarer      = -1;
        gDummy         = -1;
        gTrump         = -1;
        gTrick         = [];
        gTricksNS      = 0;
        gTricksEW      = 0;
        gTricksTotal   = 0;
        gOpeningLeadDone = FALSE;
        gDummyRevealed   = FALSE;
        gPendingPlaySeat = -1;
        gPendingPlayCard = -1;
    }

    link_message(integer sender, integer num, string str, key id) {

        if (num == MSG_PLAY_START) {
            // str = "declarer|level|suit|doubled|lead_seat"
            list parts  = llParseString2List(str, ["|"], []);
            gDeclarer   = (integer)llList2String(parts, 0);
            gContractLevel = (integer)llList2String(parts, 1);
            gTrump      = (integer)llList2String(parts, 2);
            gDoubled    = (integer)llList2String(parts, 3);
            gLeader     = (integer)llList2String(parts, 4);
            // Dummy is declarer's partner
            gDummy = gDeclarer ^ 1;

            gTrick       = [];
            gLedSuit     = -1;
            gTricksNS    = 0;
            gTricksEW    = 0;
            gTricksTotal = 0;
            gOpeningLeadDone = FALSE;
            gDummyRevealed   = FALSE;

        } else if (num == MSG_PLAY_RESPONSE) {
            // str = "seat|card"
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer card = (integer)llList2String(parts, 1);
            validatePlay(seat, card);

        } else if (num == MSG_SUIT_CHECK_RESPONSE) {
            // str = "seat|suit|1or0"
            list parts  = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer suit = (integer)llList2String(parts, 1);
            integer has  = (integer)llList2String(parts, 2);

            if (seat != gPendingPlaySeat) return; // stale response

            integer card = gPendingPlayCard;
            gPendingPlaySeat = -1;
            gPendingPlayCard = -1;

            if (has && cardSuit(card) != gLedSuit) {
                // Must follow suit — reject
                llSay(0, seatName(seat) + ": must follow suit ("
                    + llList2String(["C","D","H","S"], gLedSuit) + ").");
                // If the rejected seat was the dummy, re-prompt the declarer
                integer reqSeat  = seat;
                integer forDummy = 0;
                if (seat == gDummy) { reqSeat = gDeclarer; forDummy = 1; }
                llMessageLinked(LINK_SET, MSG_PLAY_REQUEST,
                    (string)reqSeat + "|" + (string)forDummy, NULL_KEY);
            } else {
                acceptPlay(seat, card);
            }

        } else if (num == MSG_HAND_DATA) {
            // Dummy hand came back from deck_manager — broadcast for display
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            if (seat == gDummy) {
                llMessageLinked(LINK_SET, MSG_DUMMY_REVEAL, str, NULL_KEY);
            }
        }
    }
}
