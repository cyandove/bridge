// game_controller.lsl
// Master state machine for the Bridge table.
// Lives in the root prim of the table object.
//
// Owns game state, turn order, and dealer rotation.
// Routes MSG_BID_RESPONSE and MSG_PLAY_RESPONSE to the appropriate engines.
// All other scripts are subordinate — they act on messages from here.

// ---------------------------------------------------------------------------
// Message type constants (shared across all scripts)
// ---------------------------------------------------------------------------
// Game flow
integer MSG_GAME_START      = 100;
integer MSG_DEAL_DONE       = 101;
integer MSG_BIDDING_START   = 102;
integer MSG_CONTRACT_SET    = 103;
integer MSG_PLAY_START      = 104;
integer MSG_TRICK_DONE      = 105;
integer MSG_HAND_DONE       = 106;
integer MSG_RUBBER_DONE     = 107;

// Deck manager
integer MSG_REMOVE_CARD     = 212;
integer MSG_HAND_REQUEST    = 213;

// Seat/bot I/O
integer MSG_BID_REQUEST     = 200;
integer MSG_PLAY_REQUEST    = 201;
integer MSG_HAND_UPDATE     = 202;
integer MSG_BID_RESPONSE    = 300;
integer MSG_PLAY_RESPONSE   = 301;

// Seat presence
integer MSG_SEAT_OCCUPIED   = 403;
integer MSG_SEAT_VACATED    = 404;

// Scoring
integer MSG_SCORE_UPDATE    = 400;

// ---------------------------------------------------------------------------
// Game states
// ---------------------------------------------------------------------------
integer STATE_IDLE      = 0;
integer STATE_WAITING   = 1;
integer STATE_DEALING   = 2;
integer STATE_BIDDING   = 3;
integer STATE_PLAYING   = 4;
integer STATE_SCORING   = 5;

// ---------------------------------------------------------------------------
// Seat constants
// ---------------------------------------------------------------------------
integer NORTH = 0;
integer SOUTH = 1;
integer EAST  = 2;
integer WEST  = 3;

// ---------------------------------------------------------------------------
// Global state
// ---------------------------------------------------------------------------
integer gState       = 0;   // current game state (STATE_*)
integer gDealer      = 0;   // NORTH=0, rotates each hand
integer gCurrentSeat = 0;   // whose turn it is
integer gTrickCount  = 0;   // tricks played this hand
integer gTricksNS    = 0;
integer gTricksEW    = 0;
integer gPendingLead = -1;  // winner waiting for inter-trick delay
integer gHandCount   = 0;   // hands played this rubber

// Seat occupancy: 1=human present, 0=bot
list gOccupied = [0, 0, 0, 0];

// Contract from bidding_engine: "declarer|level|suit|doubled"
// doubled: 0=none 1=doubled 2=redoubled
integer gDeclarer = -1;
integer gDummy    = -1;
integer gContractLevel = 0;
integer gContractSuit  = 0;   // 0-3 = C D H S, 4 = NT
integer gDoubled       = 0;

// Vulnerability: 1 if side has won a game this rubber
// Index 0 = NS, 1 = EW
list gVulnerable = [0, 0];

// Games won this rubber per side: index 0=NS 1=EW
list gGamesWon = [0, 0];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Partnership of a seat: 0=NS 1=EW
integer partnership(integer seat) {
    if (seat == NORTH || seat == SOUTH) return 0;
    return 1;
}

// Seat to the left (clockwise: N→E→S→W→N)
integer leftOf(integer seat) {
    // Clockwise: N(0)→E(2)→S(1)→W(3)→N(0)
    list next = [2, 3, 1, 0];
    return llList2Integer(next, seat);
}

// Advance dealer one seat clockwise
rotateDealer() {
    gDealer = leftOf(gDealer);
}

// Who is declarer's LHO (makes opening lead)?
integer lhoOf(integer seat) {
    return leftOf(seat);
}

string seatName(integer seat) {
    if (seat == NORTH) return "North";
    if (seat == SOUTH) return "South";
    if (seat == EAST)  return "East";
    return "West";
}

// ---------------------------------------------------------------------------
// State transitions
// ---------------------------------------------------------------------------

startWaiting() {
    gState = STATE_WAITING;
    llSetText("Bridge Table\nTouch a seat to join", <1,1,1>, 1.0);
}

