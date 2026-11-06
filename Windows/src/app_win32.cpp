#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <wincrypt.h>
#include <shlobj.h>
#include <atomic>
#include <optional>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "prison/agent.hpp"
#include "prison/server.hpp"

namespace {
constexpr wchar_t kClassName[] = L"PrisonDisplayWindows";
constexpr wchar_t kVersion[] = L"0.2.2";
constexpr char kVersionUtf8[] = "0.2.2";
constexpr UINT kStatusMessage = WM_APP + 1;
constexpr UINT kSetClipboard = WM_APP + 2;
constexpr UINT kConfirmPairing = WM_APP + 3;
struct PairingQuestion { std::string mac, code; bool accepted = false; };
HWND g_window = nullptr;

std::wstring widen(const std::string& text) {
    if (text.empty()) return {};
    const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring out(static_cast<std::size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
    return out;
}
std::string narrow(const std::wstring& text) {
    if (text.empty()) return {};
    const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<std::size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
    return out;
}

// Real input. Coordinates span every monitor (virtual desktop).
struct Win32Sink final : prison::InputSink {
    static void send(INPUT input) { SendInput(1, &input, sizeof input); }
    void move(double x, double y) override {
        INPUT input{}; input.type = INPUT_MOUSE;
        input.mi.dx = static_cast<LONG>(x * 65535.0 + 0.5); input.mi.dy = static_cast<LONG>(y * 65535.0 + 0.5);
        input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
        send(input);
    }
    void button(Button button, bool down) override {
        INPUT input{}; input.type = INPUT_MOUSE;
        switch (button) {
        case Button::left: input.mi.dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP; break;
        case Button::right: input.mi.dwFlags = down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP; break;
        case Button::middle: input.mi.dwFlags = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP; break;
        }
        send(input);
    }
    void wheel(int vertical, int horizontal) override {
        if (vertical) { INPUT input{}; input.type = INPUT_MOUSE; input.mi.dwFlags = MOUSEEVENTF_WHEEL; input.mi.mouseData = static_cast<DWORD>(vertical); send(input); }
        if (horizontal) { INPUT input{}; input.type = INPUT_MOUSE; input.mi.dwFlags = MOUSEEVENTF_HWHEEL; input.mi.mouseData = static_cast<DWORD>(horizontal); send(input); }
    }
    // Writing needs a window owned by the interface thread.
    void set_clipboard(const std::string& text) override {
        if (g_window) SendMessageW(g_window, kSetClipboard, 0, reinterpret_cast<LPARAM>(&text));
    }
    std::optional<std::string> clipboard_changed() override {
        const DWORD sequence = GetClipboardSequenceNumber();
        if (sequence == seen_) return std::nullopt;
        seen_ = sequence;
        if (!IsClipboardFormatAvailable(CF_UNICODETEXT) || !OpenClipboard(nullptr)) return std::nullopt;
        std::optional<std::string> result;
        if (HANDLE handle = GetClipboardData(CF_UNICODETEXT)) {
            if (const auto* text = static_cast<const wchar_t*>(GlobalLock(handle))) { result = narrow(text); GlobalUnlock(handle); }
        }
        CloseClipboard();
        return result;
    }
    std::atomic<DWORD> seen_{GetClipboardSequenceNumber()};
    // Replace this .exe with the verified build from the Mac and restart.
    void install_update(const prison::Bytes& data, const std::string& version) override;
    void key(prison::ScanKey key, bool down) override {
        INPUT input{}; input.type = INPUT_KEYBOARD;
        input.ki.wScan = key.scan;
        input.ki.dwFlags = KEYEVENTF_SCANCODE | (key.extended ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP);
        send(input);
    }
};

std::wstring data_folder() {
    PWSTR path = nullptr; std::wstring folder;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path))) folder = std::wstring(path) + L"\\PRISON DISPLAY";
    CoTaskMemFree(path);
    CreateDirectoryW(folder.c_str(), nullptr);
    return folder;
}
// The key is protected for this Windows user with DPAPI, never stored in clear.
std::string load_or_create_key() {
    const auto file = data_folder() + L"\\clave-mac.bin";
    std::ifstream in(std::filesystem::path(file), std::ios::binary);
    std::vector<char> sealed((std::istreambuf_iterator<char>(in)), {});
    if (!sealed.empty()) {
        DATA_BLOB input{static_cast<DWORD>(sealed.size()), reinterpret_cast<BYTE*>(sealed.data())}, output{};
        if (CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, 0, &output)) {
            std::string key(reinterpret_cast<char*>(output.pbData), output.cbData);
            LocalFree(output.pbData);
            try { return prison::normalized_key(key); } catch (...) {}
        }
    }
    const auto key = prison::new_pc_key();
    DATA_BLOB input{static_cast<DWORD>(key.size()), reinterpret_cast<BYTE*>(const_cast<char*>(key.data()))}, output{};
    if (CryptProtectData(&input, L"PRISON DISPLAY", nullptr, nullptr, nullptr, 0, &output)) {
        std::ofstream out(std::filesystem::path(file), std::ios::binary | std::ios::trunc);
        out.write(reinterpret_cast<char*>(output.pbData), output.cbData);
        LocalFree(output.pbData);
    }
    return key;
}
std::wstring local_addresses() {
    char host[256] = {};
    if (gethostname(host, sizeof host) != 0) return L"(desconocida)";
    addrinfo hints{}; hints.ai_family = AF_INET; addrinfo* result = nullptr;
    if (getaddrinfo(host, nullptr, &hints, &result) != 0) return L"(desconocida)";
    std::wstring list;
    for (auto* item = result; item; item = item->ai_next) {
        char text[INET_ADDRSTRLEN] = {};
        inet_ntop(AF_INET, &reinterpret_cast<sockaddr_in*>(item->ai_addr)->sin_addr, text, sizeof text);
        const std::wstring address = widen(text);
        if (address.rfind(L"127.", 0) == 0 || address.rfind(L"169.254.", 0) == 0 || list.find(address) != std::wstring::npos) continue;
        if (!list.empty()) list += L"   ·   ";
        list += address;
    }
    freeaddrinfo(result);
    return list.empty() ? L"(sin red)" : list;
}

