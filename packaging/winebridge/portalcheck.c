#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <libusb.h>

static int find_devnode(unsigned vid, unsigned pid, char *out, size_t n) {
    DIR *d = opendir("/sys/bus/usb/devices");
    struct dirent *e;
    char p[512]; char buf[32];
    while (d && (e = readdir(d))) {
        unsigned v=0, pr=0, bus=0, dev=0; FILE *f;
        snprintf(p, sizeof p, "/sys/bus/usb/devices/%s/idVendor", e->d_name);
        if (!(f = fopen(p, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) v = strtoul(buf, 0, 16); fclose(f);
        snprintf(p, sizeof p, "/sys/bus/usb/devices/%s/idProduct", e->d_name);
        if (!(f = fopen(p, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) pr = strtoul(buf, 0, 16); fclose(f);
        if (v != vid || pr != pid) continue;
        snprintf(p, sizeof p, "/sys/bus/usb/devices/%s/busnum", e->d_name);
        if (!(f = fopen(p, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) bus = strtoul(buf, 0, 10); fclose(f);
        snprintf(p, sizeof p, "/sys/bus/usb/devices/%s/devnum", e->d_name);
        if (!(f = fopen(p, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) dev = strtoul(buf, 0, 10); fclose(f);
        snprintf(out, n, "/dev/bus/usb/%03u/%03u", bus, dev);
        closedir(d);
        return 0;
    }
    if (d) closedir(d);
    return -1;
}

int main(int argc, char **argv) {
    int mode = argc > 1 ? atoi(argv[1]) : 0;
    libusb_context *ctx = NULL;
    if (mode == 1) {
        libusb_set_option(NULL, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
        printf("[mode 1] NO_DEVICE_DISCOVERY + wrap_sys_device\n");
    } else {
        printf("[mode 0] normal enumeration open_device_with_vid_pid\n");
    }
    int r = libusb_init(&ctx);
    printf("init -> %d\n", r);
    if (r) return 1;
    libusb_device_handle *h = NULL;
    if (mode == 1) {
        char node[64];
        if (find_devnode(0x0e4c, 0x7288, node, sizeof node)) { printf("no sysfs match\n"); return 1; }
        printf("devnode: %s\n", node);
        int fd = open(node, O_RDWR);
        if (fd < 0) { perror("open(node, O_RDWR)"); return 1; }
        r = libusb_wrap_sys_device(ctx, (intptr_t)fd, &h);
        printf("wrap_sys_device -> %d (%s)\n", r, r ? libusb_error_name(r) : "OK");
    } else {
        h = libusb_open_device_with_vid_pid(ctx, 0x0e4c, 0x7288);
        printf("open_device_with_vid_pid -> %p\n", (void *)h);
    }
    if (h) {
        r = libusb_claim_interface(h, 0);
        printf("claim -> %d\n", r);
        unsigned char b[8]; int tr = 0;
        r = libusb_interrupt_transfer(h, 0x81, b, 8, &tr, 1500);
        printf("interrupt read -> %d, %d bytes\n", r, tr);
        libusb_release_interface(h, 0);
        libusb_close(h);
    }
    libusb_exit(ctx);
    printf("clean exit\n");
    return 0;
}
