#include <windows.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <MinHook.h>

#include <array>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace
{
using create_process_w_fn = BOOL(WINAPI *)(LPCWSTR, LPWSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES,
    BOOL, DWORD, LPVOID, LPCWSTR, LPSTARTUPINFOW, LPPROCESS_INFORMATION);

create_process_w_fn g_create_process_w = nullptr;
std::filesystem::path g_launcher_directory;
std::filesystem::path g_game_executable;
constexpr wchar_t expected_launcher_hash[] = L"DAF16D8A6C2A4E0E4480D08D865EB9F6A445A05CF1F238EB2D4391048E35A561";
constexpr wchar_t expected_game_hash[] = L"9E8DF67EA7F41E7F8306CE1A77584707209069B3C75389B3F00445EFE459FE41";

std::filesystem::path module_path(HMODULE module)
{
    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetModuleFileNameW(module, buffer.data(), static_cast<DWORD>(buffer.size()));
    return length > 0 && length < buffer.size() ? std::filesystem::path(std::wstring(buffer.data(), length)) : std::filesystem::path();
}

void log_line(const std::string &message)
{
    std::ofstream log(g_launcher_directory / L"MGS4FastBoot.log", std::ios::out | std::ios::app);
    if (log)
        log << message << '\n';
}

std::wstring sha256_file(const std::filesystem::path &path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input)
        return {};

    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    std::array<unsigned char, 32> digest = {};
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0)
        return {};
    if (BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0)
    {
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return {};
    }

    std::vector<char> buffer(64 * 1024);
    bool success = true;
    while (input)
    {
        input.read(buffer.data(), buffer.size());
        const std::streamsize count = input.gcount();
        if (count > 0 && BCryptHashData(hash, reinterpret_cast<unsigned char *>(buffer.data()), static_cast<ULONG>(count), 0) < 0)
        {
            success = false;
            break;
        }
    }
    if (success)
        success = BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0;
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    if (!success)
        return {};

    std::wostringstream encoded;
    encoded << std::hex << std::uppercase << std::setfill(L'0');
    for (const unsigned char byte : digest)
        encoded << std::setw(2) << static_cast<unsigned int>(byte);
    return encoded.str();
}

bool supported_build(const std::filesystem::path &launcher_executable)
{
    return sha256_file(launcher_executable) == expected_launcher_hash && sha256_file(g_game_executable) == expected_game_hash;
}

bool equals_path(const std::filesystem::path &left, const std::filesystem::path &right)
{
    return _wcsicmp(left.lexically_normal().c_str(), right.lexically_normal().c_str()) == 0;
}

std::filesystem::path process_application_path(LPCWSTR application_name, LPCWSTR command_line)
{
    std::filesystem::path application;
    if (application_name != nullptr && application_name[0] != L'\0')
    {
        application = application_name;
    }
    else if (command_line != nullptr)
    {
        int argument_count = 0;
        LPWSTR *arguments = CommandLineToArgvW(command_line, &argument_count);
        if (arguments != nullptr && argument_count > 0)
            application = arguments[0];
        if (arguments != nullptr)
            LocalFree(arguments);
    }

    if (application.empty())
        return {};
    if (application.is_relative())
        application = g_launcher_directory / application;
    return application.lexically_normal();
}

bool has_main_menu_flag(const std::wstring &command_line)
{
    std::wstring lowered = command_line;
    for (wchar_t &value : lowered)
        value = static_cast<wchar_t>(towlower(value));
    return lowered.find(L"--skip-to-main-menu") != std::wstring::npos;
}

BOOL WINAPI on_create_process_w(LPCWSTR application_name, LPWSTR command_line,
    LPSECURITY_ATTRIBUTES process_attributes, LPSECURITY_ATTRIBUTES thread_attributes,
    BOOL inherit_handles, DWORD creation_flags, LPVOID environment, LPCWSTR current_directory,
    LPSTARTUPINFOW startup_info, LPPROCESS_INFORMATION process_information)
{
    const std::filesystem::path application = process_application_path(application_name, command_line);
    if (!application.empty() && equals_path(application, g_game_executable) && sha256_file(application) == expected_game_hash)
    {
        std::wstring official_arguments = command_line != nullptr ? command_line : L"";
        if (!has_main_menu_flag(official_arguments))
        {
            std::wstring fast_boot_arguments = official_arguments;
            if (!fast_boot_arguments.empty() && !iswspace(fast_boot_arguments.back()))
                fast_boot_arguments.push_back(L' ');
            fast_boot_arguments += L"--skip-to-main-menu";
            std::vector<wchar_t> mutable_arguments(fast_boot_arguments.begin(), fast_boot_arguments.end());
            mutable_arguments.push_back(L'\0');
            log_line("Official launcher settings preserved; appended --skip-to-main-menu.");
            return g_create_process_w(application_name, mutable_arguments.data(), process_attributes, thread_attributes,
                inherit_handles, creation_flags, environment, current_directory, startup_info, process_information);
        }
    }

    return g_create_process_w(application_name, command_line, process_attributes, thread_attributes,
        inherit_handles, creation_flags, environment, current_directory, startup_info, process_information);
}

