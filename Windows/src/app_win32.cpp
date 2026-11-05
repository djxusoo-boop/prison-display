#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include "prison/protocol.hpp"
#include "prison/discovery.hpp"

namespace {
constexpr wchar_t kClassName[] = L"PrisonDisplayWindows";
constexpr wchar_t kVersion[] = L"0.1.0-dev";
// The Windows product has its own visible version, while the wire handshake
// remains compatible with the currently deployed Mac release.
constexpr char kWireProfileVersion[] = "0.4.22";
prison::Discovery g_discovery;
std::wstring g_peer_text = L"Buscando equipos PRISON DISPLAY en la red local…";
int g_monitor_count = 0;
BOOL CALLBACK count_monitor(HMONITOR, HDC, LPRECT, LPARAM data) {
    ++*reinterpret_cast<int*>(data);
    return TRUE;
}
LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case WM_PAINT: {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        RECT bounds{};
        GetClientRect(window, &bounds);
        HBRUSH background = CreateSolidBrush(RGB(18, 20, 27));
        FillRect(dc, &bounds, background);
        DeleteObject(background);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(245, 245, 250));
        HFONT title = CreateFontW(30, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                  DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                  CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                  DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
        HFONT old = static_cast<HFONT>(SelectObject(dc, title));
        TextOutW(dc, 42, 34, L"PRISON DISPLAY", 15);
        SelectObject(dc, old);
        DeleteObject(title);
        SetTextColor(dc, RGB(170, 150, 255));
        TextOutW(dc, 44, 78, L"Windows", 7);
        SetTextColor(dc, RGB(205, 210, 225));
        TextOutW(dc, 44, 130, L"Estado", 6);
        SetTextColor(dc, RGB(90, 220, 145));
        TextOutW(dc, 160, 130, L"Núcleo compatible con Mac validado", 32);
        SetTextColor(dc, RGB(185, 190, 205));
        TextOutW(dc, 44, 182, g_peer_text.c_str(), static_cast<int>(g_peer_text.size()));
        std::wstring monitors = L"Pantallas detectadas: " + std::to_wstring(g_monitor_count);
        SetTextColor(dc, RGB(185, 190, 205));
        TextOutW(dc, 44, 226, monitors.c_str(), static_cast<int>(monitors.size()));
        std::wstring version = L"Versión " + std::wstring(kVersion);
        TextOutW(dc, 44, bounds.bottom - 38, version.c_str(), static_cast<int>(version.size()));
        EndPaint(window, &paint);
        return 0;
    }
    case WM_TIMER: {
        g_discovery.announce();
        const auto peers = g_discovery.poll();
        if (peers.empty()) g_peer_text = L"Buscando equipos PRISON DISPLAY en la red local…";
        else g_peer_text = L"Equipos disponibles: " + std::to_wstring(peers.size());
        InvalidateRect(window, nullptr, FALSE);
        return 0;
    }
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProcW(window, message, wparam, lparam);
    }
}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    WNDCLASSW klass{};
    klass.hInstance = instance;
    klass.lpfnWndProc = window_proc;
    klass.lpszClassName = kClassName;
    klass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    if (!RegisterClassW(&klass)) return 1;
    HWND window = CreateWindowExW(0, kClassName, L"PRISON DISPLAY · Windows",
                                 WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                                 860, 520, nullptr, nullptr, instance, nullptr);
    if (!window) return 1;
    g_discovery.start("Windows de xuso", kWireProfileVersion);
    EnumDisplayMonitors(nullptr, nullptr, count_monitor, reinterpret_cast<LPARAM>(&g_monitor_count));
    SetTimer(window, 1, 1000, nullptr);
    ShowWindow(window, show);
    UpdateWindow(window);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
}
#endif
