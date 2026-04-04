// bot_ai.lsl
// Rule-based AI for bot-controlled seats.
// Responds to MSG_BOT_BID_REQUEST and MSG_BOT_PLAY_REQUEST for any seat
// that is currently unoccupied (seat.lsl routes requests here when no human
// is present).
//
// Bidding: Simplified Standard American (HCP + distribution)
// Play: Classic heuristics (2nd hand low, 3rd hand high, lead 4th best)
//
// Messages received:
//   MSG_BOT_BID_REQUEST  (220) — str="seat"
//   MSG_BOT_PLAY_REQUEST (221) — str="seat"
//   MSG_HAND_UPDATE      (202) — str="seat|c0|c1|..." cache all hands
//   MSG_CONTRACT_SET     (103) — str="declarer|level|suit|doubled" cache contract
//   MSG_TRICK_PLAYED     (402) — str="seat|card" track played cards
//   MSG_TRICK_DONE       (105) — str="winner|tricks_ns|tricks_ew" clear trick
//   MSG_BIDDING_START    (102) — str="dealer|first_bidder" reset auction state
//   MSG_BID_ADVANCE      (203) — str="seat" track auction progress
//   MSG_BID_RESPONSE     (300) — str="seat|bid" track bids by all seats
//
// Messages sent:
//   MSG_BID_RESPONSE     (300) — str="seat|bid"
//   MSG_PLAY_RESPONSE    (301) — str="seat|card"

// ---------------------------------------------------------------------------
// Message constants
// ---------------------------------------------------------------------------
integer MSG_CONTRACT_SET     = 103;
integer MSG_BIDDING_START    = 102;
integer MSG_TRICK_DONE       = 105;
integer MSG_HAND_UPDATE      = 202;
integer MSG_BID_ADVANCE      = 203;
integer MSG_BID_REQUEST      = 200;
integer MSG_PLAY_REQUEST     = 201;
integer MSG_BID_RESPONSE     = 300;
integer MSG_PLAY_RESPONSE    = 301;
integer MSG_TRICK_PLAYED     = 402;
integer MSG_BOT_BID_REQUEST  = 220;
integer MSG_BOT_PLAY_REQUEST = 221;

// ---------------------------------------------------------------------------
// Card helpers
// ---------------------------------------------------------------------------
integer cardSuit(integer card) { return card / 13; }
integer cardRank(integer card) { return card % 13; }

// HCP value: J=1 Q=2 K=3 A=4
integer hcp(integer card) {
    integer rank = cardRank(card);
    if (rank == 9)  return 1;  // Jack
    if (rank == 10) return 2;  // Queen
    if (rank == 11) return 3;  // King
    if (rank == 12) return 4;  // Ace
    return 0;
}

integer NORTH = 0;
integer SOUTH = 1;
integer EAST  = 2;
integer WEST  = 3;

integer partnership(integer seat) {
    if (seat == NORTH || seat == SOUTH) return 0;
    return 1;
}

// ---------------------------------------------------------------------------
// Bid encoding (must match bidding_engine.lsl)
// ---------------------------------------------------------------------------
integer BID_PASS     = 0;
integer BID_DOUBLE   = 1;
integer BID_REDOUBLE = 2;

integer makeBid(integer level, integer suit) { return level * 5 + suit; }
integer bidLevel(integer bid) { return bid / 5; }
integer bidSuit(integer bid)  { return bid % 5; }

// ---------------------------------------------------------------------------
// State: 4 hands, cached for bot decisions
// ---------------------------------------------------------------------------
list gHands = [];   // flat list: 52 entries; gHands[seat*13 + i] = card or -1

// Returns hand list for seat (13-element list, may contain -1 for played cards)
list getHand(integer seat) {
    return llList2List(gHands, seat * 13, seat * 13 + 12);
}

// Live unplayed cards for seat
list liveCards(integer seat) {
    list hand = getHand(seat);
    list live = [];
    integer i;
    for (i = 0; i < 13; i++) {
        integer c = llList2Integer(hand, i);
        if (c >= 0) live += [c];
    }
    return live;
}

