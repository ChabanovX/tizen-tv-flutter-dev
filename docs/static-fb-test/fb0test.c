#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    int fd = open("/dev/fb0", O_RDWR);
    if (fd < 0) { perror("open"); sleep(99); return 1; }
    struct fb_var_screeninfo vinfo;
    ioctl(fd, FBIOGET_VSCREENINFO, &vinfo);
    printf("MAGENTA fb0 %dx%d@%dbpp xv=%d yv=%d\n",
           vinfo.xres, vinfo.yres, vinfo.bits_per_pixel,
           vinfo.xres_virtual, vinfo.yres_virtual);
    fflush(stdout);

    uint32_t color = 0x00FF00FF;
    if (argc > 1) color = strtoul(argv[1], NULL, 16);

    // Allocate a row of max-likely size
    static uint32_t row[4096];
    for (int i = 0; i < 4096; i++) row[i] = color;

    int w = vinfo.xres_virtual ? vinfo.xres_virtual : vinfo.xres;
    int h = vinfo.yres_virtual ? vinfo.yres_virtual : vinfo.yres;
    if (w > 4096) w = 4096;
    lseek(fd, 0, SEEK_SET);
    long total = 0;
    for (int y = 0; y < h; y++) {
        ssize_t n = write(fd, row, w * 4);
        if (n < 0) break;
        total += n;
    }
    printf("MAGENTA wrote %ld bytes (%dx%d)\n", total, w, h);
    fflush(stdout);
    sleep(99999);
    return 0;
}
