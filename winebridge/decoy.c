/* Tiny Win32 window titled "FunkeyOne" so MegaByte.exe proceeds to its USB
 * code during bridge testing without launching the full game. Exits on its
 * own after 90 seconds. */
#include <windows.h>

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    (void)prev; (void)cmd; (void)show;
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = inst;
    wc.lpszClassName = "FunkeyDecoy";
    RegisterClassA(&wc);
    CreateWindowExA(0, "FunkeyDecoy", "FunkeyOne", WS_OVERLAPPEDWINDOW,
                    0, 0, 200, 100, NULL, NULL, inst, NULL);
    /* window stays hidden; FindWindow still sees it */
    SetTimer(NULL, 1, 90000, NULL);
    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        if (msg.message == WM_TIMER) break;
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    return 0;
}