bool is_direct_game_start(int argument_count, LPWSTR *arguments)
{
    return argument_count == 3 &&
        _wcsicmp(arguments[1], L"-jump") == 0 &&
        _wcsicmp(arguments[2], L"directGameStart") == 0;
}

bool install_process_hook()
{
    HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    void *target = kernel32 != nullptr ? reinterpret_cast<void *>(GetProcAddress(kernel32, "CreateProcessW")) : nullptr;
    if (target == nullptr)
        return false;
    if (MH_Initialize() != MH_OK)
        return false;
    if (MH_CreateHook(target, reinterpret_cast<void *>(&on_create_process_w), reinterpret_cast<void **>(&g_create_process_w)) != MH_OK)
        return false;
    return MH_EnableHook(target) == MH_OK;
}

DWORD WINAPI fast_boot_thread(void *)
{
    const std::filesystem::path launcher_executable = module_path(nullptr);
    g_launcher_directory = launcher_executable.parent_path();
    g_game_executable = (g_launcher_directory.parent_path() / L"MGS4" / L"mgs4.exe").lexically_normal();
    const std::filesystem::path config_path = g_launcher_directory / L"MGS4FastBoot.ini";

    if (_wcsicmp(launcher_executable.filename().c_str(), L"launcher.exe") != 0)
        return 0;

    int argument_count = 0;
    LPWSTR *arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
    if (arguments == nullptr)
        return 0;

    const bool direct_game_start = is_direct_game_start(argument_count, arguments);
    LocalFree(arguments);

    if (direct_game_start)
    {
        if (!supported_build(launcher_executable))
        {
            log_line("Direct launch child is an unsupported build; continuing without interception.");
            return 0;
        }
        if (GetPrivateProfileIntW(L"FastBoot", L"SkipToMainMenu", 1, config_path.c_str()) != 0 && install_process_hook())
            log_line("Direct launch child armed; waiting for the official MGS4 process request.");
        else
            log_line("Direct launch child continues through the official path without the main-menu hook.");
        return 0;
    }

    if (argument_count != 1)
    {
        log_line("Fast Boot bypassed: explicit launcher arguments are owned by the official launcher.");
        return 0;
    }

    Sleep(150);
    if ((GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0)
    {
        log_line("Fast Boot bypassed: Shift override is active.");
        return 0;
    }
    if (GetPrivateProfileIntW(L"FastBoot", L"Enabled", 1, config_path.c_str()) == 0)
    {
        log_line("Fast Boot bypassed: disabled in configuration.");
        return 0;
    }
    if (!supported_build(launcher_executable))
    {
        log_line("Fast Boot bypassed: launcher or game executable hash is unsupported.");
        MessageBoxW(nullptr, L"Fast Boot refused an unsupported MGS4 build. The official launcher will continue.", L"MGS4 Fast Boot", MB_OK | MB_ICONWARNING);
        return 0;
    }

    std::wstring child_command_line = L"\"" + launcher_executable.wstring() + L"\" -jump directGameStart";
    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process = {};
    if (!CreateProcessW(launcher_executable.c_str(), child_command_line.data(), nullptr, nullptr, FALSE, 0,
        nullptr, g_launcher_directory.c_str(), &startup, &process))
    {
        log_line("Fast Boot relaunch failed; continuing through the visible official launcher.");
        return 0;
    }

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    log_line("Relaunched the official settings path with -jump directGameStart.");
    ExitProcess(0);
}
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(module);
        HANDLE thread = CreateThread(nullptr, 0, fast_boot_thread, nullptr, 0, nullptr);
        if (thread == nullptr)
            return FALSE;
        CloseHandle(thread);
    }
    return TRUE;
}
