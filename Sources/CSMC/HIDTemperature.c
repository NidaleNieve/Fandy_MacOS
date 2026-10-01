#include "CSMC.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
// Independently authored optional adapter for the reverse-engineered userspace HID temperature interface.
// Filter only vendor temperature sensors (page 0xff00, usage 5); never request input-device events.
CFArrayRef fandy_hid_temperatures(void) {
    typedef CFTypeRef (*Create)(CFAllocatorRef);
    typedef CFArrayRef (*Services)(CFTypeRef);
    typedef CFTypeRef (*Property)(CFTypeRef,CFStringRef);
    typedef CFTypeRef (*Event)(CFTypeRef,int,int64_t,int);
    typedef double (*Value)(CFTypeRef,int);
    void *library=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY|RTLD_LOCAL);
    if (!library) return NULL;
    Create create=(Create)dlsym(library,"IOHIDEventSystemClientCreate");
    Services services=(Services)dlsym(library,"IOHIDEventSystemClientCopyServices");
    Property property=(Property)dlsym(library,"IOHIDServiceClientCopyProperty");
    Event event=(Event)dlsym(library,"IOHIDServiceClientCopyEvent");
    Value value=(Value)dlsym(library,"IOHIDEventGetFloatValue");
    CFMutableArrayRef result=CFArrayCreateMutable(NULL,0,&kCFTypeArrayCallBacks);
    if (!create||!services||!property||!event||!value) { dlclose(library); return result; }
    CFTypeRef client=create(NULL);
    if (!client) { dlclose(library); return result; }
    CFArrayRef list=services(client);
    if (list) for (CFIndex i=0;i<CFArrayGetCount(list);i++) {
        CFTypeRef service=CFArrayGetValueAtIndex(list,i);
        CFTypeRef page=property(service,CFSTR("PrimaryUsagePage")),usage=property(service,CFSTR("PrimaryUsage"));
        int p=0,u=0;
        if (page&&CFGetTypeID(page)==CFNumberGetTypeID()) CFNumberGetValue(page,kCFNumberIntType,&p);
        if (usage&&CFGetTypeID(usage)==CFNumberGetTypeID()) CFNumberGetValue(usage,kCFNumberIntType,&u);
        if(page)CFRelease(page);if(usage)CFRelease(usage);
        if(p!=0xff00||u!=5)continue;
        CFTypeRef sample=event(service,15,0,0),name=property(service,CFSTR("Product"));
        if(sample&&name&&CFGetTypeID(name)==CFStringGetTypeID()) {
            double degrees=value(sample,15<<16);
            if(isfinite(degrees)&&degrees>0&&degrees<150) {
                CFNumberRef number=CFNumberCreate(NULL,kCFNumberDoubleType,&degrees);
                const void *keys[]={CFSTR("name"),CFSTR("celsius")},*values[]={name,number};
                CFDictionaryRef record=CFDictionaryCreate(NULL,keys,values,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
                CFArrayAppendValue(result,record);CFRelease(record);CFRelease(number);
            }
        }
        if(sample)CFRelease(sample);if(name)CFRelease(name);
    }
    if(list)CFRelease(list);CFRelease(client);dlclose(library);return result;
}
