// seat.lsl
// Seat prim script — identical copy goes in all four seat prims.
// Put a notecard named "seat_config" in each prim containing one line:
//   seat=0   (0=North  1=South  2=East  3=West)
//
// Responsibilities:
//   - Detect avatar sit / unsit events
//   - Broadcast seat occupancy to the rest of the table
//   - Display floating name tag above the seat
//   - Give the HUD to a human who sits down, then push the seat ID to it
//   - Relay human bid/play responses from the private listen channel
//   - When seat is vacant, forward BID_REQUEST / PLAY_REQUEST to bot_ai

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
string  NOTECARD       = "seat_config";
list    BOT_NAMES      = ["North Bot", "South Bot", "East Bot", "West Bot"];
string  HUD_OBJECT     = "Bridge HUD";
integer HUD_HANDSHAKE_CHANNEL = -7769;

// Message constants (must match game_controller.lsl)
integer MSG_BIDDING_START    = 102;
integer MSG_BID_REQUEST      = 200;
integer MSG_PLAY_REQUEST     = 201;
integer MSG_HAND_UPDATE      = 202;
integer MSG_BID_RESPONSE     = 300;
integer MSG_PLAY_RESPONSE    = 301;
integer MSG_BID_MADE         = 205;
integer MSG_SEAT_OCCUPIED    = 403;
integer MSG_SEAT_VACATED     = 404;

integer MSG_DUMMY_REVEAL     = 401;
integer MSG_BOT_BID_REQUEST  = 220;
integer MSG_BOT_PLAY_REQUEST = 221;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
integer gSeatID           = -1;

key     gAvatarKey        = NULL_KEY;
string  gAvatarName       = "";
integer gListenHandle     = -1;
integer gHandshakeHandle  = -1;
integer gIsHuman          = FALSE;
string  gHandStr          = "";
string  gLastBid          = "";

key     gNotecardQuery    = NULL_KEY;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
integer listenChannel() { return -7770 - gSeatID; }

updateNameTag() {
    if (gSeatID == -1) {
        llSetText("(no seat_config)", <1,0.3,0.3>, 1.0);
        return;
    }
    list dirs = ["North","South","East","West"];
    string direction = llList2String(dirs, gSeatID);
    string label;
    if (gIsHuman) {
        label = direction + "\n" + gAvatarName;
    } else {
        label = direction + "\n" + llList2String(BOT_NAMES, gSeatID);
    }
    if (gLastBid != "") label += "\n" + gLastBid;
    if (gIsHuman) {
        llSetText(label, <1,1,1>, 1.0);
    } else {
        llSetText(label, <0.6,0.6,0.6>, 0.8);
    }
}

// ---------------------------------------------------------------------------
// Notecard loading
// ---------------------------------------------------------------------------
loadNotecard() {
    if (llGetInventoryType(NOTECARD) != INVENTORY_NOTECARD) {
        llOwnerSay("[seat] notecard '" + NOTECARD + "' not found");
        return;
    }
    gNotecardQuery = llGetNotecardLine(NOTECARD, 0);
}

afterConfigLoaded() {
    llSitTarget(<0.7, 0.0, -0.05>, <0.00000, 0.08716, 0.00000, 0.99619>);
    updateNameTag();
}

// ---------------------------------------------------------------------------
// Sit / unsit handlers
// ---------------------------------------------------------------------------
onSit(key avatarKey) {
    gAvatarKey  = avatarKey;
    gAvatarName = llGetDisplayName(avatarKey);
    gIsHuman    = TRUE;

    updateNameTag();

    if (llGetInventoryType(HUD_OBJECT) == INVENTORY_OBJECT)
        llGiveInventory(avatarKey, HUD_OBJECT);

    if (gListenHandle != -1) llListenRemove(gListenHandle);
    gListenHandle = llListen(listenChannel(), "", NULL_KEY, "");

    if (gHandshakeHandle != -1) llListenRemove(gHandshakeHandle);
    gHandshakeHandle = llListen(HUD_HANDSHAKE_CHANNEL, "", NULL_KEY, "");

    llRegionSayTo(avatarKey, HUD_HANDSHAKE_CHANNEL, "SEAT|" + (string)gSeatID);

    llMessageLinked(LINK_SET, MSG_SEAT_OCCUPIED,
        (string)gSeatID + "|" + gAvatarName, NULL_KEY);

    if (gHandStr != "")
        llRegionSayTo(avatarKey, listenChannel(), "HAND|" + gHandStr);
}

