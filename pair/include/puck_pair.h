#ifndef PUCK_PAIR_H
#define PUCK_PAIR_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*PuckPairReadyCb)(void *ctx,
                                const char *service_id,
                                uint16_t port,
                                const char *const *txt_keys,
                                const char *const *txt_vals,
                                size_t txt_count);

typedef void (*PuckPairPinCb)(const char *pin, void *ctx);

typedef void (*PuckPairDoneCb)(int32_t ok,
                               const char *error,
                               const char *path,
                               const char *device_name,
                               const char *device_udid,
                               const char *irk_hex,
                               void *ctx);

int32_t puck_pair_run(const char *bind_addr,
                      uint16_t port,
                      const char *name,
                      const char *model,
                      const char *out_path,
                      PuckPairReadyCb ready_cb,
                      PuckPairPinCb pin_cb,
                      PuckPairDoneCb done_cb,
                      void *ctx);

#ifdef __cplusplus
}
#endif

#endif
