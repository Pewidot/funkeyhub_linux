/*
 * ninput.dll no-op replacement for Wine.
 *
 * Adobe/HARMAN Flash 34 (the control the game embeds) drives the Windows
 * Pointer Input / InteractionContext API (ninput.dll) for touch gestures.
 * Wine's builtin ninput implements some of these as stubs that ABORT the
 * whole process when called — StopInteractionContext is one, and it kills
 * the game right after the Flash control initialises.
 *
 * The game is perfectly playable with a mouse and needs no gesture handling,
 * so every InteractionContext entry point here is a harmless no-op that just
 * returns S_OK. CreateInteractionContext hands back a non-NULL dummy handle
 * so the caller's null-checks pass. Win64 is caller-cleanup, so declaring the
 * no-ops with no parameters is safe regardless of how many args the caller
 * pushes.
 *
 * Installed as a native override (WINEDLLOVERRIDES=ninput=n) with this PE DLL
 * on the loader search path (the game directory).
 */
#include <windows.h>

#define OK __attribute__((used)) HRESULT WINAPI

/* handle-returning creator: give back any non-NULL value */
HRESULT WINAPI CreateInteractionContext(void **ctx)
{
    if (ctx) *ctx = (void *)(ULONG_PTR)1;
    return S_OK;
}

OK DestroyInteractionContext(void)                        { return S_OK; }
OK ResetInteractionContext(void)                          { return S_OK; }
OK StopInteractionContext(void)                           { return S_OK; }
OK AddPointerInteractionContext(void)                     { return S_OK; }
OK RemovePointerInteractionContext(void)                  { return S_OK; }
OK ProcessPointerFramesInteractionContext(void)           { return S_OK; }
OK BufferPointerPacketsInteractionContext(void)           { return S_OK; }
OK ProcessBufferedPacketsInteractionContext(void)         { return S_OK; }
OK ProcessInertiaInteractionContext(void)                 { return S_OK; }
OK RegisterOutputCallbackInteractionContext(void)         { return S_OK; }
OK SetInteractionConfigurationInteractionContext(void)    { return S_OK; }
OK GetInteractionConfigurationInteractionContext(void)    { return S_OK; }
OK SetPropertyInteractionContext(void)                    { return S_OK; }
OK GetPropertyInteractionContext(void)                    { return S_OK; }
OK GetStateInteractionContext(void)                       { return S_OK; }
OK SetCrossSlideParametersInteractionContext(void)        { return S_OK; }
OK GetCrossSlideParameterInteractionContext(void)         { return S_OK; }
OK SetInertiaParameterInteractionContext(void)            { return S_OK; }
OK GetInertiaParameterInteractionContext(void)            { return S_OK; }
OK SetMouseWheelParameterInteractionContext(void)         { return S_OK; }
OK GetMouseWheelParameterInteractionContext(void)         { return S_OK; }
OK SetPivotInteractionContext(void)                       { return S_OK; }

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(inst);
    return TRUE;
}
