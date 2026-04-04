// bidding_engine.lsl
// Manages the auction: validates bids, tracks the contract,
// detects auction end, and determines the declarer.
//
// Messages received:
//   MSG_BIDDING_START (102) — str="dealer|first_bidder", reset auction
//   MSG_BID_RESPONSE  (300) — str="seat|bid", process a bid
//
// Messages sent:
//   MSG_BID_ADVANCE   (203) — str="next_seat", tell controller whose turn
//   MSG_CONTRACT_SET  (103) — str="declarer|level|suit|doubled"
//   MSG_BID_INVALID   (204) — str="seat|reason", bounce invalid bid back

// ---------------------------------------------------------------------------
// Message constants
// ---------------------------------------------------------------------------
integer MSG_BIDDING_START = 102;
integer MSG_CONTRACT_SET  = 103;
integer MSG_BID_REQUEST   = 200;
integer MSG_BID_ADVANCE   = 203;
integer MSG_BID_INVALID   = 204;
integer MSG_BID_RESPONSE  = 300;

// ---------------------------------------------------------------------------
// Bid encoding
//   level * 5 + suit  where suit: 0=C 1=D 2=H 3=S 4=NT
//   Range 5..39 (1C=5 … 7NT=39)
//   Special: PASS=0 DOUBLE=1 REDOUBLE=2
// ---------------------------------------------------------------------------
integer BID_PASS      = 0;
integer BID_DOUBLE    = 1;
integer BID_REDOUBLE  = 2;
integer BID_MIN       = 5;   // 1C

integer bidLevel(integer bid) { return bid / 5; }
integer bidSuit(integer bid)  { return bid % 5; }

integer NORTH = 0;
integer SOUTH = 1;
integer EAST  = 2;
integer WEST  = 3;

// ---------------------------------------------------------------------------
// Auction state
// ---------------------------------------------------------------------------
integer gDealer       = NORTH;
integer gCurrentBidder = NORTH;

// Current highest contract bid (5..39), 0 if none yet
integer gHighBid      = 0;

// Seat that made gHighBid
integer gHighBidder   = -1;

// Doubling state: 0=none 1=doubled 2=redoubled
integer gDoubled      = 0;

// Who doubled (needed for contract ownership check)
integer gDoubler      = -1;

// Consecutive passes since last real bid (or since auction start)
integer gPassCount    = 0;

// Full auction log: list of bid integers in order
list gAuction = [];

// Has any real (non-pass) bid been made?
integer gAnyBid = FALSE;

// First bid per partnership per denomination — used for declarer determination
// "declarer" is the first player of the declaring partnership to bid that suit
// We track: for each seat, first time they bid each denomination
// Simpler: track first bidder per partnership per suit (0..4)
// [NS_C, NS_D, NS_H, NS_S, NS_NT, EW_C, EW_D, EW_H, EW_S, EW_NT]
list gFirstBidder = [-1,-1,-1,-1,-1, -1,-1,-1,-1,-1];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

integer partnership(integer seat) {
    if (seat == NORTH || seat == SOUTH) return 0;
    return 1;
}

integer leftOf(integer seat) { return (seat + 1) % 4; }

string bidStr(integer bid) {
    if (bid == BID_PASS)     return "Pass";
    if (bid == BID_DOUBLE)   return "Dbl";
    if (bid == BID_REDOUBLE) return "Rdbl";
    integer level = bidLevel(bid);
    integer suit  = bidSuit(bid);
    list suitNames = ["C","D","H","S","NT"];
    return (string)level + llList2String(suitNames, suit);
}

string seatName(integer seat) {
    list names = ["North","South","East","West"];
    return llList2String(names, seat);
}

// ---------------------------------------------------------------------------
// Reset for a new auction
// ---------------------------------------------------------------------------
resetAuction(integer dealer, integer firstBidder) {
    gDealer        = dealer;
    gCurrentBidder = firstBidder;
    gHighBid       = 0;
    gHighBidder    = -1;
    gDoubled       = 0;
    gDoubler       = -1;
    gPassCount     = 0;
    gAuction       = [];
    gAnyBid        = FALSE;
    gFirstBidder   = [-1,-1,-1,-1,-1, -1,-1,-1,-1,-1];
}

// ---------------------------------------------------------------------------
// Bid validation
// Returns "" if valid, or an error string
// ---------------------------------------------------------------------------
string validateBid(integer seat, integer bid) {
    if (bid == BID_PASS) return "";  // always legal

    if (bid == BID_DOUBLE) {
        // Must double opponents' contract that is currently undoubled
        if (gHighBid == 0) return "Nothing to double";
        if (partnership(gHighBidder) == partnership(seat)) return "Cannot double own side";
        if (gDoubled == 1) return "Already doubled";
        if (gDoubled == 2) return "Already redoubled";
        return "";
    }

    if (bid == BID_REDOUBLE) {
        if (gDoubled != 1) return "Not doubled";
        if (partnership(gDoubler) == partnership(seat)) return "Cannot redouble own double";
        return "";
    }

    // Real bid: must be strictly higher than current high bid
    if (bid <= gHighBid) return "Bid must be higher than " + bidStr(gHighBid);
    if (bid < BID_MIN || bid > 39) return "Invalid bid value";
    return "";
}

