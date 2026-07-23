
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>

enum { OP_INIT=1, OP_EXIT, OP_OPEN, OP_CLOSE, OP_CLAIM, OP_RELEASE,
       OP_KDA, OP_DETACH, OP_CTRL, OP_INTR };

#pragma pack(push,1)
struct req  { uint32_t op, handle, a, b, c, d, e, datalen; };
struct resp { int32_t ret; uint32_t handle; int32_t transferred; uint32_t datalen; };
#pragma pack(pop)

static SOCKET g_sock = INVALID_SOCKET;
static CRITICAL_SECTION g_lock;
static int g_lock_ready = 0;

static void ensure_lock(void)
{

    if (!g_lock_ready) { InitializeCriticalSection(&g_lock); g_lock_ready = 1; }
}

static int rd(SOCKET s, void *buf, int n)
{
    char *p = buf; int got = 0;
    while (got < n) {
        int r = recv(s, p + got, n - got, 0);
        if (r <= 0) return -1;
        got += r;
    }
    return 0;
}
static int wr(SOCKET s, const void *buf, int n)
{
    const char *p = buf; int put = 0;
    while (put < n) {
        int r = send(s, p + put, n - put, 0);
        if (r <= 0) return -1;
        put += r;
    }
    return 0;
}

static int connect_daemon(void)
{
    if (g_sock != INVALID_SOCKET) return 0;
    static int wsa = 0;
    if (!wsa) { WSADATA w; if (WSAStartup(MAKEWORD(2,2), &w)) return -1; wsa = 1; }

    int port = 47288;
    const char *e = getenv("FUNKEY_USB_PORT");
    if (e && *e) port = atoi(e);

    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    if (s == INVALID_SOCKET) return -1;
    struct sockaddr_in a; memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons((u_short)port);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(s, (struct sockaddr *)&a, sizeof a) != 0) { closesocket(s); return -1; }
    int one = 1; setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (char *)&one, sizeof one);
    g_sock = s;
    return 0;
}

static struct resp rpc(struct req *q, const void *out, int outlen, void *in, int inmax)
{
    struct resp r; memset(&r, 0, sizeof r); r.ret = -1;
    ensure_lock();
    EnterCriticalSection(&g_lock);
    if (connect_daemon() != 0) { LeaveCriticalSection(&g_lock); return r; }

    q->datalen = (uint32_t)(outlen > 0 ? outlen : 0);
    int bad = wr(g_sock, q, sizeof *q) != 0
           || (q->datalen && wr(g_sock, out, (int)q->datalen) != 0)
           || rd(g_sock, &r, sizeof r) != 0;
    if (!bad && r.datalen) {
        int take = (int)r.datalen < inmax ? (int)r.datalen : inmax;
        if (rd(g_sock, in, take) != 0) bad = 1;
        else if ((int)r.datalen > take) {
            char junk[256];                       
            int left = (int)r.datalen - take;
            while (left > 0) { int t = left < (int)sizeof junk ? left : (int)sizeof junk;
                if (rd(g_sock, junk, t) != 0) { bad = 1; break; } left -= t; }
        }
    }
    if (bad) { closesocket(g_sock); g_sock = INVALID_SOCKET; memset(&r, 0, sizeof r); r.ret = -1; }
    LeaveCriticalSection(&g_lock);
    return r;
}

__declspec(dllexport) int libusb_init(void **ctx)
{
    struct req q; memset(&q, 0, sizeof q); q.op = OP_INIT;
    struct resp r = rpc(&q, NULL, 0, NULL, 0);
    if (r.ret == 0 && ctx) *ctx = (void *)1;   
    return r.ret;
}

__declspec(dllexport) void libusb_exit(void *ctx)
{
    (void)ctx;
    struct req q; memset(&q, 0, sizeof q); q.op = OP_EXIT;
    rpc(&q, NULL, 0, NULL, 0);
}