Win32Sink g_sink;
void set_status(const std::string& text);
std::wstring own_path() {
    std::wstring path(MAX_PATH, L'\0');
    for (;;) {
        const DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
        if (length < path.size()) { path.resize(length); return path; }
        path.resize(path.size() * 2);
    }
}
void Win32Sink::install_update(const prison::Bytes& data, const std::string& version) {
    const auto current = own_path(), fresh = current + L".nuevo", old = current + L".anterior";
    {
        std::ofstream out(std::filesystem::path(fresh), std::ios::binary | std::ios::trunc);
        out.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
        if (!out) { set_status("No se pudo guardar la actualización."); return; }
    }
    DeleteFileW(old.c_str());
    if (!MoveFileExW(current.c_str(), old.c_str(), MOVEFILE_REPLACE_EXISTING)) { set_status("No se pudo sustituir la app (¿carpeta protegida?)."); return; }
    if (!MoveFileExW(fresh.c_str(), current.c_str(), MOVEFILE_REPLACE_EXISTING)) { MoveFileExW(old.c_str(), current.c_str(), 0); set_status("No se pudo sustituir la app."); return; }
    set_status("Actualizado a " + version + ". Reiniciando…");
    STARTUPINFOW startup{}; startup.cb = sizeof startup; PROCESS_INFORMATION process{};
    std::wstring command = L"\"" + current + L"\" --tras-actualizar";
    if (CreateProcessW(current.c_str(), command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup, &process)) {
        CloseHandle(process.hThread); CloseHandle(process.hProcess);
    }
    if (g_window) PostMessageW(g_window, WM_CLOSE, 0, 0);
}
std::unique_ptr<prison::InputAgent> g_agent;
std::unique_ptr<prison::AgentServer> g_server;
std::atomic<bool> g_stop{false};
std::thread g_thread;
std::mutex g_status_mutex;
std::wstring g_status = L"Preparando…";
std::wstring g_key, g_addresses, g_name;

