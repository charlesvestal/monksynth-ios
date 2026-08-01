/* Fixed parity script. Times are in samples at 44100 Hz.
 * Kind: 0=param set (normalized), 1=note on, 2=note off, 3=xy note on,
 *       4=xy note off, 5=xy pitch, 6=xy vowel.
 *
 * IMPORTANT — event timing is quantized to PARITY_BLOCK (512 samples).
 * The dispatch loop in render_golden.c only checks pending events at block
 * boundaries (pos = 0, 512, 1024, ...), so an event scripted at `at` fires
 * on the first boundary >= `at`, not at the sample-accurate `at` itself
 * (e.g. the note-on scripted at 4410 actually fires at 4608). Any replay
 * of this script (e.g. Task 6's Swift port) must process audio in the
 * same 512-sample blocks or its output will diverge from this golden for
 * reasons unrelated to the parameter mapping. */
#ifndef PARITY_SCRIPT_H
#define PARITY_SCRIPT_H

typedef struct { int at; int kind; int index; float value; } ParityEvent;

#define PARITY_SR        44100
#define PARITY_FRAMES    176400        /* 4 seconds */
#define PARITY_BLOCK     512

/* Must stay sorted by `at` in non-decreasing order — the dispatch loop
 * walks this table with a single forward-only pointer (see render_golden.c),
 * so an out-of-order edit would silently fire an event at the wrong time
 * instead of failing loudly. */
static const ParityEvent kParityScript[] = {
    {     0, 0,  0, 0.25f},   /* portTime          */
    {     0, 0,  2, 0.60f},   /* delay             */
    {     0, 0,  3, 0.70f},   /* headSize          */
    {     0, 0,  4, 0.35f},   /* vibrato           */
    {     0, 0,  5, 0.80f},   /* vibratoRate       */
    {     0, 0,  6, 0.20f},   /* aspiration        */
    {     0, 0,  7, 0.10f},   /* attack  -> 0.5 s  */
    {     0, 0,  8, 0.30f},   /* decay   -> 1.5 s  */
    {     0, 0,  9, 0.70f},   /* sustain           */
    {     0, 0, 10, 0.40f},   /* release -> 2.0 s  */
    {     0, 0, 11, 0.55f},   /* unison  -> 6      */
    {     0, 0, 12, 0.40f},   /* detune  -> 20 ct  */
    {     0, 0, 13, 0.65f},   /* delayRate         */
    {     0, 0, 14, 0.90f},   /* level             */
    {     0, 0, 15, 0.50f},   /* voiceSpread       */
    {  4410, 1, 60, 0.80f},   /* note on  C4       */
    { 22050, 0, 19, 0.75f},   /* pitchBend +6 st   */
    { 30870, 0,  1, 0.20f},   /* vowel             */
    { 44100, 2, 60, 0.00f},   /* note off          */
    { 61740, 5,  0, 0.30f},   /* xy pitch          */
    { 61740, 3,  0, 1.00f},   /* xy note on        */
    { 79380, 6,  0, 0.85f},   /* xy vowel          */
    { 96030, 5,  0, 0.75f},   /* xy pitch glide    */
    {114660, 4,  0, 0.00f},   /* xy note off       */
    {132300, 0, 19, 0.50f},   /* pitchBend back    */
};
#define PARITY_EVENT_COUNT (int)(sizeof(kParityScript) / sizeof(kParityScript[0]))

#endif