// ---------------------------------------------------------------------------
// Auction tracking
// ---------------------------------------------------------------------------
integer gCurrentHighBid   = 0;   // highest real bid so far (0 = none)
integer gCurrentHighSeat  = -1;
integer gCurrentDoubled   = 0;
list    gAuction          = [];   // list of [seat, bid] pairs

// Contract (set after bidding)
integer gDeclarer      = -1;
integer gContractLevel = 0;
integer gContractSuit  = 0;
integer gDoubled       = 0;

// Current trick for play decisions
list    gCurrentTrick  = [];  // [seat, card, seat, card, ...]
integer gLedSuit       = -1;
integer gTrump         = -1;

// ---------------------------------------------------------------------------
// HCP and distribution count for a hand
// ---------------------------------------------------------------------------
integer countHCP(list hand) {
    integer total = 0;
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        total += hcp(llList2Integer(hand, i));
    }
    return total;
}

// Count cards of a suit
integer countSuit(list hand, integer suit) {
    integer n = 0;
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        if (cardSuit(llList2Integer(hand, i)) == suit) n++;
    }
    return n;
}

// Distribution points: 1 per card beyond 4 in longest suit
integer distribPts(list hand) {
    integer pts = 0;
    integer s;
    for (s = 0; s < 4; s++) {
        integer len = countSuit(hand, s);
        if (len > 4) pts += len - 4;
    }
    return pts;
}

// Longest suit (0-3); tie-break by rank of highest card
integer longestSuit(list hand) {
    integer best = 0;
    integer bestLen = 0;
    integer s;
    for (s = 0; s < 4; s++) {
        integer len = countSuit(hand, s);
        if (len > bestLen) {
            bestLen = len;
            best = s;
        }
    }
    return best;
}

// Is hand balanced (4333, 4432, 5332)?
integer isBalanced(list hand) {
    integer s;
    for (s = 0; s < 4; s++) {
        integer len = countSuit(hand, s);
        if (len < 2 || len > 5) return FALSE;
    }
    return TRUE;
}

// ---------------------------------------------------------------------------
// Bidding heuristics
// ---------------------------------------------------------------------------

// What has partner bid? Returns last real bid by partner, or 0.
integer partnerLastBid(integer mySeat) {
    integer partner = (mySeat + 2) % 4;
    integer i;
    integer lastBid = 0;
    for (i = 0; i < llGetListLength(gAuction); i += 2) {
        if (llList2Integer(gAuction, i) == partner) {
            integer b = llList2Integer(gAuction, i + 1);
            if (b > 2) lastBid = b; // real bid
        }
    }
    return lastBid;
}

// How many times has this seat bid?
integer timesIBid(integer mySeat) {
    integer count = 0;
    integer i;
    for (i = 0; i < llGetListLength(gAuction); i += 2) {
        if (llList2Integer(gAuction, i) == mySeat) {
            if (llList2Integer(gAuction, i + 1) > 2) count++;
        }
    }
    return count;
}

