// Lock-free parameter snapshot. The render thread reads only from here — it
// must never touch AUParameter, which is not realtime-safe.
#ifndef PARAMETER_SHADOW_H
#define PARAMETER_SHADOW_H

#include "ParameterAddresses.h"

typedef struct ParamShadow ParamShadow;

ParamShadow *param_shadow_new(void);
void  param_shadow_free(ParamShadow *s);
void  param_shadow_set(ParamShadow *s, ParameterAddress a, float v);
float param_shadow_get(const ParamShadow *s, ParameterAddress a);

// A one-shot "release every MIDI note" request, set from any thread (a host's
// reset()) and taken by the render thread before its next block.
void param_shadow_request_all_notes_off(ParamShadow *s);
int  param_shadow_take_all_notes_off(ParamShadow *s);

// A value MIDI wrote on the render thread (a CC, the pitch wheel). Marks the
// address so the main thread can report it to the host as a parameter change
// — which is what lets a host record CC moves as automation.
void param_shadow_set_from_midi(ParamShadow *s, ParameterAddress a, float v);
// 1 if MIDI changed `a` since the last call (and clears the mark).
int  param_shadow_take_midi_change(ParamShadow *s, ParameterAddress a);

#endif
