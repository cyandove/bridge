// dummy_debug.lsl
// Drop into the dummy_0 prim. Touch it to print its current local position
// and rotation to local chat -- use these values in the card_layout notecard.
//
// Workflow:
//   1. Deal a hand so card_display.lsl repositions dummy_0
//   2. Touch dummy_0 -- values appear in local chat
//   3. Copy <seat>_base and <seat>_rot into card_layout
//   4. For <seat>_spread: measure the gap you want between cards (card width
//      + a small margin), set that distance along the same axis as the base
//      position offset from centre.  e.g. if cards fan along X, use <0.13,0,0>

default {
    touch_start(integer total) {
        vector   pos = llGetLocalPos();
        rotation rot = llGetLocalRot();
        llSay(0, "dummy_0 -- link " + (string)llGetLinkNumber()
            + "\n  local pos: " + (string)pos
            + "\n  local rot: " + (string)rot
            + "\nPaste into card_layout:"
            + "\n  <seat>_base="   + (string)pos
            + "\n  <seat>_rot="    + (string)rot);
    }
}