// Decide a bid for a bot seat
integer decideBid(integer seat) {
    list hand      = liveCards(seat);
    integer points = countHCP(hand) + distribPts(hand);
    integer hasBid = timesIBid(seat) > 0;
    integer pBid   = partnerLastBid(seat);

    // ---- Opening bid (no real bids yet, or we haven't bid) ----
    if (gCurrentHighBid == 0 && !hasBid) {
        if (points < 12) return BID_PASS;
        if (points >= 15 && points <= 17 && isBalanced(hand)) {
            return makeBid(1, 4); // 1NT
        }
        return makeBid(1, longestSuit(hand));
    }

    // ---- Response to partner's opening ----
    if (pBid > 0 && !hasBid) {
        integer pLevel = bidLevel(pBid);
        integer pSuit  = bidSuit(pBid);

        if (points < 6) return BID_PASS;

        // Raise partner's major with 3+ card support
        if ((pSuit == 2 || pSuit == 3) && countSuit(hand, pSuit) >= 3) {
            if (points >= 13) {
                // Jump to game
                integer gameLevel = (pSuit == 2 || pSuit == 3) ? 4 : 5;
                integer nextBid = makeBid(gameLevel, pSuit);
                if (nextBid > gCurrentHighBid) return nextBid;
            }
            integer raiseBid = makeBid(pLevel + 1, pSuit);
            if (raiseBid > gCurrentHighBid) return raiseBid;
        }

        // 1NT response with 6-9 balanced
        if (points >= 6 && points <= 9 && isBalanced(hand)) {
            integer ntBid = makeBid(1, 4);
            if (ntBid > gCurrentHighBid) return ntBid;
        }

        // Bid new suit at 1-level
        if (points >= 6) {
            integer s;
            for (s = 3; s >= 0; s--) { // try majors first
                if (countSuit(hand, s) >= 4) {
                    integer nb = makeBid(1, s);
                    if (nb > gCurrentHighBid) return nb;
                }
            }
        }

        if (points >= 10) {
            integer nb = makeBid(2, longestSuit(hand));
            if (nb > gCurrentHighBid) return nb;
        }

        return BID_PASS;
    }

    // ---- We've already bid or opponents opened ----
    // Simple: keep quiet unless we have extra values
    if (points >= 17 && gCurrentHighBid == 0) {
        return makeBid(1, longestSuit(hand));
    }

    return BID_PASS;
}

// ---------------------------------------------------------------------------
// Card play heuristics
// ---------------------------------------------------------------------------

// Highest card of suit in hand
integer highestOfSuit(list hand, integer suit) {
    integer best = -1;
    integer bestRank = -1;
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        integer c = llList2Integer(hand, i);
        if (cardSuit(c) == suit && cardRank(c) > bestRank) {
            best = c;
            bestRank = cardRank(c);
        }
    }
    return best;
}

// Lowest card of suit in hand
integer lowestOfSuit(list hand, integer suit) {
    integer best = -1;
    integer bestRank = 14;
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        integer c = llList2Integer(hand, i);
        if (cardSuit(c) == suit && cardRank(c) < bestRank) {
            best = c;
            bestRank = cardRank(c);
        }
    }
    return best;
}

// 4th-best card of suit (for opening leads vs NT)
integer fourthBestOfSuit(list hand, integer suit) {
    // Collect cards of suit, sort descending, return 4th (index 3) or lowest
    list cards = [];
    integer i;
    for (i = 0; i < llGetListLength(hand); i++) {
        integer c = llList2Integer(hand, i);
        if (cardSuit(c) == suit) cards += [c];
    }
    if (llGetListLength(cards) < 4) return lowestOfSuit(hand, suit);
    // Sort descending by rank (insertion sort)
    integer n = llGetListLength(cards);
    integer j;
    for (i = 1; i < n; i++) {
        integer key = llList2Integer(cards, i);
        j = i - 1;
        while (j >= 0 && cardRank(llList2Integer(cards, j)) < cardRank(key)) {
            cards = llListReplaceList(cards, [llList2Integer(cards, j)], j+1, j+1);
            j--;
        }
        cards = llListReplaceList(cards, [key], j+1, j+1);
    }
    return llList2Integer(cards, 3);
}

// Current winning card in the trick
integer currentWinner() {
    if (llGetListLength(gCurrentTrick) == 0) return -1;
    integer winningSeat = llList2Integer(gCurrentTrick, 0);
    integer winningCard = llList2Integer(gCurrentTrick, 1);
    integer winningIsTrump = (gTrump < 4 && cardSuit(winningCard) == gTrump);
    integer i;
    for (i = 2; i < llGetListLength(gCurrentTrick); i += 2) {
        integer c    = llList2Integer(gCurrentTrick, i + 1);
        integer suit = cardSuit(c);
        integer rank = cardRank(c);
        integer isTrump = (gTrump < 4 && suit == gTrump);
        if (isTrump && !winningIsTrump) {
            winningCard = c; winningIsTrump = TRUE;
        } else if (isTrump && winningIsTrump && rank > cardRank(winningCard)) {
            winningCard = c;
        } else if (!isTrump && !winningIsTrump && suit == gLedSuit && rank > cardRank(winningCard)) {
            winningCard = c;
        }
    }
    return winningCard;
}

