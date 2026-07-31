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

#endif
