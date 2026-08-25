/* HelionBridge — original iOS glue. Not MeloNX. */
#include <stdint.h>
#include <string.h>
#include <stdio.h>

void TriggerCallback(const char *id) {
    if (id) fprintf(stderr, "[helion] cb %s\n", id);
}
void TriggerCallbackWithData(const char *id, const void *data, uintptr_t len) {
    (void)data; (void)len;
    if (id) fprintf(stderr, "[helion] cb-data %s %lu\n", id, (unsigned long)len);
}
void showKeyboardAlert(const char *t, const char *m, const char *p) {
    (void)t; (void)m; (void)p;
}
void showAlert(const char *t, const char *m, int cancel) {
    (void)t; (void)m; (void)cancel;
}
const char *getKeyboardInput(void) { return ""; }
void clearKeyboardInput(void) {}