__declspec(dllexport) void *libusb_open_device_with_vid_pid(void *ctx, uint16_t vid, uint16_t pid)
{
    (void)ctx;
    struct req q; memset(&q, 0, sizeof q); q.op = OP_OPEN; q.a = vid; q.b = pid;
    struct resp r = rpc(&q, NULL, 0, NULL, 0);
    return (r.ret == 0 && r.handle) ? (void *)(uintptr_t)r.handle : NULL;
}

__declspec(dllexport) void libusb_close(void *h)
{
    struct req q; memset(&q, 0, sizeof q); q.op = OP_CLOSE; q.handle = (uint32_t)(uintptr_t)h;
    rpc(&q, NULL, 0, NULL, 0);
}

static int simple(uint32_t op, void *h, int iface)
{
    struct req q; memset(&q, 0, sizeof q);
    q.op = op; q.handle = (uint32_t)(uintptr_t)h; q.a = (uint32_t)iface;
    return rpc(&q, NULL, 0, NULL, 0).ret;
}
__declspec(dllexport) int libusb_claim_interface(void *h, int i)        { return simple(OP_CLAIM, h, i); }
__declspec(dllexport) int libusb_release_interface(void *h, int i)      { return simple(OP_RELEASE, h, i); }
__declspec(dllexport) int libusb_kernel_driver_active(void *h, int i)   { return simple(OP_KDA, h, i); }
__declspec(dllexport) int libusb_detach_kernel_driver(void *h, int i)   { return simple(OP_DETACH, h, i); }

__declspec(dllexport) int libusb_control_transfer(void *h, uint8_t bmRequestType,
    uint8_t bRequest, uint16_t wValue, uint16_t wIndex,
    unsigned char *data, uint16_t wLength, unsigned int timeout)
{
    struct req q; memset(&q, 0, sizeof q);
    q.op = OP_CTRL; q.handle = (uint32_t)(uintptr_t)h;
    q.a = bmRequestType; q.b = bRequest;
    q.c = ((uint32_t)wValue << 16) | wIndex; q.d = wLength; q.e = timeout;
    int isIn = (bmRequestType & 0x80) != 0;
    struct resp r = rpc(&q, isIn ? NULL : data, isIn ? 0 : wLength, data, wLength);
    return r.ret;
}

__declspec(dllexport) int libusb_interrupt_transfer(void *h, unsigned char endpoint,
    unsigned char *data, int length, int *transferred, unsigned int timeout)
{
    struct req q; memset(&q, 0, sizeof q);
    q.op = OP_INTR; q.handle = (uint32_t)(uintptr_t)h;
    q.a = endpoint; q.c = (uint32_t)length; q.e = timeout;
    int isIn = (endpoint & 0x80) != 0;
    struct resp r = rpc(&q, isIn ? NULL : data, isIn ? 0 : length, data, length);
    if (transferred) *transferred = r.transferred;
    return r.ret;
}

__declspec(dllexport) const char *libusb_error_name(int code)
{
    switch (code) {
    case 0:   return "LIBUSB_SUCCESS";
    case -1:  return "LIBUSB_ERROR_IO";
    case -2:  return "LIBUSB_ERROR_INVALID_PARAM";
    case -3:  return "LIBUSB_ERROR_ACCESS";
    case -4:  return "LIBUSB_ERROR_NO_DEVICE";
    case -5:  return "LIBUSB_ERROR_NOT_FOUND";
    case -6:  return "LIBUSB_ERROR_BUSY";
    case -7:  return "LIBUSB_ERROR_TIMEOUT";
    case -8:  return "LIBUSB_ERROR_OVERFLOW";
    case -9:  return "LIBUSB_ERROR_PIPE";
    case -10: return "LIBUSB_ERROR_INTERRUPTED";
    case -11: return "LIBUSB_ERROR_NO_MEM";
    case -12: return "LIBUSB_ERROR_NOT_SUPPORTED";
    default:  return "LIBUSB_ERROR_OTHER";
    }
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)inst; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) { DisableThreadLibraryCalls(inst); ensure_lock(); }
    return TRUE;
}