// Is the current winning card held by our partnership?
integer partnerIsWinning(integer seat) {
    if (llGetListLength(gCurrentTrick) == 0) return FALSE;
    integer winningSeat = llList2Integer(gCurrentTrick, 0);
    // Find who played the current winner
    integer winCard = currentWinner();
    integer i;
    for (i = 0; i < llGetListLength(gCurrentTrick); i += 2) {
        if (llList2Integer(gCurrentTrick, i + 1) == winCard) {
            winningSeat = llList2Integer(gCurrentTrick, i);
        }
    }
    return (partnership(winningSeat) == partnership(seat));
}

// Decide which card to play
integer decidePlay(integer seat) {
    list hand = liveCards(seat);
    if (llGetListLength(hand) == 0) return -1;

    integer cardsInTrick = llGetListLength(gCurrentTrick) / 2;

    // ---- Leading ----
    if (cardsInTrick == 0) {
        integer leadSuit;
        if (gTrump == 4) {
            // NT: lead 4th best of longest suit
            leadSuit = longestSuit(hand);
            return fourthBestOfSuit(hand, leadSuit);
        } else {
            // Suit contract: lead top of longest side suit
            // Prefer suits with sequences; simplification: lead longest non-trump suit
            integer best = -1;
            integer bestLen = 0;
            integer s;
            for (s = 0; s < 4; s++) {
                if (s == gTrump) continue;
                integer len = countSuit(hand, s);
                if (len > bestLen) { bestLen = len; best = s; }
            }
            if (best == -1) {
                // Only trump left
                return lowestOfSuit(hand, gTrump);
            }
            return highestOfSuit(hand, best); // top of sequence heuristic
        }
    }

    // ---- Must follow suit if possible ----
    integer hasSuit = (countSuit(hand, gLedSuit) > 0);

    if (hasSuit) {
        // Standard: 2nd seat low, 3rd seat high
        if (cardsInTrick == 1) {
            // 2nd seat: play low of led suit
            return lowestOfSuit(hand, gLedSuit);
        }
        if (cardsInTrick == 2) {
            // 3rd seat: play high of led suit
            return highestOfSuit(hand, gLedSuit);
        }
        // 4th seat: beat current winner if possible, else low
        integer winCard = currentWinner();
        integer winRank = cardRank(winCard);
        if (partnerIsWinning(seat)) {
            return lowestOfSuit(hand, gLedSuit); // partner winning, play low
        }
        // Try to beat it
        integer i;
        integer bestBeater = -1;
        integer bestBeaterRank = 99;
        for (i = 0; i < llGetListLength(hand); i++) {
            integer c = llList2Integer(hand, i);
            if (cardSuit(c) == gLedSuit && cardRank(c) > winRank
                    && cardRank(c) < bestBeaterRank) {
                bestBeater = c;
                bestBeaterRank = cardRank(c);
            }
        }
        if (bestBeater != -1) return bestBeater;
        return lowestOfSuit(hand, gLedSuit);
    }

    // ---- Void in led suit ----
    if (gTrump < 4 && countSuit(hand, gTrump) > 0 && !partnerIsWinning(seat)) {
        // Ruff with lowest trump
        return lowestOfSuit(hand, gTrump);
    }

    // Discard: throw lowest card overall
    integer lowest = llList2Integer(hand, 0);
    integer i;
    for (i = 1; i < llGetListLength(hand); i++) {
        integer c = llList2Integer(hand, i);
        if (cardRank(c) < cardRank(lowest)) lowest = c;
    }
    return lowest;
}

// ---------------------------------------------------------------------------
// Initialise flat hand storage
// ---------------------------------------------------------------------------
initHands() {
    gHands = [];
    integer i;
    for (i = 0; i < 52; i++) gHands += [-1];
}

