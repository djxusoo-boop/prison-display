#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <wincrypt.h>
#include <shlobj.h>
#include <shellapi.h>
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
constexpr wchar_t kVersion[] = L"0.3.0";
constexpr char kVersionUtf8[] = "0.3.0";
constexpr UINT kStatusMessage = WM_APP + 1;
constexpr UINT kSetClipboard = WM_APP + 2;
constexpr UINT kConfirmPairing = WM_APP + 3;
struct PairingQuestion { std::string mac, code; bool accepted = false; };
HWND g_window = nullptr;
std::atomic<bool> g_clipboard_on{true};

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
        if (!g_clipboard_on) return std::nullopt;
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
std::string g_key_raw;
HINSTANCE g_instance = nullptr;
HICON app_icon() { HICON icon = LoadIconW(g_instance, MAKEINTRESOURCEW(1)); return icon ? icon : LoadIconW(nullptr, MAKEINTRESOURCEW(32512)); }
constexpr UINT kTrayMessage = WM_APP + 4;
constexpr UINT kRefreshTimer = 7;

// ---------- Settings (HKCU\Software\PRISON DISPLAY) ----------
constexpr wchar_t kSettingsKey[] = L"Software\\PRISON DISPLAY";
bool read_setting(const wchar_t* name, bool fallback) {
    DWORD value = 0, size = sizeof value;
    if (RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, name, RRF_RT_REG_DWORD, nullptr, &value, &size) != ERROR_SUCCESS) return fallback;
    return value != 0;
}
void write_setting(const wchar_t* name, bool value) {
    HKEY key = nullptr; DWORD data = value ? 1 : 0;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kSettingsKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        RegSetValueExW(key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&data), sizeof data); RegCloseKey(key);
    }
}
// Start with Windows: only when the person turns it on in Opciones.
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
bool autostart_enabled() { return RegGetValueW(HKEY_CURRENT_USER, kRunKey, L"PRISON DISPLAY", RRF_RT_REG_SZ, nullptr, nullptr, nullptr) == ERROR_SUCCESS; }
void set_autostart(bool on) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) != ERROR_SUCCESS) return;
    if (on) { const std::wstring command = L"\"" + own_path() + L"\" --bandeja"; RegSetValueExW(key, L"PRISON DISPLAY", 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()), static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t))); }
    else RegDeleteValueW(key, L"PRISON DISPLAY");
    RegCloseKey(key);
}

struct Options { bool mouse = true, keyboard = true, clipboard = true, tray = true; } g_options;

// ---------- Drawing ----------
enum class Page { home, connect, options };
Page g_page = Page::home;
struct Hit { RECT rect; int id; };
std::vector<Hit> g_hits;
enum : int { kNavHome = 1, kNavConnect, kNavOptions, kCopyKey, kNewKey, kToggleMouse, kToggleKeyboard, kToggleClipboard, kToggleAutostart, kToggleTray };
double g_scale = 1.0;
int S(double v) { return static_cast<int>(v * g_scale + 0.5); }
const COLORREF kBackground = RGB(17, 19, 23), kSidebar = RGB(23, 26, 31), kCard = RGB(27, 29, 36), kBorder = RGB(48, 51, 59),
    kAccent = RGB(139, 120, 240), kText = RGB(245, 245, 250), kSecondary = RGB(160, 165, 180), kGreen = RGB(90, 210, 140), kOrange = RGB(240, 160, 70);
