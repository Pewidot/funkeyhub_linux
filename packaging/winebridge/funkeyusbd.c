
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

int   ub_init(void);
void  ub_exit(void);
void *ub_open(unsigned vid, unsigned pid);
void  ub_close(void *h);
int   ub_claim_interface(void *h, int iface);
int   ub_release_interface(void *h, int iface);
int   ub_kernel_driver_active(void *h, int iface);
int   ub_detach_kernel_driver(void *h, int iface);
int   ub_control_transfer(void *h, unsigned char bmRequestType, unsigned char bRequest,
        unsigned short wValue, unsigned short wIndex, unsigned char *data,
        unsigned short wLength, unsigned int timeout);
int   ub_interrupt_transfer(void *h, unsigned char endpoint, unsigned char *data,
        int length, int *transferred, unsigned int timeout);

enum { OP_INIT=1, OP_EXIT, OP_OPEN, OP_CLOSE, OP_CLAIM, OP_RELEASE,
       OP_KDA, OP_DETACH, OP_CTRL, OP_INTR };

#pragma pack(push,1)
struct req  { uint32_t op, handle, a, b, c, d, e, datalen; };
struct resp { int32_t ret; uint32_t handle; int32_t transferred; uint32_t datalen; };
#pragma pack(pop)

#define BUFMAX 4096
#define MAXH   8
static void *g_htab[MAXH];   

static int readn(int fd, void *buf, size_t n)
{
    char *p = buf; size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, p + got, n - got);
        if (r <= 0) return (r == 0) ? 0 : -1;
        got += (size_t)r;
    }
    return 1;
}
static int writen(int fd, const void *buf, size_t n)
{
    const char *p = buf; size_t put = 0;
    while (put < n) {
        ssize_t r = write(fd, p + put, n - put);
        if (r <= 0) return -1;
        put += (size_t)r;
    }
    return 0;
}

static void *h_lookup(uint32_t id)
{
    return (id >= 1 && id <= MAXH) ? g_htab[id - 1] : NULL;
}

static void serve(int fd)
{
    struct req q;
    unsigned char in[BUFMAX], out[BUFMAX];
    memset(g_htab, 0, sizeof g_htab);

    while (readn(fd, &q, sizeof q) == 1) {
        struct resp r; memset(&r, 0, sizeof r);
        uint32_t dlen = q.datalen > BUFMAX ? BUFMAX : q.datalen;
        if (q.datalen && readn(fd, in, dlen) != 1) break;

        void *h = h_lookup(q.handle);
        switch (q.op) {
        case OP_INIT:    r.ret = ub_init(); break;
        case OP_EXIT:    ub_exit(); r.ret = 0; break;
        case OP_OPEN: {
            void *nh = ub_open(q.a, q.b);
            if (nh) {
                int slot = -1;
                for (int i = 0; i < MAXH; i++) if (!g_htab[i]) { slot = i; break; }
                if (slot < 0) { ub_close(nh); r.ret = -1; }
                else { g_htab[slot] = nh; r.handle = slot + 1; r.ret = 0; }
            } else r.ret = -4;            
            break;
        }
        case OP_CLOSE:
            if (h) { ub_close(h); if (q.handle>=1 && q.handle<=MAXH) g_htab[q.handle-1]=NULL; }
            r.ret = 0; break;
        case OP_CLAIM:   r.ret = h ? ub_claim_interface(h, q.a)       : -4; break;
        case OP_RELEASE: r.ret = h ? ub_release_interface(h, q.a)     : -4; break;
        case OP_KDA:     r.ret = h ? ub_kernel_driver_active(h, q.a)  : -4; break;
        case OP_DETACH:  r.ret = h ? ub_detach_kernel_driver(h, q.a)  : -4; break;
        case OP_CTRL: {
            unsigned char bmType = (unsigned char)q.a, bReq = (unsigned char)q.b;
            unsigned short wValue = (unsigned short)(q.c >> 16), wIndex = (unsigned short)(q.c & 0xffff);
            unsigned short wLen = (unsigned short)q.d; unsigned int to = q.e;
            if (wLen > BUFMAX) wLen = BUFMAX;
            unsigned char *buf = (bmType & 0x80) ? out : in;   
            r.ret = h ? ub_control_transfer(h, bmType, bReq, wValue, wIndex, buf, wLen, to) : -4;
            if ((bmType & 0x80) && r.ret > 0) r.datalen = (uint32_t)r.ret;
            break;
        }
        case OP_INTR: {
            unsigned char ep = (unsigned char)q.a; int len = (int)q.c; unsigned int to = q.e;
            if (len > BUFMAX) len = BUFMAX;
            int xfer = 0;
            unsigned char *buf = (ep & 0x80) ? out : in;       
            r.ret = h ? ub_interrupt_transfer(h, ep, buf, len, &xfer, to) : -4;
            r.transferred = xfer;
            if ((ep & 0x80) && xfer > 0) r.datalen = (uint32_t)xfer;
            break;
        }
        default: r.ret = -99; break;
        }

        if (writen(fd, &r, sizeof r) != 0) break;
        if (r.datalen && writen(fd, out, r.datalen) != 0) break;
        if (q.op == OP_EXIT) break;
    }

    for (int i = 0; i < MAXH; i++) if (g_htab[i]) { ub_close(g_htab[i]); g_htab[i] = NULL; }
}

int main(void)
{
    signal(SIGPIPE, SIG_IGN);
    int port = 47288;
    const char *p = getenv("FUNKEY_USB_PORT");
    if (p && *p) port = atoi(p);

    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) { perror("socket"); return 1; }
    int one = 1; setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a; memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_port = htons(port);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(s, (struct sockaddr *)&a, sizeof a) != 0) { perror("bind"); return 1; }
    if (listen(s, 4) != 0) { perror("listen"); return 1; }
    fprintf(stderr, "[funkeyusbd] listening on 127.0.0.1:%d\n", port);

    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) { if (errno == EINTR) continue; break; }
        int one2 = 1; setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one2, sizeof one2);
        serve(c);
        close(c);
    }
    close(s);
    return 0;
}
