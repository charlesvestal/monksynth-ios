#include "script.h"
#include "synth.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int   xy_active  = 0;
static float xy_pending = 0.5f;
static int   midi_notes = 0;

static float xy_hz(float v) { return 130.81f * powf(2.0f, v); }

static void apply_param(MonkSynthEngine *s, int i, float v) {
    switch (i) {
    case  0: monk_synth_set_glide(s, v); break;
    case  1: monk_synth_set_vowel(s, v); break;
    case  2: monk_synth_set_delay_mix(s, v); break;
    case  3: monk_synth_set_voice(s, v); break;
    case  4: monk_synth_set_vibrato(s, v); break;
    case  5: monk_synth_set_vibrato_rate(s, v); break;
    case  6: monk_synth_set_aspiration(s, v); break;
    case  7: monk_synth_set_attack(s, v * 5.0f); break;
    case  8: monk_synth_set_decay(s, v * 5.0f); break;
    case  9: monk_synth_set_sustain(s, v); break;
    case 10: monk_synth_set_release(s, v * 5.0f); break;
    case 11: monk_synth_set_unison(s, (int)(v * 9.0f + 1.5f)); break;
    case 12: monk_synth_set_unison_detune(s, v * 50.0f); break;
    case 13: monk_synth_set_delay_rate(s, v); break;
    case 14: monk_synth_set_level(s, v); break;
    case 15: monk_synth_set_unison_voice_spread(s, v * 0.5f); break;
    case 19: monk_synth_set_pitch_bend(s, (v - 0.5f) * 24.0f); break;
    default: break;
    }
}

static void apply_event(MonkSynthEngine *s, const ParityEvent *e) {
    switch (e->kind) {
    case 0: apply_param(s, e->index, e->value); break;
    case 1: monk_synth_note_on(s, (uint8_t)e->index, e->value); midi_notes++; break;
    case 2:
        if (midi_notes > 0) midi_notes--;
        monk_synth_note_off(s, (uint8_t)e->index);
        if (xy_active && midi_notes == 0)
            monk_synth_set_pitch_hz(s, xy_hz(xy_pending));
        break;
    case 3: xy_active = 1; monk_synth_set_pitch_hz(s, xy_hz(xy_pending)); break;
    case 4:
        xy_active = 0;
        if (midi_notes > 0) monk_synth_restore_note_stack(s);
        else                monk_synth_note_off(s, 60);
        break;
    case 5:
        xy_pending = e->value;
        if (xy_active) monk_synth_set_pitch_hz(s, xy_hz(e->value));
        break;
    case 6: monk_synth_set_vowel(s, e->value); break;
    default: break;
    }
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "Tests/ParityHarness/golden_44k.f32";
    MonkSynthEngine *s = monk_synth_new((float)PARITY_SR);
    float *out = calloc((size_t)PARITY_FRAMES * 2, sizeof(float));
    if (!out) { perror("calloc"); monk_synth_free(s); return 1; }
    float l[PARITY_BLOCK], r[PARITY_BLOCK];
    int next = 0;

    /* Events are only checked at block boundaries (pos = 0, 512, 1024, ...),
     * so an event scripted at `at` actually fires on the first boundary
     * >= `at` — i.e. `at` rounds UP to the next multiple of PARITY_BLOCK.
     * See the note in script.h; any replay of this script must use the
     * same block size to stay bit-identical. */
    for (int pos = 0; pos < PARITY_FRAMES; pos += PARITY_BLOCK) {
        while (next < PARITY_EVENT_COUNT && kParityScript[next].at <= pos)
            apply_event(s, &kParityScript[next++]);

        int n = PARITY_FRAMES - pos < PARITY_BLOCK ? PARITY_FRAMES - pos : PARITY_BLOCK;
        monk_synth_process(s, l, r, (uint32_t)n);
        for (int i = 0; i < n; i++) {
            out[(size_t)(pos + i) * 2]     = l[i];
            out[(size_t)(pos + i) * 2 + 1] = r[i];
        }
    }

    /* Write to a temp file in the same directory as `path`, then rename()
     * into place only once the write and close both succeed. rename() on
     * the same filesystem is atomic, so a failed/partial render can never
     * leave a truncated file sitting at `path` — a caller either sees the
     * old (or no) file, or the fully-written new one, never a broken one. */
    char tmp_path[4096];
    int tmp_len = snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path);
    if (tmp_len < 0 || (size_t)tmp_len >= sizeof(tmp_path)) {
        fprintf(stderr, "error: path too long: %s\n", path);
        free(out);
        monk_synth_free(s);
        return 1;
    }

    FILE *f = fopen(tmp_path, "wb");
    if (!f) { perror("fopen"); free(out); monk_synth_free(s); return 1; }

    size_t written = fwrite(out, sizeof(float), (size_t)PARITY_FRAMES * 2, f);
    if (written != (size_t)PARITY_FRAMES * 2) {
        perror("fwrite");
        fclose(f);
        remove(tmp_path);
        free(out);
        monk_synth_free(s);
        return 1;
    }
    if (fclose(f) != 0) {
        perror("fclose");
        remove(tmp_path);
        free(out);
        monk_synth_free(s);
        return 1;
    }
    if (rename(tmp_path, path) != 0) {
        perror("rename");
        remove(tmp_path);
        free(out);
        monk_synth_free(s);
        return 1;
    }

    free(out);
    monk_synth_free(s);
    printf("wrote %d samples to %s\n", PARITY_FRAMES * 2, path);
    return 0;
}
