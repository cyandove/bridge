// scoring_engine.lsl
// Rubber Bridge scoring.
//
// Messages received:
//   MSG_HAND_DONE   (106) — str="winner_seat|tricks_ns|tricks_ew"
//                           winner_seat = trick winner of last trick (not used here)
//   MSG_CONTRACT_SET(103) — str="declarer|level|suit|doubled"
//                           cache the contract for when hand ends
//
// Messages sent:
//   MSG_SCORE_UPDATE(400) — str="games_ns|games_ew|vul_ns|vul_ew|rubber_done"
//                           rubber_done = 1 when a side has won 2 games

// ---------------------------------------------------------------------------
// Message constants
// ---------------------------------------------------------------------------
integer MSG_CONTRACT_SET = 103;
integer MSG_HAND_DONE    = 106;
integer MSG_GAME_RESET   = 108;
integer MSG_SCORE_UPDATE = 400;

// ---------------------------------------------------------------------------
// Seat / partnership helpers
// ---------------------------------------------------------------------------
integer NORTH = 0;
integer SOUTH = 1;
integer EAST  = 2;
integer WEST  = 3;

integer partnership(integer seat) {
    if (seat == NORTH || seat == SOUTH) return 0;
    return 1;
}

// ---------------------------------------------------------------------------
// Rubber score state
// ---------------------------------------------------------------------------
// Points scored below the line per side (count toward game)
integer gBelowNS = 0;
integer gBelowEW = 0;

// Points scored above the line per side (bonuses, overtricks, penalties)
integer gAboveNS = 0;
integer gAboveEW = 0;

// Games won this rubber: 0=NS, 1=EW
list gGamesWon = [0, 0];

// Vulnerability: 1 if that side has won one game
list gVulnerable = [0, 0];

// Cached contract
integer gDeclarer      = -1;
integer gContractLevel = 0;
integer gContractSuit  = 0;   // 0-3=suit 4=NT
integer gDoubled       = 0;

// ---------------------------------------------------------------------------
// Trick point value per suit (undoubled, per contracted trick)
// ---------------------------------------------------------------------------
integer trickPoints(integer suit, integer trick_index) {
    // trick_index: 0-based index of tricks beyond 6 (0 = first contracted trick)
    if (suit == 0 || suit == 1) return 20;    // Clubs, Diamonds
    if (suit == 2 || suit == 3) return 30;    // Hearts, Spades
    // No Trump
    if (trick_index == 0) return 40;
    return 30;
}