void set_status(const std::string& text) {
    { std::lock_guard<std::mutex> lock(g_status_mutex); g_status = widen(text); }
    if (g_window) PostMessageW(g_window, kStatusMessage, 0, 0);
}
void text(HDC dc, int x, int y, const std::wstring& value, COLORREF color, int size = 18, int weight = FW_NORMAL) {
    HFONT font = CreateFontW(size, 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
    HFONT old = static_cast<HFONT>(SelectObject(dc, font));
    SetTextColor(dc, color); TextOutW(dc, x, y, value.c_str(), static_cast<int>(value.size()));
    SelectObject(dc, old); DeleteObject(font);
}
void screen_size(std::uint32_t& width, std::uint32_t& height) {
    width = static_cast<std::uint32_t>(GetSystemMetrics(SM_CXVIRTUALSCREEN));
    height = static_cast<std::uint32_t>(GetSystemMetrics(SM_CYVIRTUALSCREEN));
}

LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case WM_PAINT: {
        PAINTSTRUCT paint{}; HDC dc = BeginPaint(window, &paint);
        RECT bounds{}; GetClientRect(window, &bounds);
        HBRUSH background = CreateSolidBrush(RGB(18, 20, 27)); FillRect(dc, &bounds, background); DeleteObject(background);
        SetBkMode(dc, TRANSPARENT);
        text(dc, 42, 30, L"PRISON DISPLAY", RGB(245, 245, 250), 34, FW_BOLD);
        text(dc, 44, 72, L"PC con Windows · ratón y teclado del Mac", RGB(170, 150, 255), 20, FW_SEMIBOLD);
        std::wstring status; { std::lock_guard<std::mutex> lock(g_status_mutex); status = g_status; }
        text(dc, 44, 122, L"Estado", RGB(150, 155, 170), 16, FW_SEMIBOLD);
        text(dc, 44, 144, status, RGB(90, 220, 145), 20, FW_SEMIBOLD);
        text(dc, 44, 196, L"En el Mac: Enviar pantalla → PC con Windows → «Buscar y emparejar» (o escribe la dirección y la clave)", RGB(205, 210, 225));
        text(dc, 44, 236, L"Dirección de este PC", RGB(150, 155, 170), 16, FW_SEMIBOLD);
        text(dc, 44, 258, g_addresses, RGB(245, 245, 250), 24, FW_SEMIBOLD);
        text(dc, 44, 302, L"Clave", RGB(150, 155, 170), 16, FW_SEMIBOLD);
        text(dc, 44, 324, g_key, RGB(245, 245, 250), 28, FW_BOLD);
        text(dc, 44, 376, L"La clave solo se escribe una vez en el Mac. Si Windows pregunta por el firewall, permite redes privadas.", RGB(185, 190, 205), 16);
        text(dc, 44, 398, L"Para volver al Mac, lleva el ratón al borde por el que entraste o pulsa Ctrl+Opción+Esc en el Mac.", RGB(185, 190, 205), 16);
        text(dc, 44, bounds.bottom - 36, L"Versión " + std::wstring(kVersion) + L" · " + g_name, RGB(130, 135, 150), 16);
        EndPaint(window, &paint);
        return 0;
    }
    case kStatusMessage: InvalidateRect(window, nullptr, FALSE); return 0;
    case kConfirmPairing: {
        auto* question = reinterpret_cast<PairingQuestion*>(lparam);
        ShowWindow(window, SW_RESTORE); SetForegroundWindow(window);
        const std::string code = question->code.substr(0, 3) + " " + question->code.substr(3);
        const std::wstring text = L"El Mac «" + widen(question->mac) + L"» quiere usar este PC con su ratón, teclado y portapapeles.\n\n"
            L"Código: " + widen(code) + L"\n\n¿Es el mismo código que muestra el Mac?";
        question->accepted = MessageBoxW(window, text.c_str(), L"PRISON DISPLAY · Emparejar con un Mac", MB_YESNO | MB_ICONQUESTION | MB_SETFOREGROUND | MB_TOPMOST) == IDYES;
        return 0;
    }
    case kSetClipboard: {
        const auto& text = *reinterpret_cast<const std::string*>(lparam);
        const std::wstring wide = widen(text);
        if (!OpenClipboard(window)) return 0;
        EmptyClipboard();
        if (HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, (wide.size() + 1) * sizeof(wchar_t))) {
            if (auto* target = static_cast<wchar_t*>(GlobalLock(memory))) {
                std::copy(wide.begin(), wide.end(), target); target[wide.size()] = L'\0'; GlobalUnlock(memory);
                if (!SetClipboardData(CF_UNICODETEXT, memory)) GlobalFree(memory);
            } else GlobalFree(memory);
        }
        CloseClipboard();
        g_sink.seen_ = GetClipboardSequenceNumber(); // Not echoed back to the Mac.
        return 0;
    }
    case WM_DISPLAYCHANGE: {
        std::uint32_t width = 0, height = 0; screen_size(width, height);
        if (g_server) g_server->with_agent([&](prison::InputAgent& agent) { agent.set_screen(width, height); });
        return 0;
    }
    case WM_DESTROY:
        g_stop = true;
        if (g_thread.joinable()) g_thread.join();
        PostQuitMessage(0);
        return 0;
    default: return DefWindowProcW(window, message, wparam, lparam);
    }
}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    // Physical pixels on every monitor, so the Mac moves at the right speed.
    using Awareness = BOOL(WINAPI*)(HANDLE);
    if (auto set = reinterpret_cast<Awareness>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetProcessDpiAwarenessContext")))
        set(reinterpret_cast<HANDLE>(-4)); // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
    WSADATA wsa{}; if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 1;
    DeleteFileW((own_path() + L".anterior").c_str()); // Left by the previous update.
    HANDLE single = CreateMutexW(nullptr, TRUE, L"Local\\PrisonDisplayWindowsInput");
    // After an update the previous copy is still closing: wait for it.
    DWORD owned = WAIT_OBJECT_0;
    if (GetLastError() == ERROR_ALREADY_EXISTS) owned = WaitForSingleObject(single, 10000);
    if (owned != WAIT_OBJECT_0 && owned != WAIT_ABANDONED) {
        MessageBoxW(nullptr, L"PRISON DISPLAY ya está abierto en este PC.", L"PRISON DISPLAY", MB_ICONINFORMATION);
        return 0;
    }
    wchar_t computer[MAX_COMPUTERNAME_LENGTH + 1] = {}; DWORD length = MAX_COMPUTERNAME_LENGTH + 1;
    GetComputerNameW(computer, &length); g_name = computer;
    const auto key = load_or_create_key();
    g_key = widen(prison::grouped_key(key));
    g_addresses = local_addresses();
    std::uint32_t width = 0, height = 0; screen_size(width, height);
    g_agent = std::make_unique<prison::InputAgent>(g_sink, narrow(g_name).empty() ? "PC con Windows" : narrow(g_name), kVersionUtf8, width, height);
    g_server = std::make_unique<prison::AgentServer>(*g_agent, key);
    g_server->confirm_pairing = [](const std::string& mac, const std::string& code) {
        PairingQuestion question{mac, code};
        if (g_window) SendMessageW(g_window, kConfirmPairing, 0, reinterpret_cast<LPARAM>(&question));
        return question.accepted;
    };

    WNDCLASSW klass{}; klass.hInstance = instance; klass.lpfnWndProc = window_proc; klass.lpszClassName = kClassName;
    klass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    if (!RegisterClassW(&klass)) return 1;
    g_window = CreateWindowExW(0, kClassName, L"PRISON DISPLAY · PC con Windows", WS_OVERLAPPEDWINDOW,
                               CW_USEDEFAULT, CW_USEDEFAULT, 980, 520, nullptr, nullptr, instance, nullptr);
    if (!g_window) return 1;
    g_thread = std::thread([] { if (!g_server->run(g_stop, set_status)) {} });
    ShowWindow(g_window, show); UpdateWindow(g_window);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
    if (single) CloseHandle(single);
    WSACleanup();
    return static_cast<int>(message.wParam);
}
#endif
