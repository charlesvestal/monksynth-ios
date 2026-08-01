#include "ParameterShadow.h"
#include <stdatomic.h>
#include <stdlib.h>

struct ParamShadow { _Atomic float values[kParamCount]; };

ParamShadow *param_shadow_new(void) {
    ParamShadow *s = calloc(1, sizeof(ParamShadow));
    return s;
}

void param_shadow_free(ParamShadow *s) { free(s); }

void param_shadow_set(ParamShadow *s, ParameterAddress a, float v) {
    if (!s || a < 0 || a >= kParamCount) return;
    atomic_store_explicit(&s->values[a], v, memory_order_relaxed);
}

float param_shadow_get(const ParamShadow *s, ParameterAddress a) {
    if (!s || a < 0 || a >= kParamCount) return 0.0f;
    return atomic_load_explicit(&s->values[a], memory_order_relaxed);
}