storeHand(integer seat, list cards) {
    integer i;
    for (i = 0; i < 13; i++) {
        integer idx = seat * 13 + i;
        integer val = (i < llGetListLength(cards)) ? llList2Integer(cards, i) : -1;
        gHands = llListReplaceList(gHands, [val], idx, idx);
    }
}

// Remove a played card from cached hand
removeCardFromHand(integer seat, integer card) {
    integer i;
    for (i = 0; i < 13; i++) {
        integer idx = seat * 13 + i;
        if (llList2Integer(gHands, idx) == card) {
            gHands = llListReplaceList(gHands, [-1], idx, idx);
            return;
        }
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        initHands();
        gCurrentHighBid  = 0;
        gCurrentHighSeat = -1;
        gCurrentDoubled  = 0;
        gAuction         = [];
        gCurrentTrick    = [];
        gLedSuit         = -1;
        gTrump           = -1;
    }

    link_message(integer sender, integer num, string str, key id) {

        if (num == MSG_HAND_UPDATE) {
            // str = "seat|c0|c1|..."
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            list cards = [];
            integer i;
            for (i = 1; i < llGetListLength(parts); i++) {
                cards += [(integer)llList2String(parts, i)];
            }
            storeHand(seat, cards);

        } else if (num == MSG_BIDDING_START) {
            gCurrentHighBid  = 0;
            gCurrentHighSeat = -1;
            gCurrentDoubled  = 0;
            gAuction         = [];

        } else if (num == MSG_BID_RESPONSE) {
            // Track all bids including human bids
            list parts = llParseString2List(str, ["|"], []);
            integer bidSeat = (integer)llList2String(parts, 0);
            integer bid     = (integer)llList2String(parts, 1);
            gAuction += [bidSeat, bid];
            if (bid > 2) { // real bid
                gCurrentHighBid  = bid;
                gCurrentHighSeat = bidSeat;
                gCurrentDoubled  = 0;
            } else if (bid == BID_DOUBLE) {
                gCurrentDoubled = 1;
            } else if (bid == BID_REDOUBLE) {
                gCurrentDoubled = 2;
            }

        } else if (num == MSG_CONTRACT_SET) {
            list parts     = llParseString2List(str, ["|"], []);
            gDeclarer      = (integer)llList2String(parts, 0);
            gContractLevel = (integer)llList2String(parts, 1);
            gContractSuit  = (integer)llList2String(parts, 2);
            gDoubled       = (integer)llList2String(parts, 3);
            gTrump         = gContractSuit; // 4=NT, bot checks gTrump < 4

        } else if (num == MSG_TRICK_PLAYED) {
            list parts = llParseString2List(str, ["|"], []);
            integer seat = (integer)llList2String(parts, 0);
            integer card = (integer)llList2String(parts, 1);
            if (llGetListLength(gCurrentTrick) == 0) {
                gLedSuit = cardSuit(card);
            }
            gCurrentTrick += [seat, card];
            removeCardFromHand(seat, card);

        } else if (num == MSG_TRICK_DONE) {
            gCurrentTrick = [];
            gLedSuit = -1;

        } else if (num == MSG_BOT_BID_REQUEST) {
            integer seat = (integer)str;
            integer bid  = decideBid(seat);
            llMessageLinked(LINK_SET, MSG_BID_RESPONSE,
                (string)seat + "|" + (string)bid, NULL_KEY);

        } else if (num == MSG_BOT_PLAY_REQUEST) {
            integer seat = (integer)str;
            integer card = decidePlay(seat);
            if (card == -1) {
                // No cards left — shouldn't happen; pass a safe fallback
                list hand = liveCards(seat);
                if (llGetListLength(hand) > 0)
                    card = llList2Integer(hand, 0);
            }
            llMessageLinked(LINK_SET, MSG_PLAY_RESPONSE,
                (string)seat + "|" + (string)card, NULL_KEY);
        }
    }
}
