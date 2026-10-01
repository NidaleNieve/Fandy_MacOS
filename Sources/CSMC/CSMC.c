#include "CSMC.h"
#include <IOKit/IOKitLib.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach.h>
struct FandySMC { io_connect_t port; };
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } Limits;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct { uint32_t key; Version version; Limits limits; KeyInfo info; uint8_t result, status, command; uint32_t index; uint8_t bytes[32]; } Parameters;
_Static_assert(sizeof(Parameters) == 80, "SMC ABI size");
_Static_assert(offsetof(Parameters, info) == 28, "SMC key info offset");
_Static_assert(offsetof(Parameters, result) == 40, "SMC result offset");
_Static_assert(offsetof(Parameters, command) == 42, "SMC command offset");
_Static_assert(offsetof(Parameters, bytes) == 48, "SMC bytes offset");
static int32_t call(FandySMC *c, Parameters *in, Parameters *out) {
    if (!c || !in || !out) return kIOReturnBadArgument;
    memset(out, 0, sizeof(*out)); size_t size = sizeof(*out);
    kern_return_t result = IOConnectCallStructMethod(c->port, 2, in, sizeof(*in), out, &size);
    if (result != KERN_SUCCESS) return result;
    if (size != sizeof(*out)) return kIOReturnUnderrun;
    return out->result == 0 ? 0 : (int32_t)(0xFAD00000u | out->result);
}
FandySMC *fandy_smc_open(int32_t *error) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) { if(error) *error = kIOReturnNotFound; return NULL; }
    io_connect_t port = 0; kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &port); IOObjectRelease(service);
    if (error) *error = r;
    if (r != KERN_SUCCESS) return NULL;
    FandySMC *c = calloc(1, sizeof(*c));
    if (!c) { IOServiceClose(port); if(error) *error = kIOReturnNoMemory; return NULL; }
    c->port = port; return c;
}
void fandy_smc_close(FandySMC *c) { if(c) { IOServiceClose(c->port); free(c); } }
int32_t fandy_smc_read(FandySMC *c, const char *key, FandySMCValue *value) {
    if (!key || strlen(key) != 4 || !value) return kIOReturnBadArgument;
    Parameters in = {0}, out = {0}; memset(value, 0, sizeof(*value));
    for(int i=0;i<4;i++) in.key = (in.key<<8) | (uint8_t)key[i];
    in.command = 9; int32_t r = call(c,&in,&out); if(r) return r;
    if(out.info.size == 0 || out.info.size > 32) return kIOReturnUnsupported;
    value->size = out.info.size; value->attributes = out.info.attributes;
    for(int i=0;i<4;i++) value->type[i]=(char)(out.info.type >> (24-i*8));
    in.info.size=out.info.size; in.command=5;
    r=call(c,&in,&out); if(r) return r;
    memcpy(value->bytes, out.bytes, value->size); return 0;
}
int32_t fandy_smc_key_at(FandySMC *c, uint32_t index, char key[5]) {
    Parameters in={0}, out={0}; in.command=8; in.index=index;
    int32_t r=call(c,&in,&out); if(r) return r;
    for(int i=0;i<4;i++) key[i]=(char)(out.key >> (24-i*8)); key[4]=0; return 0;
}
