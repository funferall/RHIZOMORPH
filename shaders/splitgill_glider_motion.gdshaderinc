// Written by tools/unimate/glider_motion.py from UniMate clips. Do not edit by hand.
const int BONE_COUNT = 14;
const float CLIP_FPS = 30.0;
// one flight loop is one stride: at gait g (rad/s) it plays at g / GAIT_REF of its own speed
const float GAIT_REF = 10.4720;
const int GLIDE_START = 0;
const int GLIDE_LEN = 40;
const int FLY_START = 40;
const int FLY_LEN = 18;
const int RUN_START = 58;
const int RUN_LEN = 60;
const float RELEASE = 0.5932;   // the bomb run lets go of its bombs here (fraction of the swing)
const float SWING_SECONDS = 1.20;
const int BOMB_BONE = 1;
// chains: 0 body (by vertex x), 1 tail streamer, 2 left wing, 3 right wing (by data-UV weight)
const int CHAIN_LEN[4] = {6, 3, 4, 4};
const int CHAIN_BONE[32] = {2, 0, 1, 3, 7, 11, 11, 11, 2, 4, 8, 8, 8, 8, 8, 8, 3, 6, 10, 13, 13, 13, 13, 13, 3, 5, 9, 12, 12, 12, 12, 12};
const float CHAIN_C[32] = {-0.4000, -0.1900, 0.0100, 0.1900, 0.3400, 0.4700, 0.4700, 0.4700, -0.2500, 0.2200, 0.7200, 0.7200, 0.7200, 0.7200, 0.7200, 0.7200, -0.1200, 0.1650, 0.5000, 0.8300, 0.8300, 0.8300, 0.8300, 0.8300, -0.1200, 0.1650, 0.5000, 0.8300, 0.8300, 0.8300, 0.8300, 0.8300};
const vec3 BOMB_CENTRE[4] = {vec3(0.1000, 1.0400, 0.0700), vec3(-0.0600, 1.0000, -0.0600), vec3(-0.2000, 1.0700, 0.0500), vec3(0.0200, 0.9200, 0.0000)};
