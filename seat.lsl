// seat.lsl
// Template script for a seat prim (North / South / East / West).
// One copy per seat prim; set SEAT_ID via the integer at the top.
//
// Responsibilities:
//   - Detect avatar sit / unsit events
//   - Broadcast seat occupancy to the rest of the table
//   - Display floating name tag above the seat
//   - Give the HUD to a human who sits down
//   - Relay human bid/play responses from the private listen channel
//   - When seat is vacant, forward BID_REQUEST / PLAY_REQUEST to bot_ai

// ---------------------------------------------------------------------------
// CONFIGURE THIS PER SEAT PRIM
// 0=North 1=South 2=East 3=West
// ---------------------------------------------------------------------------
integer SEAT_ID = 0;

// Bot display names per seat
list BOT_NAMES = ["North Bot", "South Bot", "East Bot", "West Bot"];

// HUD object name in table inventory
string HUD_OBJECT = "Bridge HUD";

// ---------------------------------------------------------------------------
// Message constants (must match game_controller.lsl)
// ---------------------------------------------------------------------------
integer MSG_BID_REQUEST     = 200;
integer MSG_PLAY_REQUEST    = 201;
integer MSG_HAND_UPDATE     = 202;
integer MSG_BID_RESPONSE    = 300;
integer MSG_PLAY_RESPONSE   = 301;
integer MSG_SEAT_OCCUPIED   = 403;
integer MSG_SEAT_VACATED    = 404;

// bot_ai forward targets
integer MSG_BOT_BID_REQUEST  = 220;
integer MSG_BOT_PLAY_REQUEST = 221;

// ---------------------------------------------------------------------------
// Private listen channel for this seat's HUD
// Derived from seat ID to be unique per seat within the object
// ---------------------------------------------------------------------------
integer listenChannel() {
    // Channels are negative to avoid public chat; unique per seat
    return -7770 - SEAT_ID;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
key     gAvatarKey    = NULL_KEY;  // seated avatar, or NULL_KEY if empty
string  gAvatarName   = "";
integer gListenHandle = -1;
integer gIsHuman      = FALSE;     // TRUE when a real avatar is seated

// Pending hand for this seat (received from deck_manager via MSG_HAND_UPDATE)
// Stored so we can pass it to the HUD after a new deal
string gHandStr = "";

// ---------------------------------------------------------------------------
// Floating text
// ---------------------------------------------------------------------------
updateNameTag() {
    string direction;
    if (SEAT_ID == 0) direction = "North";
    else if (SEAT_ID == 1) direction = "South";
    else if (SEAT_ID == 2) direction = "East";
    else direction = "West";

    if (gIsHuman) {
        llSetText(direction + "\n" + gAvatarName, <1,1,1>, 1.0);
    } else {
        llSetText(direction + "\n" + llList2String(BOT_NAMES, SEAT_ID), <0.6,0.6,0.6>, 0.8);
    }
}

// ---------------------------------------------------------------------------
// Sit handler
// ---------------------------------------------------------------------------
onSit(key avatarKey) {
    gAvatarKey  = avatarKey;
    gAvatarName = llGetDisplayName(avatarKey);
    gIsHuman    = TRUE;

    updateNameTag();

    // Give HUD if it exists in inventory
    if (llGetInventoryType(HUD_OBJECT) == INVENTORY_OBJECT) {
        llGiveInventory(avatarKey, HUD_OBJECT);
    }

    // Open private listen channel for this seat
    if (gListenHandle != -1) llListenRemove(gListenHandle);
    gListenHandle = llListen(listenChannel(), "", avatarKey, "");

    // Notify the rest of the table
    llMessageLinked(LINK_SET, MSG_SEAT_OCCUPIED,
        (string)SEAT_ID + "|" + gAvatarName, NULL_KEY);

    // Send current hand to the HUD channel so the player can see their cards
    if (gHandStr != "") {
        llSay(listenChannel(), "HAND|" + gHandStr);
    }
}

// ---------------------------------------------------------------------------
// Unsit / leave handler
// ---------------------------------------------------------------------------
onUnsit() {
    gIsHuman   = FALSE;
    gAvatarKey = NULL_KEY;
    gAvatarName = "";

    if (gListenHandle != -1) {
        llListenRemove(gListenHandle);
        gListenHandle = -1;
    }

    updateNameTag();

    // Notify table — bot takes over
    llMessageLinked(LINK_SET, MSG_SEAT_VACATED, (string)SEAT_ID, NULL_KEY);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gIsHuman = FALSE;
        updateNameTag();
        // Allow any avatar to sit
        llSitTarget(<0,0,0.5>, ZERO_ROTATION);
    }

    changed(integer change) {
        if (change & CHANGED_LINK) {
            key sitter = llAvatarOnSitTarget();
            if (sitter != NULL_KEY && sitter != gAvatarKey) {
                // New avatar sat down
                onSit(sitter);
            } else if (sitter == NULL_KEY && gIsHuman) {
                // Avatar stood up
                onUnsit();
            }
        }
    }

    // Relay HUD input back into the link message bus
    listen(integer channel, string name, key id, string message) {
        if (channel == listenChannel() && id == gAvatarKey) {
            list parts = llParseString2List(message, ["|"], []);
            string msgType = llList2String(parts, 0);

            if (msgType == "BID") {
                // message = "BID|bid_integer"
                string bid = llList2String(parts, 1);
                llMessageLinked(LINK_SET, MSG_BID_RESPONSE,
                    (string)SEAT_ID + "|" + bid, NULL_KEY);

            } else if (msgType == "PLAY") {
                // message = "PLAY|card_integer"
                string card = llList2String(parts, 1);
                llMessageLinked(LINK_SET, MSG_PLAY_RESPONSE,
                    (string)SEAT_ID + "|" + card, NULL_KEY);
            }
        }
    }

    link_message(integer sender, integer num, string str, key id) {
        // Store hand update for this seat
        if (num == MSG_HAND_UPDATE) {
            list parts = llParseString2List(str, ["|"], []);
            integer targetSeat = (integer)llList2String(parts, 0);
            if (targetSeat == SEAT_ID) {
                gHandStr = str;
                // If human is seated, push hand to HUD immediately
                if (gIsHuman) {
                    llSay(listenChannel(), "HAND|" + str);
                }
            }

        // Bid request for this seat
        } else if (num == MSG_BID_REQUEST) {
            integer targetSeat = (integer)str;
            if (targetSeat == SEAT_ID) {
                if (gIsHuman) {
                    // Notify HUD to show bidding UI
                    llSay(listenChannel(), "BID_PROMPT");
                } else {
                    // Forward to bot_ai
                    llMessageLinked(LINK_SET, MSG_BOT_BID_REQUEST,
                        (string)SEAT_ID, NULL_KEY);
                }
            }

        // Play request for this seat
        } else if (num == MSG_PLAY_REQUEST) {
            integer targetSeat = (integer)str;
            if (targetSeat == SEAT_ID) {
                if (gIsHuman) {
                    // Notify HUD to enable card selection
                    llSay(listenChannel(), "PLAY_PROMPT");
                } else {
                    // Forward to bot_ai
                    llMessageLinked(LINK_SET, MSG_BOT_PLAY_REQUEST,
                        (string)SEAT_ID, NULL_KEY);
                }
            }
        }
    }
}