HFONT font(int size, int weight = FW_NORMAL) {
    return CreateFontW(-S(size), 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
}
void fill(HDC dc, RECT r, COLORREF color, int radius = 0, COLORREF border = CLR_INVALID) {
    HBRUSH brush = CreateSolidBrush(color);
    HPEN pen = CreatePen(PS_SOLID, 1, border == CLR_INVALID ? color : border);
    auto oldBrush = SelectObject(dc, brush); auto oldPen = SelectObject(dc, pen);
    if (radius) RoundRect(dc, r.left, r.top, r.right, r.bottom, S(radius), S(radius)); else Rectangle(dc, r.left, r.top, r.right, r.bottom);
    SelectObject(dc, oldBrush); SelectObject(dc, oldPen); DeleteObject(brush); DeleteObject(pen);
}
int write(HDC dc, int x, int y, int width, const std::wstring& value, COLORREF color, int size = 14, int weight = FW_NORMAL, UINT format = DT_WORDBREAK) {
    HFONT f = font(size, weight); auto old = SelectObject(dc, f); SetTextColor(dc, color);
    RECT r{x, y, x + width, y + S(400)};
    const int height = DrawTextW(dc, value.c_str(), -1, &r, format | DT_NOPREFIX);
    SelectObject(dc, old); DeleteObject(f); return height;
}
RECT card(HDC dc, int x, int& y, int width, int height, const std::wstring& title) {
    RECT r{x, y, x + width, y + height}; fill(dc, r, kCard, 14, kBorder);
    write(dc, x + S(20), y + S(16), width - S(40), title, kAccent, 12, FW_BOLD, DT_SINGLELINE);
    y += height + S(16); return r;
}
void button(HDC dc, RECT r, const std::wstring& label, int id, bool primary) {
    fill(dc, r, primary ? kAccent : RGB(44, 47, 56), 10);
    write(dc, r.left, r.top + (r.bottom - r.top - S(18)) / 2, r.right - r.left, label, kText, 13, FW_SEMIBOLD, DT_CENTER | DT_SINGLELINE);
    g_hits.push_back({r, id});
}
void toggle(HDC dc, int x, int y, int width, const std::wstring& label, const std::wstring& detail, bool on, int id) {
    RECT track{x + width - S(52), y + S(2), x + width, y + S(28)};
    fill(dc, track, on ? kAccent : RGB(60, 63, 72), 26);
    const int knob = on ? track.right - S(24) : track.left + S(2);
    fill(dc, RECT{knob, track.top + S(2), knob + S(22), track.bottom - S(2)}, kText, 22);
    write(dc, x, y, width - S(70), label, kText, 14, FW_SEMIBOLD, DT_SINGLELINE);
    write(dc, x, y + S(22), width - S(70), detail, kSecondary, 12);
    g_hits.push_back({RECT{x, y, x + width, y + S(48)}, id});
}
void nav(HDC dc, int y, const std::wstring& label, Page page, int id) {
    RECT r{S(16), y, S(204), y + S(40)};
    if (g_page == page) fill(dc, r, kAccent, 12);
    write(dc, r.left + S(16), y + S(10), S(170), label, g_page == page ? kText : RGB(190, 192, 200), 14, g_page == page ? FW_SEMIBOLD : FW_NORMAL, DT_SINGLELINE);
    g_hits.push_back({r, id});
}
struct Live { bool greeted = false, controlling = false; std::string peer; } g_live;

void paint(HWND window, HDC dc) {
    RECT bounds{}; GetClientRect(window, &bounds); g_hits.clear();
    fill(dc, bounds, kBackground);
    SetBkMode(dc, TRANSPARENT);
    // Sidebar
    RECT side{0, 0, S(220), bounds.bottom}; fill(dc, side, kSidebar);
    write(dc, S(24), S(26), S(180), L"PRISON DISPLAY", kText, 17, FW_BOLD, DT_SINGLELINE);
    write(dc, S(24), S(52), S(180), g_name, kSecondary, 12, FW_NORMAL, DT_SINGLELINE | DT_END_ELLIPSIS);
    write(dc, S(24), S(92), S(180), L"PC CON WINDOWS", RGB(110, 114, 125), 11, FW_SEMIBOLD, DT_SINGLELINE);
    nav(dc, S(114), L"⌂   Inicio", Page::home, kNavHome);
    nav(dc, S(160), L"⇄   Conectar con el Mac", Page::connect, kNavConnect);
    nav(dc, S(206), L"⚙   Opciones", Page::options, kNavOptions);
    write(dc, S(24), bounds.bottom - S(36), S(180), L"Versión " + std::wstring(kVersion), RGB(110, 114, 125), 11, FW_NORMAL, DT_SINGLELINE);
    // Header and status pill
    const int left = S(250), width = bounds.right - left - S(30);
    const wchar_t* titles[] = {L"Inicio", L"Conectar con el Mac", L"Opciones"};
    const wchar_t* subtitles[] = {L"Usa el ratón, el teclado y el portapapeles del Mac en este PC.", L"Empareja este PC con el Mac una sola vez.", L"Elige qué compartes con el Mac."};
    write(dc, left, S(24), width - S(220), titles[static_cast<int>(g_page)], kText, 24, FW_BOLD, DT_SINGLELINE);
    write(dc, left, S(60), width - S(220), subtitles[static_cast<int>(g_page)], kSecondary, 13, FW_NORMAL, DT_SINGLELINE | DT_END_ELLIPSIS);
    const std::wstring pill = g_live.controlling ? L"●  Controlado por el Mac" : (g_live.greeted ? L"●  Mac conectado" : L"●  Esperando al Mac");
    const COLORREF pillColor = g_live.controlling ? kAccent : (g_live.greeted ? kGreen : kOrange);
    RECT pillRect{bounds.right - S(230), S(24), bounds.right - S(30), S(58)}; fill(dc, pillRect, RGB(33, 36, 44), 30);
    write(dc, pillRect.left, pillRect.top + S(8), pillRect.right - pillRect.left, pill, pillColor, 12, FW_SEMIBOLD, DT_CENTER | DT_SINGLELINE);
    std::wstring status; { std::lock_guard<std::mutex> lock(g_status_mutex); status = g_status; }
    int y = S(104);
    if (g_page == Page::home) {
        RECT r = card(dc, left, y, width, S(150), L"ESTADO");
        write(dc, r.left + S(20), r.top + S(44), width - S(40), g_live.greeted ? L"Conectado con " + widen(g_live.peer) : L"Esperando al Mac", g_live.greeted ? kGreen : kOrange, 20, FW_BOLD, DT_SINGLELINE);
        write(dc, r.left + S(20), r.top + S(78), width - S(40), status, kSecondary, 13);
        r = card(dc, left, y, width, S(190), L"CÓMO SE USA");
        const wchar_t* steps[] = {L"1.  En el Mac: PRISON DISPLAY → PC con Windows → «Buscar y emparejar».",
                                   L"2.  Aquí aparecerá un código: acepta si es el mismo que ve el Mac.",
                                   L"3.  Lleva el ratón del Mac al borde elegido: pasará a este PC con el teclado.",
                                   L"4.  Para volver, regresa por el mismo borde o pulsa Ctrl+Opción+Esc en el Mac."};
        for (int i = 0; i < 4; ++i) write(dc, r.left + S(20), r.top + S(46) + i * S(32), width - S(40), steps[i], kText, 13, FW_NORMAL, DT_SINGLELINE | DT_END_ELLIPSIS);
    } else if (g_page == Page::connect) {
        RECT r = card(dc, left, y, width, S(150), L"EMPAREJAR (RECOMENDADO)");
        write(dc, r.left + S(20), r.top + S(44), width - S(40), L"En el Mac pulsa «Buscar y emparejar». Este PC se anuncia solo en la red; no hace falta escribir nada. Cuando aparezca el código, acepta si coincide en los dos equipos.", kText, 13);
        write(dc, r.left + S(20), r.top + S(104), width - S(40), L"Si Windows pregunta por el firewall, permite «Redes privadas».", kSecondary, 12, FW_NORMAL, DT_SINGLELINE);
        r = card(dc, left, y, width, S(220), L"O A MANO: ESCRIBE ESTO EN EL MAC");
        write(dc, r.left + S(20), r.top + S(44), S(160), L"Dirección", kSecondary, 12, FW_SEMIBOLD, DT_SINGLELINE);
        write(dc, r.left + S(20), r.top + S(64), width - S(40), g_addresses, kText, 20, FW_BOLD, DT_SINGLELINE);
        write(dc, r.left + S(20), r.top + S(102), S(160), L"Clave", kSecondary, 12, FW_SEMIBOLD, DT_SINGLELINE);
        write(dc, r.left + S(20), r.top + S(122), width - S(40), g_key, kText, 20, FW_BOLD, DT_SINGLELINE);
        button(dc, RECT{r.left + S(20), r.top + S(162), r.left + S(200), r.top + S(198)}, L"Copiar clave", kCopyKey, true);
        button(dc, RECT{r.left + S(214), r.top + S(162), r.left + S(394), r.top + S(198)}, L"Nueva clave", kNewKey, false);
    } else {
        RECT r = card(dc, left, y, width, S(222), L"QUÉ RECIBE ESTE PC DEL MAC");
        toggle(dc, r.left + S(20), r.top + S(48), width - S(40), L"Ratón", L"El ratón del Mac puede pasar a este PC.", g_options.mouse, kToggleMouse);
        toggle(dc, r.left + S(20), r.top + S(104), width - S(40), L"Teclado", L"Lo que escribes en el Mac llega aquí (⌘C → Ctrl+C, ⌥2 → @).", g_options.keyboard, kToggleKeyboard);
        toggle(dc, r.left + S(20), r.top + S(160), width - S(40), L"Portapapeles compartido", L"Copia en un equipo y pega en el otro (texto).", g_options.clipboard, kToggleClipboard);
        r = card(dc, left, y, width, S(166), L"ESTE PC");
        toggle(dc, r.left + S(20), r.top + S(48), width - S(40), L"Abrir al iniciar Windows", L"Se abre en la bandeja del sistema al encender el PC.", autostart_enabled(), kToggleAutostart);
        toggle(dc, r.left + S(20), r.top + S(104), width - S(40), L"Seguir funcionando al cerrar la ventana", L"Queda en la bandeja (junto al reloj). Clic derecho → Salir para cerrarla del todo.", g_options.tray, kToggleTray);
    }
}

// ---------- Tray ----------
NOTIFYICONDATAW g_tray{};
void tray_add(HWND window) {
    g_tray.cbSize = sizeof g_tray; g_tray.hWnd = window; g_tray.uID = 1; g_tray.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_tray.uCallbackMessage = kTrayMessage; g_tray.hIcon = app_icon();
    lstrcpynW(g_tray.szTip, L"PRISON DISPLAY", ARRAYSIZE(g_tray.szTip));
    Shell_NotifyIconW(NIM_ADD, &g_tray);
}
void notify(const std::wstring& title, const std::wstring& body) {
    NOTIFYICONDATAW n = g_tray; n.uFlags = NIF_INFO; n.dwInfoFlags = NIIF_INFO;
    lstrcpynW(n.szInfoTitle, title.c_str(), ARRAYSIZE(n.szInfoTitle)); lstrcpynW(n.szInfo, body.c_str(), ARRAYSIZE(n.szInfo));
    Shell_NotifyIconW(NIM_MODIFY, &n);
}
void show(HWND window) { ShowWindow(window, SW_SHOW); ShowWindow(window, SW_RESTORE); SetForegroundWindow(window); }

void start_server(const std::string& key);
void apply_options() {
    g_clipboard_on = g_options.clipboard;
    if (g_server) g_server->with_agent([](prison::InputAgent& agent) { agent.set_enabled(g_options.mouse, g_options.keyboard); });
    write_setting(L"Mouse", g_options.mouse); write_setting(L"Keyboard", g_options.keyboard);
    write_setting(L"Clipboard", g_options.clipboard); write_setting(L"Tray", g_options.tray);
}
void copy_text(HWND window, const std::wstring& value) {
    if (!OpenClipboard(window)) return;
    EmptyClipboard();
    if (HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, (value.size() + 1) * sizeof(wchar_t))) {
        if (auto* target = static_cast<wchar_t*>(GlobalLock(memory))) { std::copy(value.begin(), value.end(), target); target[value.size()] = L'\0'; GlobalUnlock(memory); if (!SetClipboardData(CF_UNICODETEXT, memory)) GlobalFree(memory); }
        else GlobalFree(memory);
    }
    CloseClipboard();
}
void click(HWND window, int id) {
    switch (id) {
    case kNavHome: g_page = Page::home; break;
    case kNavConnect: g_page = Page::connect; break;
    case kNavOptions: g_page = Page::options; break;
    case kCopyKey: copy_text(window, widen(g_key_raw)); set_status("Clave copiada. Pégala en el Mac si conectas a mano."); break;
    case kNewKey:
        if (MessageBoxW(window, L"Se creará una clave nueva y el Mac tendrá que emparejarse otra vez. ¿Continuar?", L"PRISON DISPLAY", MB_YESNO | MB_ICONQUESTION) == IDYES) {
            const auto file = data_folder() + L"\\clave-mac.bin"; DeleteFileW(file.c_str());
            g_key_raw = load_or_create_key(); g_key = widen(prison::grouped_key(g_key_raw)); start_server(g_key_raw);
        }
        break;
    case kToggleMouse: g_options.mouse = !g_options.mouse; apply_options(); break;
    case kToggleKeyboard: g_options.keyboard = !g_options.keyboard; apply_options(); break;
    case kToggleClipboard: g_options.clipboard = !g_options.clipboard; apply_options(); break;
    case kToggleAutostart: set_autostart(!autostart_enabled()); break;
    case kToggleTray: g_options.tray = !g_options.tray; apply_options(); break;
    }
    InvalidateRect(window, nullptr, FALSE);
}