startDealing() {
    gState = STATE_DEALING;
    gTrickCount  = 0;
    gTricksNS    = 0;
    gTricksEW    = 0;
    gPendingLead = -1;
    llSetText("Dealing...", <1,1,0>, 1.0);
    llMessageLinked(LINK_SET, MSG_GAME_START, "", NULL_KEY);
    // deck_manager will respond with MSG_DEAL_DONE
}

startBidding() {
    gState = STATE_BIDDING;
    // Bidder to dealer's left opens the auction
    gCurrentSeat = leftOf(gDealer);
    llSetText("Bidding\n" + seatName(gCurrentSeat) + "'s turn", <0.5,0.8,1>, 1.0);
    llMessageLinked(LINK_SET, MSG_BIDDING_START,
        (string)gDealer + "|" + (string)gCurrentSeat, NULL_KEY);
    llMessageLinked(LINK_SET, MSG_BID_REQUEST,
        (string)gCurrentSeat + "|0|0|-1|-1", NULL_KEY);
}

// Called by bidding_engine via MSG_CONTRACT_SET
// str = "declarer|level|suit|doubled"
contractSet(string str) {
    list parts = llParseString2List(str, ["|"], []);
    gDeclarer      = (integer)llList2String(parts, 0);
    gDummy         = gDeclarer ^ 1;
    gContractLevel = (integer)llList2String(parts, 1);
    gContractSuit  = (integer)llList2String(parts, 2);
    gDoubled       = (integer)llList2String(parts, 3);

    gState = STATE_PLAYING;
    // Opening lead is by LHO of declarer
    gCurrentSeat = lhoOf(gDeclarer);

    llSetText("Playing\nLead: " + seatName(gCurrentSeat), <0,1,0.5>, 1.0);
    llMessageLinked(LINK_SET, MSG_PLAY_START,
        str + "|" + (string)gCurrentSeat, NULL_KEY);
    requestPlay(gCurrentSeat);
}

requestPlay(integer seat) {
    integer forDummy = 0;
    if (seat == gDummy) { seat = gDeclarer; forDummy = 1; }
    llMessageLinked(LINK_SET, MSG_PLAY_REQUEST,
        (string)seat + "|" + (string)forDummy, NULL_KEY);
}

// Called by play_engine via MSG_TRICK_DONE
// str = "winner|tricks_ns|tricks_ew"
trickDone(string str) {
    list parts = llParseString2List(str, ["|"], []);
    integer winner = (integer)llList2String(parts, 0);
    gTricksNS = (integer)llList2String(parts, 1);
    gTricksEW = (integer)llList2String(parts, 2);
    gTrickCount++;
    gCurrentSeat = winner;

    if (gTrickCount == 13) {
        // Hand complete
        gState = STATE_SCORING;
        llSetTimerEvent(0);
        llMessageLinked(LINK_SET, MSG_HAND_DONE, str, NULL_KEY);
    } else {
        llSetText("Playing\nLead: " + seatName(winner)
            + "\nTricks: " + (string)gTrickCount, <0,1,0.5>, 1.0);
        gPendingLead = winner;
        llSetTimerEvent(1.0);
    }
}

// Called by scoring_engine via MSG_SCORE_UPDATE
// str = "games_ns|games_ew|vul_ns|vul_ew|rubber_done"
scoreUpdate(string str) {
    list parts = llParseString2List(str, ["|"], []);
    gGamesWon    = [llList2Integer(parts,0), llList2Integer(parts,1)];
    gVulnerable  = [llList2Integer(parts,2), llList2Integer(parts,3)];
    integer rubberDone = (integer)llList2String(parts, 4);

    if (rubberDone) {
        llMessageLinked(LINK_SET, MSG_RUBBER_DONE, str, NULL_KEY);
        llSay(0, "Rubber complete! Starting new rubber.");
        gGamesWon   = [0, 0];
        gVulnerable = [0, 0];
        gHandCount  = 0;
        gDealer     = NORTH;
        gState      = STATE_WAITING;
        llSetTimerEvent(5.0); // brief pause then re-deal
    } else {
        gHandCount++;
        rotateDealer();
        startDealing();
    }
}

