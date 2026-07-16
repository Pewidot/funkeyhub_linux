/*
 * Windows-facing half of the Wine libusb bridge — compiled with winegcc,
 * which uses -mabi=ms for everything in this translation unit. Therefore
 * this file must NOT call any host library directly (the calls would be
 * emitted with Windows registers against SysV code). It only translates
 * the libusb-1.0.dll exports that MegaByte.exe (the OpenFK portal reader)
 * P/Invokes into calls to the ub_* functions in bridge_unix.c, which is
 * compiled by plain gcc; the sysv_abi attribute below makes the cross-object
 * calls use the correct convention.
 *
 * Why this exists: on real Windows these exports are backed by the libusbK
 * kernel driver installed by MegaByteHubInstaller.exe, which cannot work
 * under Wine. Here they end up in the host's libusb-1.0.so instead, which
 * talks to the portal (0e4c:7288) directly — no kernel driver on either side.
 */
#define SYSV __attribute__((sysv_abi))
#define MSABI __attribute__((ms_abi))

extern SYSV int ub_init(void);
extern SYSV void ub_exit(void);
extern SYSV void *ub_open(unsigned vid, unsigned pid);
extern SYSV void ub_close(void *h);
extern SYSV int ub_claim_interface(void *h, int iface);
extern SYSV int ub_release_interface(void *h, int iface);
extern SYSV int ub_kernel_driver_active(void *h, int iface);
extern SYSV int ub_detach_kernel_driver(void *h, int iface);
extern SYSV int ub_control_transfer(void *h, unsigned char bmRequestType,
    unsigned char bRequest, unsigned short wValue, unsigned short wIndex,
    unsigned char *data, unsigned short wLength, unsigned int timeout);
extern SYSV int ub_interrupt_transfer(void *h, unsigned char endpoint,
    unsigned char *data, int length, int *transferred, unsigned int timeout);
extern SYSV const char *ub_error_name(int code);

MSABI int wrap_libusb_init(void **ctx)
{
    int r = ub_init();
    /* the app never dereferences the context, it only passes it around;
     * hand back a non-NULL cookie so truthiness checks pass */
    if (r == 0 && ctx) *ctx = (void *)1;
    return r;
}

MSABI void wrap_libusb_exit(void *ctx)
{
    (void)ctx;
    ub_exit();
}

MSABI void *wrap_libusb_open_device_with_vid_pid(void *ctx,
    unsigned short vid, unsigned short pid)
{
    (void)ctx;                    /* app passes NULL here — ignored */
    return ub_open(vid, pid);
}

MSABI void wrap_libusb_close(void *h)
{
    ub_close(h);
}

MSABI int wrap_libusb_claim_interface(void *h, int iface)
{
    return ub_claim_interface(h, iface);
}

MSABI int wrap_libusb_release_interface(void *h, int iface)
{
    return ub_release_interface(h, iface);
}

MSABI int wrap_libusb_kernel_driver_active(void *h, int iface)
{
    return ub_kernel_driver_active(h, iface);
}

MSABI int wrap_libusb_detach_kernel_driver(void *h, int iface)
{
    return ub_detach_kernel_driver(h, iface);
}

MSABI int wrap_libusb_control_transfer(void *h, unsigned char bmRequestType,
    unsigned char bRequest, unsigned short wValue, unsigned short wIndex,
    unsigned char *data, unsigned short wLength, unsigned int timeout)
{
    return ub_control_transfer(h, bmRequestType, bRequest, wValue, wIndex,
                               data, wLength, timeout);
}

MSABI int wrap_libusb_interrupt_transfer(void *h, unsigned char endpoint,
    unsigned char *data, int length, int *transferred, unsigned int timeout)
{
    return ub_interrupt_transfer(h, endpoint, data, length, transferred,
                                 timeout);
}

MSABI const char *wrap_libusb_error_name(int code)
{
    return ub_error_name(code);
}
