#pragma once
#include <stdint.h>
#include <stddef.h>
// Independently authored ABI adapter. No fan-write function is exposed here.
typedef struct FandySMC FandySMC;
typedef struct { uint32_t size; char type[5]; uint8_t attributes; uint8_t bytes[32]; } FandySMCValue;
FandySMC *fandy_smc_open(int32_t *error);
void fandy_smc_close(FandySMC *connection);
int32_t fandy_smc_read(FandySMC *connection, const char *key, FandySMCValue *value);
int32_t fandy_smc_key_at(FandySMC *connection, uint32_t index, char key[5]);
// Caller owns the returned array. Missing APIs return an empty array or NULL.
#include <CoreFoundation/CoreFoundation.h>
CFArrayRef fandy_hid_temperatures(void) CF_RETURNS_RETAINED;

// Fixed known-controller check; no caller-supplied PID/path or process data is returned.
// 1 = TG Pro helper detected; 0 = not observed; -1 = enumeration unavailable.
int32_t fandy_tg_controller_present(void);