// ---------------------------------------------------------------------------
// Bid advance — called when bidding_engine signals next bidder
// str = "next_seat"  (MSG_BID_ADVANCE internal signal from bidding_engine)
// ---------------------------------------------------------------------------
integer MSG_BID_ADVANCE = 203;

advanceBid(string str) {
    gCurrentSeat = (integer)llList2String(llParseString2List(str, ["|"], []), 0);
    llSetText("Bidding\n" + seatName(gCurrentSeat) + "'s turn", <0.5,0.8,1>, 1.0);
    llMessageLinked(LINK_SET, MSG_BID_REQUEST, str, NULL_KEY);
}

// ---------------------------------------------------------------------------
// Status report (shown when table is touched during play)
// ---------------------------------------------------------------------------
showStatus() {
    list suitNames = ["C","D","H","S","N"];

    string phase;
    if (gState == STATE_DEALING) {
        phase = "Dealing";
    } else if (gState == STATE_BIDDING) {
        phase = "Bidding — " + seatName(gCurrentSeat) + "'s turn";
    } else if (gState == STATE_PLAYING) {
        string contract = (string)gContractLevel
            + llList2String(suitNames, gContractSuit);
        if (gDoubled == 1) contract += " Dbl";
        if (gDoubled == 2) contract += " Rdbl";
        phase = "Playing " + contract + " by " + seatName(gDeclarer)
            + "\nTurn: " + seatName(gCurrentSeat)
            + "  Tricks: NS " + (string)gTricksNS
            + " / EW " + (string)gTricksEW;
    } else if (gState == STATE_SCORING) {
        phase = "Scoring";
    } else {
        phase = "Waiting";
    }

    string vul;
    integer vNS = llList2Integer(gVulnerable, 0);
    integer vEW = llList2Integer(gVulnerable, 1);
    if      (vNS && vEW)  vul = "Both vul";
    else if (vNS)          vul = "NS vul";
    else if (vEW)          vul = "EW vul";
    else                   vul = "None vul";

    llSay(0, phase
        + "\nGames — NS: " + (string)llList2Integer(gGamesWon, 0)
        + "  EW: " + (string)llList2Integer(gGamesWon, 1)
        + "  " + vul);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gState      = STATE_IDLE;
        gDealer     = NORTH;
        gOccupied   = [0, 0, 0, 0];
        gGamesWon   = [0, 0];
        gVulnerable = [0, 0];
        startWaiting();
    }

    touch_start(integer total) {
        if (gState == STATE_WAITING && llListFindList(gOccupied, [1]) != -1) {
            startDealing();
        } else if (gState != STATE_WAITING && gState != STATE_IDLE) {
            showStatus();
        }
    }

    timer() {
        llSetTimerEvent(0);
        if (gState == STATE_PLAYING && gPendingLead != -1) {
            integer lead = gPendingLead;
            gPendingLead = -1;
            requestPlay(lead);
        } else if (gState == STATE_WAITING) {
            startDealing();
        }
    }

    link_message(integer sender, integer num, string str, key id) {
        // Deck ready
        if (num == MSG_DEAL_DONE) {
            startBidding();

        // Bidding engine signals next bidder
        } else if (num == MSG_BID_ADVANCE) {
            advanceBid(str);

        // Bidding engine signals contract finalised
        } else if (num == MSG_CONTRACT_SET) {
            contractSet(str);

        // Play engine signals trick complete
        } else if (num == MSG_TRICK_DONE) {
            trickDone(str);

        // Scoring engine signals score updated
        } else if (num == MSG_SCORE_UPDATE) {
            scoreUpdate(str);

        // Seat occupied by human
        } else if (num == MSG_SEAT_OCCUPIED) {
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            gOccupied = llListReplaceList(gOccupied, [1], seat, seat);
            if (gState == STATE_WAITING) {
                llSetText("Bridge Table\nTouch when all players are ready", <1,1,1>, 1.0);
                if ((integer)llListStatistics(LIST_STAT_SUM, gOccupied) == 1)
                    llSay(0, "Touch the table when all players are ready to start the game.");
            }

        // Seat vacated
        } else if (num == MSG_SEAT_VACATED) {
            integer seat = (integer)str;
            gOccupied = llListReplaceList(gOccupied, [0], seat, seat);
        }
    }
}
