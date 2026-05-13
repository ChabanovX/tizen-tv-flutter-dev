#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <string.h>
#include <errno.h>

// Emulates Lwipc's "EventDone" ioctl + file creation.
// Based on RE of liblwipc.so: ioctl number 0x40409603 on /dev/lwipc
// Pass null-terminated path string as buffer.

static void event_done(const char *name) {
    char buf[64] = {0};
    strncpy(buf, name, 63);

    int fd = open("/dev/lwipc", O_WRONLY);
    if (fd < 0) {
        fprintf(stderr, "open /dev/lwipc: %s\n", strerror(errno));
    } else {
        int r = ioctl(fd, 0x40409603, buf);
        fprintf(stderr, "ioctl(%s) = %d\n", name, r);
        close(fd);
    }
    // also create the file (mode 0644)
    int cf = creat(name, 0644);
    if (cf < 0) {
        fprintf(stderr, "creat %s: %s\n", name, strerror(errno));
    } else {
        close(cf);
        fprintf(stderr, "creat(%s) ok\n", name);
    }
}

int main(void) {
    const char *events[] = {
        "/run/.wm_ready",
        "/run/wm_start",
        "/tmp/wm_start",
        "/tmp/.wm_ready",
        "/tmp/.screen_manager_ready",
        "/tmp/app_ready",
        "/run/systemd/system/default.target.done",
        NULL,
    };
    for (int i = 0; events[i]; i++) event_done(events[i]);
    fflush(stderr);

    // also try opening fb0 + filling magenta to show we got past the events
    int fd = open("/dev/fb0", O_RDWR);
    if (fd >= 0) {
        unsigned char row[1920*4];
        for (int i = 0; i < 1920; i++) {
            row[i*4] = 0xFF; row[i*4+1] = 0; row[i*4+2] = 0xFF; row[i*4+3] = 0;
        }
        lseek(fd, 0, SEEK_SET);
        for (int y = 0; y < 1080; y++) write(fd, row, sizeof(row));
        close(fd);
    }
    sleep(99999);
    return 0;
}