// ---------------------------------------------------------------------------
// Score a completed hand
// ---------------------------------------------------------------------------
scoreHand(integer tricksNS, integer tricksEW) {
    if (gDeclarer == -1) return; // passed-out hand, no score

    integer declarerPartnership = partnership(gDeclarer);
    integer vul = llList2Integer(gVulnerable, declarerPartnership);

    // Tricks made and needed
    integer tricksMade;
    if (declarerPartnership == 0) tricksMade = tricksNS;
    else tricksMade = tricksEW;
    integer tricksNeeded = gContractLevel + 6;
    integer overtricks   = tricksMade - tricksNeeded;

    integer belowLine = 0;
    integer aboveDeclarer = 0;
    integer aboveDefenders = 0;

    if (overtricks >= 0) {
        // ---- Made the contract ----

        // Below-the-line trick score
        integer i;
        for (i = 0; i < gContractLevel; i++) {
            integer pts = trickPoints(gContractSuit, i);
            if (gDoubled == 1) pts *= 2;
            else if (gDoubled == 2) pts *= 4;
            belowLine += pts;
        }

        // Overtrick bonuses (above the line)
        if (overtricks > 0) {
            integer otPts;
            if (gDoubled == 0) {
                otPts = trickPoints(gContractSuit, gContractLevel) * overtricks;
            } else if (gDoubled == 1) {
                if (vul) otPts = 200 * overtricks;
                else otPts = 100 * overtricks;
            } else {
                if (vul) otPts = 400 * overtricks;
                else otPts = 200 * overtricks;
            }
            aboveDeclarer += otPts;
        }

        // Insult bonus for making a doubled/redoubled contract
        if (gDoubled == 1)  aboveDeclarer += 50;
        if (gDoubled == 2)  aboveDeclarer += 100;

        // Slam bonuses
        if (gContractLevel == 6) {
            // Small slam
            if (vul) aboveDeclarer += 750;
            else aboveDeclarer += 500;
        } else if (gContractLevel == 7) {
            // Grand slam
            if (vul) aboveDeclarer += 1500;
            else aboveDeclarer += 1000;
        }

        // Apply below-the-line
        if (declarerPartnership == 0) gBelowNS += belowLine;
        else                          gBelowEW += belowLine;

        // Check for game
        integer gameWon = FALSE;
        if (declarerPartnership == 0 && gBelowNS >= 100) gameWon = TRUE;
        if (declarerPartnership == 1 && gBelowEW >= 100) gameWon = TRUE;

        if (gameWon) {
            gBelowNS = 0;
            gBelowEW = 0;
            gGamesWon = llListReplaceList(gGamesWon,
                [llList2Integer(gGamesWon, declarerPartnership) + 1],
                declarerPartnership, declarerPartnership);
            gVulnerable = llListReplaceList(gVulnerable, [1],
                declarerPartnership, declarerPartnership);

            // Check rubber
            integer gamesDeclarerSide = llList2Integer(gGamesWon, declarerPartnership);
            if (gamesDeclarerSide == 2) {
                // Rubber bonus
                integer opponentGames = llList2Integer(gGamesWon, 1 - declarerPartnership);
                integer rubberBonus;
                if (opponentGames == 0) rubberBonus = 700;
                else rubberBonus = 500;
                aboveDeclarer += rubberBonus;
            }
        }

        // Apply above-the-line
        if (declarerPartnership == 0) gAboveNS += aboveDeclarer;
        else                          gAboveEW += aboveDeclarer;

    } else {
        // ---- Went down ----
        integer undertricks = -overtricks;

        if (gDoubled == 0) {
            if (vul) aboveDefenders = 100 * undertricks;
            else aboveDefenders = 50 * undertricks;
        } else {
            // Doubled undertrick schedule
            integer first;
            integer second;
            integer rest;
            if (vul) { first = 200; second = 300; rest = 300; }
            else     { first = 100; second = 200; rest = 200; }

            if (undertricks >= 1) aboveDefenders += first;
            if (undertricks >= 2) aboveDefenders += second;
            if (undertricks >= 3) aboveDefenders += (undertricks - 2) * rest;

            if (gDoubled == 2) aboveDefenders *= 2; // redoubled
        }

        integer defenders = 1 - declarerPartnership;
        if (defenders == 0) gAboveNS += aboveDefenders;
        else                gAboveEW += aboveDefenders;
    }

    // Build result string for display
    integer gamesNS  = llList2Integer(gGamesWon, 0);
    integer gamesEW  = llList2Integer(gGamesWon, 1);
    integer vulNS    = llList2Integer(gVulnerable, 0);
    integer vulEW    = llList2Integer(gVulnerable, 1);
    integer rubberDone = (gamesNS == 2 || gamesEW == 2);

    string vulStr = "";
    if (vulNS) vulStr += " [NS vul]";
    if (vulEW) vulStr += " [EW vul]";
    llSay(0, "Score — NS: " + (string)(gAboveNS + gBelowNS)
        + "  EW: " + (string)(gAboveEW + gBelowEW)
        + "  Games NS/EW: " + (string)gamesNS + "/" + (string)gamesEW
        + vulStr);

    llMessageLinked(LINK_SET, MSG_SCORE_UPDATE,
        (string)gamesNS + "|" + (string)gamesEW + "|"
        + (string)vulNS  + "|" + (string)vulEW  + "|"
        + (string)rubberDone,
        NULL_KEY);

    // Reset for new rubber if done
    if (rubberDone) {
        gBelowNS    = 0; gBelowEW    = 0;
        gAboveNS    = 0; gAboveEW    = 0;
        gGamesWon   = [0, 0];
        gVulnerable = [0, 0];
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gBelowNS    = 0; gBelowEW    = 0;
        gAboveNS    = 0; gAboveEW    = 0;
        gGamesWon   = [0, 0];
        gVulnerable = [0, 0];
        gDeclarer   = -1;
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == MSG_CONTRACT_SET) {
            // Cache contract: "declarer|level|suit|doubled"
            // Passed-out hand has declarer = -1
            list parts     = llParseString2List(str, ["|"], []);
            gDeclarer      = (integer)llList2String(parts, 0);
            gContractLevel = (integer)llList2String(parts, 1);
            gContractSuit  = (integer)llList2String(parts, 2);
            gDoubled       = (integer)llList2String(parts, 3);

        } else if (num == MSG_HAND_DONE) {
            // str = "last_trick_winner|tricks_ns|tricks_ew"
            list parts   = llParseString2List(str, ["|"], []);
            integer tricksNS = (integer)llList2String(parts, 1);
            integer tricksEW = (integer)llList2String(parts, 2);
            scoreHand(tricksNS, tricksEW);

        } else if (num == MSG_GAME_RESET) {
            // str="0" abort hand (preserve rubber); str="1" full reset
            gDeclarer = -1;
            if ((integer)str == 1) {
                gBelowNS = 0; gBelowEW = 0;
                gAboveNS = 0; gAboveEW = 0;
                gGamesWon   = [0, 0];
                gVulnerable = [0, 0];
            }
        }
    }
}