// ---------------------------------------------------------------------------
// Record first-bidder per partnership per denomination
// ---------------------------------------------------------------------------
recordFirstBidder(integer seat, integer bid) {
    integer suit = bidSuit(bid);
    integer p    = partnership(seat);
    integer idx  = p * 5 + suit;
    if (llList2Integer(gFirstBidder, idx) == -1) {
        gFirstBidder = llListReplaceList(gFirstBidder, [seat], idx, idx);
    }
}

// ---------------------------------------------------------------------------
// Determine declarer after auction ends
// Declarer = first player of the declaring partnership to bid the final suit
// ---------------------------------------------------------------------------
integer determineDeclarerSeat(integer finalBidder, integer finalSuit) {
    integer p   = partnership(finalBidder);
    integer idx = p * 5 + finalSuit;
    integer first = llList2Integer(gFirstBidder, idx);
    if (first == -1) return finalBidder; // fallback
    return first;
}

// ---------------------------------------------------------------------------
// Process a bid
// ---------------------------------------------------------------------------
processBid(integer seat, integer bid) {
    // Validate
    string err = validateBid(seat, bid);
    if (err != "") {
        llMessageLinked(LINK_SET, MSG_BID_INVALID,
            (string)seat + "|" + err, NULL_KEY);
        // Re-request bid from same seat
        llMessageLinked(LINK_SET, MSG_BID_REQUEST, (string)seat, NULL_KEY);
        return;
    }

    // Record in auction log
    gAuction += [bid];
    llSay(0, seatName(seat) + ": " + bidStr(bid));

    if (bid == BID_PASS) {
        gPassCount++;

        // Auction ends if:
        //   4 passes from the start (all pass), or
        //   3 passes after a real bid
        if (!gAnyBid && gPassCount == 4) {
            auctionPassed();
            return;
        }
        if (gAnyBid && gPassCount == 3) {
            auctionComplete();
            return;
        }

    } else if (bid == BID_DOUBLE) {
        gDoubled  = 1;
        gDoubler  = seat;
        gPassCount = 0;

    } else if (bid == BID_REDOUBLE) {
        gDoubled  = 2;
        gPassCount = 0;

    } else {
        // Real bid
        gHighBid    = bid;
        gHighBidder = seat;
        gDoubled    = 0;
        gDoubler    = -1;
        gPassCount  = 0;
        gAnyBid     = TRUE;
        recordFirstBidder(seat, bid);
    }

    // Advance to next bidder
    gCurrentBidder = leftOf(seat);
    llMessageLinked(LINK_SET, MSG_BID_ADVANCE, (string)gCurrentBidder, NULL_KEY);
}

// ---------------------------------------------------------------------------
// All 4 players passed without a bid — hand is passed out, re-deal
// ---------------------------------------------------------------------------
auctionPassed() {
    llSay(0, "Passed out — re-dealing.");
    // Signal game_controller to re-deal (reuse MSG_CONTRACT_SET with level=0)
    llMessageLinked(LINK_SET, MSG_CONTRACT_SET, "-1|0|0|0", NULL_KEY);
}

// ---------------------------------------------------------------------------
// Auction complete — emit contract
// ---------------------------------------------------------------------------
auctionComplete() {
    integer declarer = determineDeclarerSeat(gHighBidder, bidSuit(gHighBid));
    integer level    = bidLevel(gHighBid);
    integer suit     = bidSuit(gHighBid);

    list suitNames = ["Clubs","Diamonds","Hearts","Spades","NT"];
    string doubledStr = "";
    if (gDoubled == 1) doubledStr = " Doubled";
    else if (gDoubled == 2) doubledStr = " Redoubled";
    llSay(0, "Contract: " + (string)level + llList2String(suitNames, suit)
        + doubledStr + " by " + seatName(declarer));

    llMessageLinked(LINK_SET, MSG_CONTRACT_SET,
        (string)declarer + "|" + (string)level + "|"
        + (string)suit + "|" + (string)gDoubled,
        NULL_KEY);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        resetAuction(NORTH, leftOf(NORTH));
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == MSG_BIDDING_START) {
            // str = "dealer|first_bidder"
            list parts = llParseString2List(str, ["|"], []);
            resetAuction((integer)llList2String(parts,0),
                         (integer)llList2String(parts,1));

        } else if (num == MSG_BID_RESPONSE) {
            // str = "seat|bid"
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer bid  = (integer)llList2String(parts, 1);
            // Only process if it's actually this seat's turn
            if (seat == gCurrentBidder) {
                processBid(seat, bid);
            }
        }
    }
}
