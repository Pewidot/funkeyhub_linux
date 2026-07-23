
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <libusb.h>

static libusb_context *g_ctx;
static int g_refs;

static int dbg_enabled(void)
{
    static int cached = -1;
    if (cached < 0) {
        const char *e = getenv("FUNKEY_BRIDGE_DEBUG");
        cached = (e && *e && *e != '0') ? 1 : 0;
    }
    return cached;
}

#define TRACE(...) do { if (dbg_enabled()) { \
    fprintf(stderr, "[usb-bridge] " __VA_ARGS__); fputc('\n', stderr); } } while (0)

static int ensure_ctx(void)
{
    if (g_ctx) return 0;

    libusb_set_option(NULL, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
    int r = libusb_init(&g_ctx);
    if (r != 0) g_ctx = NULL;
    return r;
}

int ub_init(void)
{
    int r = ensure_ctx();
    if (r == 0) g_refs++;
    TRACE("init -> %d (refs=%d)", r, g_refs);
    return r;
}

void ub_exit(void)
{
    TRACE("exit (refs=%d)", g_refs);
    if (g_refs > 0 && --g_refs == 0 && g_ctx) {
        libusb_exit(g_ctx);
        g_ctx = NULL;
    }
}

static int find_devnode(unsigned vid, unsigned pid, char *out, size_t n)
{
    DIR *d = opendir("/sys/bus/usb/devices");
    struct dirent *e;
    char path[512], buf[32];
    int found = -1;

    while (d && (e = readdir(d))) {
        unsigned v = 0, p = 0, bus = 0, dev = 0;
        FILE *f;
        snprintf(path, sizeof path, "/sys/bus/usb/devices/%s/idVendor", e->d_name);
        if (!(f = fopen(path, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) v = strtoul(buf, NULL, 16);
        fclose(f);
        if (v != vid) continue;
        snprintf(path, sizeof path, "/sys/bus/usb/devices/%s/idProduct", e->d_name);
        if (!(f = fopen(path, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) p = strtoul(buf, NULL, 16);
        fclose(f);
        if (p != pid) continue;
        snprintf(path, sizeof path, "/sys/bus/usb/devices/%s/busnum", e->d_name);
        if (!(f = fopen(path, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) bus = strtoul(buf, NULL, 10);
        fclose(f);
        snprintf(path, sizeof path, "/sys/bus/usb/devices/%s/devnum", e->d_name);
        if (!(f = fopen(path, "r"))) continue;
        if (fgets(buf, sizeof buf, f)) dev = strtoul(buf, NULL, 10);
        fclose(f);
        snprintf(out, n, "/dev/bus/usb/%03u/%03u", bus, dev);
        found = 0;
        break;
    }
    if (d) closedir(d);
    return found;
}

#define MAX_OPEN 8
static struct { void *h; int fd; } g_open[MAX_OPEN];

void *ub_open(unsigned vid, unsigned pid)
{
    if (ensure_ctx() != 0) return NULL;

    char node[64];
    if (find_devnode(vid, pid, node, sizeof node) != 0) {
        TRACE("open %04x:%04x -> not present (sysfs)", vid, pid);
        return NULL;
    }
    int fd = open(node, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        TRACE("open %04x:%04x -> %s: %s%s", vid, pid, node, strerror(errno),
              errno == EACCES ? "  (install the udev rule!)" : "");
        return NULL;
    }
    libusb_device_handle *h = NULL;
    int r = libusb_wrap_sys_device(g_ctx, (intptr_t)fd, &h);
    if (r != 0 || !h) {
        TRACE("open %04x:%04x -> wrap_sys_device failed: %s",
              vid, pid, libusb_error_name(r));
        close(fd);
        return NULL;
    }
    for (int i = 0; i < MAX_OPEN; i++) {
        if (!g_open[i].h) { g_open[i].h = h; g_open[i].fd = fd; break; }
    }
    TRACE("open %04x:%04x -> %p via %s", vid, pid, (void *)h, node);
    return h;
}

void ub_close(void *h)
{
    TRACE("close %p", h);
    if (!h) return;
    libusb_close(h);
    for (int i = 0; i < MAX_OPEN; i++) {
        if (g_open[i].h == h) {
            close(g_open[i].fd);
            g_open[i].h = NULL;
            g_open[i].fd = -1;
            break;
        }
    }
}

int ub_claim_interface(void *h, int iface)
{
    int r = libusb_claim_interface(h, iface);
    TRACE("claim_interface %d -> %d", iface, r);
    return r;
}

int ub_release_interface(void *h, int iface)
{
    int r = libusb_release_interface(h, iface);
    TRACE("release_interface %d -> %d", iface, r);
    return r;
}

int ub_kernel_driver_active(void *h, int iface)
{
    int r = libusb_kernel_driver_active(h, iface);
    TRACE("kernel_driver_active %d -> %d", iface, r);
    return r;
}

int ub_detach_kernel_driver(void *h, int iface)
{
    int r = libusb_detach_kernel_driver(h, iface);
    TRACE("detach_kernel_driver %d -> %d", iface, r);

    return (r == LIBUSB_ERROR_NOT_FOUND) ? 0 : r;
}

int ub_control_transfer(void *h, unsigned char bmRequestType,
    unsigned char bRequest, unsigned short wValue, unsigned short wIndex,
    unsigned char *data, unsigned short wLength, unsigned int timeout)
{
    int r = libusb_control_transfer(h, bmRequestType, bRequest, wValue,
                                    wIndex, data, wLength, timeout);
    TRACE("control_transfer type=%02x req=%02x len=%u -> %d",
          bmRequestType, bRequest, wLength, r);
    return r;
}

int ub_interrupt_transfer(void *h, unsigned char endpoint,
    unsigned char *data, int length, int *transferred, unsigned int timeout)
{
    int r = libusb_interrupt_transfer(h, endpoint, data, length,
                                      transferred, timeout);

    if (r != 0 && r != LIBUSB_ERROR_TIMEOUT)
        TRACE("interrupt_transfer ep=%02x len=%d -> %d", endpoint, length, r);
    return r;
}

const char *ub_error_name(int code)
{
    return libusb_error_name(code);
}
