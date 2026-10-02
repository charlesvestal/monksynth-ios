// Parameter addresses, shared by the C shadow array and Swift.
// Order and values MUST match upstream cpp/src/plugin_cids.h for every address
// upstream defines; MonkSynth's own additions are appended after them.
#ifndef PARAMETER_ADDRESSES_H
#define PARAMETER_ADDRESSES_H

#include <stdint.h>

typedef enum {
    kParamPortTime          = 0,
    kParamVowel             = 1,
    kParamDelay             = 2,
    kParamHeadSize          = 3,
    kParamVibrato           = 4,
    kParamVibratoRate       = 5,
    kParamAspiration        = 6,
    kParamAttack            = 7,
    kParamDecay             = 8,
    kParamSustain           = 9,
    kParamRelease           = 10,
    kParamUnison            = 11,
    kParamUnisonDetune      = 12,
    kParamDelayRate         = 13,
    kParamLevel             = 14,
    kParamUnisonVoiceSpread = 15,
    kParamXYNoteOn          = 16,
    kParamXYVowel           = 17,
    kParamXYPitchTarget     = 18,
    kParamPitchBend         = 19,
    kParamPitchBendRouting  = 20,
    kParamPitchWheelRaw     = 21,
    // MonkSynth-only additions go after upstream's, so its addresses never move.
    kParamPitchSnap         = 22,
    kParamCount             = 23
} ParameterAddress;

#endif
