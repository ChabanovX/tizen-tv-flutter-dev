#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dlfcn.h>

/* DRM_IOCTL_SET_CLIENT_CAP = _IOW('d', 0x0d, struct drm_set_client_cap)
 * struct drm_set_client_cap { __u64 capability; __u64 value; }; */
struct drm_set_client_cap {
    unsigned long long capability;
    unsigned long long value;
};
#define DRM_CLIENT_CAP_UNIVERSAL_PLANES 2ULL
#define DRM_IOCTL_SET_CLIENT_CAP 0x4010640d

/* drmModeGetPlaneResources is a libdrm function. We intercept it. */
typedef struct drmModePlaneRes *drmModePlaneResPtr;

drmModePlaneResPtr drmModeGetPlaneResources(int fd) {
    static drmModePlaneResPtr (*real)(int) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "drmModeGetPlaneResources");

    struct drm_set_client_cap cap = {DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1};
    int rc = ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &cap);
    /* Best-effort log to stderr (won't crash if not connected) */
    fprintf(stderr, "[shim] SET_CLIENT_CAP(UNIVERSAL_PLANES) on fd=%d rc=%d errno=%d\n", fd, rc, rc<0?errno:0);
    drmModePlaneResPtr r = real(fd);
    if (r) {
        unsigned *count = (unsigned*)r;  /* struct starts with count_planes (u32) */
        fprintf(stderr, "[shim] drmModeGetPlaneResources(%d) -> %p count=%u\n", fd, r, *count);
    }
    return r;
}
