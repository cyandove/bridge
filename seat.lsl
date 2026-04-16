// seat.lsl
// Template script for a seat prim (North / South / East / West).
// One copy per seat prim; set SEAT_ID via the integer at the top.
//
// Responsibilities:
//   - Detect avatar sit / unsit events
//   - Broadcast seat occupancy to the rest of the table
//   - Display floating name tag above the seat
//   - Give the HUD to a human who sits down, then push the seat ID to it
//   - Relay human bid/play responses from the private listen channel
//   - When seat is vacant, forward BID_REQUEST / PLAY_REQUEST to bot_ai

// ---------------------------------------------------------------------------
// CONFIGURE THIS PER SEAT PRIM
// 0=North 1=South 2=East 3=West
// ---------------------------------------------------------------------------
integer SEAT_ID = 0;

// Bot display names per seat
list BOT_NAMES = ["North Bot", "South Bot", "East Bot", "West Bot"];

// HUD object name in table inventory (single object, no per-seat variants)
string HUD_OBJECT = "Bridge HUD";

// Handshake channel — fixed, matches hud_controller.lsl
integer HUD_HANDSHAKE_CHANNEL = -7769;

// ---------------------------------------------------------------------------
// Message constants (must match game_controller.lsl)
// ---------------------------------------------------------------------------
integer MSG_BID_REQUEST      = 200;
integer MSG_PLAY_REQUEST     = 201;
integer MSG_HAND_UPDATE      = 202;
integer MSG_BID_RESPONSE     = 300;
integer MSG_PLAY_RESPONSE    = 301;
integer MSG_SEAT_OCCUPIED    = 403;
integer MSG_SEAT_VACATED     = 404;

// bot_ai forward targets
integer MSG_BOT_BID_REQUEST  = 220;
integer MSG_BOT_PLAY_REQUEST = 221;

// ---------------------------------------------------------------------------
// Private listen channel for this seat's HUD
// ---------------------------------------------------------------------------
integer listenChannel() {
    return -7770 - SEAT_ID;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
key     gAvatarKey        = NULL_KEY;
string  gAvatarName       = "";
integer gListenHandle     = -1;
integer gHandshakeHandle  = -1;
integer gIsHuman          = FALSE;

string gHandStr = "";

// ---------------------------------------------------------------------------
// Floating text
// ---------------------------------------------------------------------------
updateNameTag() {
    string direction;
    if (SEAT_ID == 0)      direction = "North";
    else if (SEAT_ID == 1) direction = "South";
    else if (SEAT_ID == 2) direction = "East";
    else                   direction = "West";

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

    // Give HUD if not already in avatar's inventory
    if (llGetInventoryType(HUD_OBJECT) == INVENTORY_OBJECT) {
        llGiveInventory(avatarKey, HUD_OBJECT);
    }

    // Open private listen for this seat
    if (gListenHandle != -1) llListenRemove(gListenHandle);
    gListenHandle = llListen(listenChannel(), "", avatarKey, "");

    // Listen for HUD_READY in case avatar attaches HUD after sitting
    if (gHandshakeHandle != -1) llListenRemove(gHandshakeHandle);
    gHandshakeHandle = llListen(HUD_HANDSHAKE_CHANNEL, "", NULL_KEY, "");

    // Push seat ID to HUD via the handshake channel
    // llRegionSayTo reaches worn attachments on the named avatar
    llRegionSayTo(avatarKey, HUD_HANDSHAKE_CHANNEL, "SEAT|" + (string)SEAT_ID);

    // Notify the rest of the table
    llMessageLinked(LINK_SET, MSG_SEAT_OCCUPIED,
        (string)SEAT_ID + "|" + gAvatarName, NULL_KEY);

    // Send current hand to HUD if a deal is already in progress
    if (gHandStr != "") {
        llRegionSayTo(avatarKey, listenChannel(), "HAND|" + gHandStr);
    }
}

// ---------------------------------------------------------------------------
// Unsit handler
// ---------------------------------------------------------------------------
onUnsit() {
    gIsHuman    = FALSE;
    gAvatarKey  = NULL_KEY;
    gAvatarName = "";

    if (gListenHandle != -1) {
        llListenRemove(gListenHandle);
        gListenHandle = -1;
    }
    if (gHandshakeHandle != -1) {
        llListenRemove(gHandshakeHandle);
        gHandshakeHandle = -1;
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
        // Basic Chair
        // <0.7, 0.0, -0.05>, <0.00000, 0.08716, 0.00000, 0.99619>
        llSitTarget(<0.7, 0.0, -0.05>, <0.00000, 0.08716, 0.00000, 0.99619>);
    }

    changed(integer change) {
        if (change & CHANGED_LINK) {
            key sitter = llAvatarOnSitTarget();
            if (sitter != NULL_KEY && sitter != gAvatarKey) {
                onSit(sitter);
            } else if (sitter == NULL_KEY && gIsHuman) {
                onUnsit();
            }
        }
    }

    listen(integer channel, string name, key id, string message) {
        if (channel == HUD_HANDSHAKE_CHANNEL) {
            list parts = llParseString2List(message, ["|"], []);
            if (llList2String(parts, 0) == "HUD_READY"
                    && (key)llList2String(parts, 1) == gAvatarKey) {
                llRegionSayTo(gAvatarKey, HUD_HANDSHAKE_CHANNEL,
                    "SEAT|" + (string)SEAT_ID);
            }
            return;
        }

        if (channel == listenChannel() && id == gAvatarKey) {
            list parts = llParseString2List(message, ["|"], []);
            string msgType = llList2String(parts, 0);

            if (msgType == "BID") {
                string bid = llList2String(parts, 1);
                llMessageLinked(LINK_SET, MSG_BID_RESPONSE,
                    (string)SEAT_ID + "|" + bid, NULL_KEY);

            } else if (msgType == "PLAY") {
                string card = llList2String(parts, 1);
                llMessageLinked(LINK_SET, MSG_PLAY_RESPONSE,
                    (string)SEAT_ID + "|" + card, NULL_KEY);
            }
        }
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == MSG_HAND_UPDATE) {
            list parts = llParseString2List(str, ["|"], []);
            integer targetSeat = (integer)llList2String(parts, 0);
            if (targetSeat == SEAT_ID) {
                gHandStr = str;
                if (gIsHuman) {
                    llRegionSayTo(gAvatarKey, listenChannel(), "HAND|" + str);
                }
            }

        } else if (num == MSG_BID_REQUEST) {
            integer targetSeat = (integer)str;
            if (targetSeat == SEAT_ID) {
                if (gIsHuman) {
                    llRegionSayTo(gAvatarKey, listenChannel(), "BID_PROMPT");
                } else {
                    llMessageLinked(LINK_SET, MSG_BOT_BID_REQUEST,
                        (string)SEAT_ID, NULL_KEY);
                }
            }

        } else if (num == MSG_PLAY_REQUEST) {
            integer targetSeat = (integer)str;
            if (targetSeat == SEAT_ID) {
                if (gIsHuman) {
                    llRegionSayTo(gAvatarKey, listenChannel(), "PLAY_PROMPT");
                } else {
                    llMessageLinked(LINK_SET, MSG_BOT_PLAY_REQUEST,
                        (string)SEAT_ID, NULL_KEY);
                }
            }
        }
    }
}
