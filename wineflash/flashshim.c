/*
 * Flash ActiveX de-licensing shim for Wine.
 *
 * Problem: FunkeyOne.exe (WinForms, real MS .NET 4.8 under Wine) embeds the
 * Adobe/HARMAN Flash Player ActiveX control via System.Windows.Forms.AxHost.
 * AxHost first asks the class factory for IClassFactory2 to fetch a runtime
 * license key, then creates the control with IClassFactory2::CreateInstanceLic.
 * Under Wine the CLR<->oleaut32 marshalling of that licensed call corrupts
 * memory and the process dies with an AccessViolation inside CreateWithLicense.
 * The *unlicensed* path (plain IClassFactory::CreateInstance) works fine —
 * verified against this exact Flash.ocx.
 *
 * Fix: register THIS dll under the ShockwaveFlash CLSID instead of Flash.ocx.
 * Its class factory:
 *   - answers IClassFactory (plain) normally, and
 *   - returns E_NOINTERFACE for IClassFactory2.
 * AxHost.GetLicenseKey() explicitly treats E_NOINTERFACE as "no license", so
 * it skips the licensed path and calls plain CreateInstance — which the shim
 * forwards straight to the real Flash.ocx sitting next to this file. The real
 * control does all the actual SWF rendering; only the licensing handshake is
 * bypassed.
 *
 * Everything here is Windows x64 (shim, CLR, Flash.ocx alike), so the COM ABI
 * is native — no cross-ABI juggling like the libusb bridge needed.
 */
#include <windows.h>
#include <unknwn.h>
#include <ocidl.h>
#include <stdio.h>
#include <stdarg.h>

static void shim_log(const char *fmt, ...)
{
    static int on = -1;
    if (on < 0) { char b[8]; on = GetEnvironmentVariableA("FUNKEY_SHIM_DEBUG", b, sizeof b) ? 1 : 0; }
    if (!on) return;
    va_list ap; va_start(ap, fmt);
    fprintf(stderr, "[flash-shim] "); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
    fflush(stderr); va_end(ap);
}

/* Local GUID constants (no initguid.h / -luuid coupling needed for these).
 * IID_IUnknown, IID_IClassFactory, IID_IClassFactory2 come from the SDK
 * headers + -luuid. */
/* {D27CDB6E-AE6D-11cf-96B8-444553540000} — ShockwaveFlash.ShockwaveFlash */
static const GUID CLSID_ShockwaveFlash =
    { 0xd27cdb6e, 0xae6d, 0x11cf, { 0x96, 0xb8, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00 } };

static LONG g_lock;

/* --- the real Flash.ocx, loaded lazily --- */
typedef HRESULT (WINAPI *DllGetClassObject_t)(REFCLSID, REFIID, void **);

static HRESULT real_flash_factory(REFIID riid, void **ppv)
{
    static HMODULE ocx;
    static DllGetClassObject_t getobj;
    if (!ocx) {
        /* 1) explicit path from the launcher (most reliable) */
        WCHAR env[MAX_PATH];
        if (GetEnvironmentVariableW(L"FUNKEY_FLASH_OCX", env, MAX_PATH))
            ocx = LoadLibraryW(env);
        /* 2) the real OCX beside us, under its renamed name. This shim is
         *    installed AS Flash.ocx (reg-free COM loads it by that name from
         *    the manifest), so the genuine control is renamed FlashReal.ocx
         *    to avoid loading ourselves. */
        if (!ocx) ocx = LoadLibraryW(L"FlashReal.ocx");
        if (!ocx) return E_FAIL;
        getobj = (DllGetClassObject_t)GetProcAddress(ocx, "DllGetClassObject");
        if (!getobj) return E_FAIL;
    }
    return getobj(&CLSID_ShockwaveFlash, riid, ppv);
}

/* --- shim IClassFactory (singleton, no real refcount needed) --- */
static HRESULT STDMETHODCALLTYPE cf_QueryInterface(IClassFactory *this,
    REFIID riid, void **ppv)
{
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IClassFactory)) {
        *ppv = this;
        this->lpVtbl->AddRef(this);
        return S_OK;
    }
    /* The whole point: hide IClassFactory2 so AxHost skips licensing. */
    shim_log("factory QI %s -> E_NOINTERFACE",
             IsEqualIID(riid, &IID_IClassFactory2) ? "IClassFactory2" : "other");
    *ppv = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE cf_AddRef(IClassFactory *this)   { (void)this; return 2; }
static ULONG STDMETHODCALLTYPE cf_Release(IClassFactory *this)  { (void)this; return 1; }

static HRESULT STDMETHODCALLTYPE cf_CreateInstance(IClassFactory *this,
    IUnknown *outer, REFIID riid, void **ppv)
{
    (void)this;
    IClassFactory *real = NULL;
    HRESULT hr = real_flash_factory(&IID_IClassFactory, (void **)&real);
    if (FAILED(hr) || !real) return FAILED(hr) ? hr : E_FAIL;
    hr = real->lpVtbl->CreateInstance(real, outer, riid, ppv);
    real->lpVtbl->Release(real);
    return hr;
}

static HRESULT STDMETHODCALLTYPE cf_LockServer(IClassFactory *this, BOOL lock)
{
    (void)this;
    if (lock) InterlockedIncrement(&g_lock); else InterlockedDecrement(&g_lock);
    return S_OK;
}

static const IClassFactoryVtbl g_cf_vtbl = {
    cf_QueryInterface, cf_AddRef, cf_Release, cf_CreateInstance, cf_LockServer
};
static IClassFactory g_cf = { (IClassFactoryVtbl *)&g_cf_vtbl };

/* --- DLL exports --- */
HRESULT WINAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void **ppv)
{
    shim_log("DllGetClassObject called (flash clsid=%d)",
             IsEqualCLSID(rclsid, &CLSID_ShockwaveFlash));
    if (IsEqualCLSID(rclsid, &CLSID_ShockwaveFlash))
        return cf_QueryInterface((IClassFactory *)&g_cf, riid, ppv);
    *ppv = NULL;
    return CLASS_E_CLASSNOTAVAILABLE;
}

HRESULT WINAPI DllCanUnloadNow(void)
{
    return g_lock ? S_FALSE : S_FALSE;   /* never auto-unload: real ocx stays */
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
        DisableThreadLibraryCalls(inst);
    return TRUE;
}