onUnsit() {
    gIsHuman    = FALSE;
    gAvatarKey  = NULL_KEY;
    gAvatarName = "";

    if (gListenHandle != -1)    { llListenRemove(gListenHandle);    gListenHandle    = -1; }
    if (gHandshakeHandle != -1) { llListenRemove(gHandshakeHandle); gHandshakeHandle = -1; }

    updateNameTag();
    llMessageLinked(LINK_SET, MSG_SEAT_VACATED, (string)gSeatID, NULL_KEY);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
default {
    state_entry() {
        gSeatID  = -1;
        gIsHuman = FALSE;
        llSetText("Loading...", <0.5,0.5,0.5>, 1.0);
        loadNotecard();
    }

    dataserver(key query_id, string data) {
        if (query_id != gNotecardQuery) return;
        if (data == EOF) { afterConfigLoaded(); return; }

        // Ignore blank lines and comments
        if (data == "" || llGetSubString(data, 0, 0) == "#") {
            gNotecardQuery = llGetNotecardLine(NOTECARD, 1);
            return;
        }

        integer eq = llSubStringIndex(data, "=");
        if (eq != -1) {
            string key_name = llToLower(llGetSubString(data, 0, eq - 1));
            string val      = llGetSubString(data, eq + 1, -1);
            if (key_name == "seat") gSeatID = (integer)val;
        }
        // Only one config line expected; after reading it, signal done
        afterConfigLoaded();
    }

    changed(integer change) {
        if (change & CHANGED_INVENTORY) {
            llResetScript();
        }
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
                    "SEAT|" + (string)gSeatID);
            }
            return;
        }

        if (channel == listenChannel()) {
            list parts = llParseString2List(message, ["|"], []);
            string msgType = llList2String(parts, 0);

            if (msgType == "BID") {
                llMessageLinked(LINK_SET, MSG_BID_RESPONSE,
                    (string)gSeatID + "|" + llList2String(parts, 1), NULL_KEY);
            } else if (msgType == "PLAY") {
                llMessageLinked(LINK_SET, MSG_PLAY_RESPONSE,
                    (string)gSeatID + "|" + llList2String(parts, 1), NULL_KEY);
            }
        }
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == MSG_BIDDING_START) {
            gLastBid = "";
            updateNameTag();

        } else if (num == MSG_BID_MADE) {
            list parts = llParseString2List(str, ["|"], []);
            if ((integer)llList2String(parts, 0) == gSeatID) {
                gLastBid = llList2String(parts, 1);
                updateNameTag();
            }

        } else if (num == MSG_HAND_UPDATE) {
            integer targetSeat = (integer)llList2String(
                llParseString2List(str, ["|"], []), 0);
            if (targetSeat == gSeatID) {
                gHandStr = str;
                if (gIsHuman)
                    llRegionSayTo(gAvatarKey, listenChannel(), "HAND|" + str);
            }

        } else if (num == MSG_BID_REQUEST) {
            if ((integer)llList2String(llParseString2List(str, ["|"], []), 0) == gSeatID) {
                if (gIsHuman)
                    llRegionSayTo(gAvatarKey, listenChannel(), "BID_PROMPT|" + str);
                else
                    llMessageLinked(LINK_SET, MSG_BOT_BID_REQUEST, (string)gSeatID, NULL_KEY);
            }

        } else if (num == MSG_DUMMY_REVEAL) {
            // str = "dummySeat|c0|c1|..."
            // Declarer is dummy's partner: dummySeat ^ 1
            integer dummySeat = (integer)llList2String(
                llParseString2List(str, ["|"], []), 0);
            if (gIsHuman && gSeatID == (dummySeat ^ 1)) {
                llRegionSayTo(gAvatarKey, listenChannel(), "DUMMY_HAND|" + str);
            }

        } else if (num == MSG_PLAY_REQUEST) {
            list parts    = llParseString2List(str, ["|"], []);
            integer seat  = (integer)llList2String(parts, 0);
            integer forDummy = (integer)llList2String(parts, 1);
            if (seat == gSeatID) {
                if (gIsHuman) {
                    llRegionSayTo(gAvatarKey, listenChannel(),
                        "PLAY_PROMPT|" + (string)forDummy);
                } else {
                    string botStr = (string)gSeatID;
                    if (forDummy)
                        botStr += "|" + (string)(gSeatID ^ 1);
                    llMessageLinked(LINK_SET, MSG_BOT_PLAY_REQUEST, botStr, NULL_KEY);
                }
            }
        }
    }
}