void screen_size(std::uint32_t& width, std::uint32_t& height) {
    width = static_cast<std::uint32_t>(GetSystemMetrics(SM_CXVIRTUALSCREEN));
    height = static_cast<std::uint32_t>(GetSystemMetrics(SM_CYVIRTUALSCREEN));
}
void set_status(const std::string& text) {
    { std::lock_guard<std::mutex> lock(g_status_mutex); g_status = widen(text); }
    if (g_window) PostMessageW(g_window, kStatusMessage, 0, 0);
}
void start_server(const std::string& key) {
    if (g_thread.joinable()) { g_stop = true; g_thread.join(); }
    g_stop = false;
    std::uint32_t width = 0, height = 0; screen_size(width, height);
    g_server.reset();
    g_agent = std::make_unique<prison::InputAgent>(g_sink, narrow(g_name).empty() ? "PC con Windows" : narrow(g_name), kVersionUtf8, width, height);
    g_agent->set_enabled(g_options.mouse, g_options.keyboard);
    g_server = std::make_unique<prison::AgentServer>(*g_agent, key);
    g_server->confirm_pairing = [](const std::string& mac, const std::string& code) {
        PairingQuestion question{mac, code};
        if (g_window) SendMessageW(g_window, kConfirmPairing, 0, reinterpret_cast<LPARAM>(&question));
        return question.accepted;
    };
    g_thread = std::thread([] { if (!g_server->run(g_stop, set_status)) {} });
}

LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case WM_PAINT: {
        PAINTSTRUCT ps{}; HDC screen = BeginPaint(window, &ps);
        RECT bounds{}; GetClientRect(window, &bounds);
        // Double-buffered to avoid flicker.
        HDC dc = CreateCompatibleDC(screen); HBITMAP bitmap = CreateCompatibleBitmap(screen, bounds.right, bounds.bottom);
        auto old = SelectObject(dc, bitmap);
        paint(window, dc);
        BitBlt(screen, 0, 0, bounds.right, bounds.bottom, dc, 0, 0, SRCCOPY);
        SelectObject(dc, old); DeleteObject(bitmap); DeleteDC(dc);
        EndPaint(window, &ps);
        return 0;
    }
    case WM_ERASEBKGND: return 1;
    case WM_LBUTTONUP: {
        const POINT p{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
        for (const auto& hit : g_hits) if (PtInRect(&hit.rect, p)) { click(window, hit.id); break; }
        return 0;
    }
    case WM_SETCURSOR: {
        POINT p{}; GetCursorPos(&p); ScreenToClient(window, &p);
        for (const auto& hit : g_hits) if (PtInRect(&hit.rect, p)) { SetCursor(LoadCursorW(nullptr, MAKEINTRESOURCEW(32649))); return TRUE; }
        break;
    }
    case WM_DPICHANGED: {
        g_scale = HIWORD(wparam) / 96.0;
        const auto* r = reinterpret_cast<RECT*>(lparam);
        SetWindowPos(window, nullptr, r->left, r->top, r->right - r->left, r->bottom - r->top, SWP_NOZORDER | SWP_NOACTIVATE);
        return 0;
    }
    case WM_TIMER: {
        if (wparam == kRefreshTimer && g_server) {
            Live next; g_server->with_agent([&](prison::InputAgent& agent) { next.greeted = agent.greeted(); next.controlling = agent.controlling(); next.peer = agent.peer_name(); });
            if (next.greeted && !g_live.greeted) notify(L"Mac conectado", widen(next.peer) + L" ya puede usar este PC.");
            if (next.greeted != g_live.greeted || next.controlling != g_live.controlling || next.peer != g_live.peer) { g_live = next; InvalidateRect(window, nullptr, FALSE); }
        }
        return 0;
    }
    case kTrayMessage:
        if (LOWORD(lparam) == WM_LBUTTONUP || LOWORD(lparam) == WM_LBUTTONDBLCLK) show(window);
        else if (LOWORD(lparam) == WM_RBUTTONUP) {
            HMENU menu = CreatePopupMenu();
            AppendMenuW(menu, MF_STRING, 1, L"Abrir PRISON DISPLAY"); AppendMenuW(menu, MF_SEPARATOR, 0, nullptr); AppendMenuW(menu, MF_STRING, 2, L"Salir");
            POINT p{}; GetCursorPos(&p); SetForegroundWindow(window);
            const UINT choice = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, p.x, p.y, 0, window, nullptr);
            DestroyMenu(menu);
            if (choice == 1) show(window);
            if (choice == 2) DestroyWindow(window);
        }
        return 0;
    case WM_CLOSE:
        if (g_options.tray) {
            ShowWindow(window, SW_HIDE);
            static bool told = false;
            if (!told) { told = true; notify(L"PRISON DISPLAY sigue funcionando", L"Está en la bandeja, junto al reloj. Clic derecho → Salir para cerrarla."); }
            return 0;
        }
        DestroyWindow(window); return 0;
    case kStatusMessage: InvalidateRect(window, nullptr, FALSE); return 0;
    case kConfirmPairing: {
        auto* question = reinterpret_cast<PairingQuestion*>(lparam);
        show(window);
        const std::string code = question->code.substr(0, 3) + " " + question->code.substr(3);
        const std::wstring body = L"El Mac «" + widen(question->mac) + L"» quiere usar este PC con su ratón, teclado y portapapeles.\n\n"
            L"Código: " + widen(code) + L"\n\n¿Es el mismo código que muestra el Mac?";
        question->accepted = MessageBoxW(window, body.c_str(), L"PRISON DISPLAY · Emparejar con un Mac", MB_YESNO | MB_ICONQUESTION | MB_SETFOREGROUND | MB_TOPMOST) == IDYES;
        return 0;
    }
    case kSetClipboard: {
        if (!g_clipboard_on) return 0;
        const auto& value = *reinterpret_cast<const std::string*>(lparam);
        copy_text(window, widen(value));
        g_sink.seen_ = GetClipboardSequenceNumber(); // Not echoed back to the Mac.
        return 0;
    }
    case WM_DISPLAYCHANGE: {
        std::uint32_t width = 0, height = 0; screen_size(width, height);
        if (g_server) g_server->with_agent([&](prison::InputAgent& agent) { agent.set_screen(width, height); });
        return 0;
    }
    case WM_DESTROY:
        Shell_NotifyIconW(NIM_DELETE, &g_tray);
        g_stop = true;
        if (g_thread.joinable()) g_thread.join();
        PostQuitMessage(0);
        return 0;
    default: return DefWindowProcW(window, message, wparam, lparam);
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR command, int show_mode) {
    g_instance = instance;
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
        if (HWND existing = FindWindowW(kClassName, nullptr)) { ShowWindow(existing, SW_SHOW); ShowWindow(existing, SW_RESTORE); SetForegroundWindow(existing); }
        return 0;
    }
    wchar_t computer[MAX_COMPUTERNAME_LENGTH + 1] = {}; DWORD length = MAX_COMPUTERNAME_LENGTH + 1;
    GetComputerNameW(computer, &length); g_name = computer;
    g_options.mouse = read_setting(L"Mouse", true); g_options.keyboard = read_setting(L"Keyboard", true);
    g_options.clipboard = read_setting(L"Clipboard", true); g_options.tray = read_setting(L"Tray", true);
    g_clipboard_on = g_options.clipboard;
    g_key_raw = load_or_create_key();
    g_key = widen(prison::grouped_key(g_key_raw));
    g_addresses = local_addresses();

    WNDCLASSW klass{}; klass.hInstance = instance; klass.lpfnWndProc = window_proc; klass.lpszClassName = kClassName;
    klass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)); klass.hIcon = app_icon();
    if (!RegisterClassW(&klass)) return 1;
    using DpiForSystem = UINT(WINAPI*)();
    if (auto dpi = reinterpret_cast<DpiForSystem>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForSystem"))) g_scale = dpi() / 96.0;
    g_window = CreateWindowExW(0, kClassName, L"PRISON DISPLAY · PC con Windows", WS_OVERLAPPEDWINDOW,
                               CW_USEDEFAULT, CW_USEDEFAULT, S(980), S(640), nullptr, nullptr, instance, nullptr);
    if (!g_window) return 1;
    tray_add(g_window);
    start_server(g_key_raw);
    SetTimer(g_window, kRefreshTimer, 1000, nullptr);
    const bool hidden = command && std::wstring(command).find(L"--bandeja") != std::wstring::npos;
    if (!hidden) { ShowWindow(g_window, show_mode); UpdateWindow(g_window); }
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
    if (single) CloseHandle(single);
    WSACleanup();
    return static_cast<int>(message.wParam);
}
#endif
