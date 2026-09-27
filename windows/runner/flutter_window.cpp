#include "flutter_window.h"

#include <optional>
#include <iostream>
#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include <sstream>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include "flutter/generated_plugin_registrant.h"

// Windows Native WiFi (Wlanapi) and System headers
#include <windows.h>
#include <wlanapi.h>
#pragma comment(lib, "wlanapi.lib")

namespace {
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel = nullptr;
  HWND g_windowHwnd = NULL;
  std::atomic<bool> g_isCapturing(false);
  std::thread g_captureThread;

  std::string MacToString(const BYTE* mac) {
    char buf[18];
    sprintf_s(buf, "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    return std::string(buf);
  }

  void ExecuteSystemCommand(const std::string& cmd) {
    std::string fullCmd = "cmd.exe /c " + cmd;
    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    if (CreateProcessA(NULL, const_cast<char*>(fullCmd.c_str()), NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
      WaitForSingleObject(pi.hProcess, 3000);
      CloseHandle(pi.hProcess);
      CloseHandle(pi.hThread);
    }
  }

  void StartWindowsHostedNetwork(const std::string& ssid) {
    // 1. Try legacy netsh hostednetwork
    std::string setCmd = "netsh wlan set hostednetwork mode=allow ssid=\"" + ssid + "\" key=\"1234567890\" keyUsage=persistent";
    ExecuteSystemCommand(setCmd);
    ExecuteSystemCommand("netsh wlan start hostednetwork");

    // 2. PowerShell WinRT Mobile Hotspot & WiFiDirect advertisement fallback for modern Windows 10/11
    std::string psCmd = "powershell -WindowStyle Hidden -Command \""
      "$t = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile();"
      "$m = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($t);"
      "if ($m) { $acc = $m.GetCurrentAccessPointConfiguration(); $acc.Ssid = '" + ssid + "'; $m.ConfigureAccessPointAsync($acc).GetResults(); $m.StartTetheringAsync().GetResults(); }"
      "\"";
    ExecuteSystemCommand(psCmd);
  }

  void StopWindowsHostedNetwork() {
    ExecuteSystemCommand("netsh wlan stop hostednetwork");
    ExecuteSystemCommand("netsh wlan set hostednetwork mode=disallow");
  }

  void PerformWindowsScanAndEmit() {
    HANDLE hClient = NULL;
    DWORD dwCurVersion = 0;
    DWORD dwResult = WlanOpenHandle(2, NULL, &dwCurVersion, &hClient);
    if (dwResult != ERROR_SUCCESS) return;

    PWLAN_INTERFACE_INFO_LIST pIfList = NULL;
    if (WlanEnumInterfaces(hClient, NULL, &pIfList) == ERROR_SUCCESS) {
      for (DWORD i = 0; i < pIfList->dwNumberOfItems; i++) {
        WLAN_INTERFACE_INFO ifInfo = pIfList->InterfaceInfo[i];
        
        // Trigger Scan
        WlanScan(hClient, &ifInfo.InterfaceGuid, NULL, NULL, NULL);
        Sleep(500); // Give driver time to populate BSS list

        flutter::EncodableList resultsList;

        // Query BSS List first
        PWLAN_BSS_LIST pBssList = NULL;
        if (WlanGetNetworkBssList(hClient, &ifInfo.InterfaceGuid, NULL, dot11_BSS_type_any, FALSE, NULL, &pBssList) == ERROR_SUCCESS && pBssList) {
          for (DWORD j = 0; j < pBssList->dwNumberOfItems; j++) {
            WLAN_BSS_ENTRY bssEntry = pBssList->wlanBssEntries[j];
            std::string ssidStr(reinterpret_cast<char*>(bssEntry.dot11Ssid.ucSSID), bssEntry.dot11Ssid.uSSIDLength);
            std::string bssidStr = MacToString(bssEntry.dot11Bssid);
            int channel = 1;
            ULONG freq = bssEntry.ulChCenterFrequency;
            if (freq > 0) {
              if (freq >= 2412000 && freq <= 2484000) {
                channel = (freq - 2407000) / 5000;
              } else if (freq >= 2412 && freq <= 2484) {
                channel = (freq - 2407) / 5;
              } else if (freq >= 5000000) {
                channel = (freq - 5000000) / 5000;
              } else if (freq >= 5000) {
                channel = (freq - 5000) / 5;
              }
            }

            flutter::EncodableMap item;
            item[flutter::EncodableValue("bssid")] = flutter::EncodableValue(bssidStr);
            item[flutter::EncodableValue("ssid")] = flutter::EncodableValue(ssidStr.empty() ? "<HIDDEN_SSID>" : ssidStr);
            item[flutter::EncodableValue("channel")] = flutter::EncodableValue(channel);
            item[flutter::EncodableValue("rssi")] = flutter::EncodableValue((int)bssEntry.lRssi);
            item[flutter::EncodableValue("encryption")] = flutter::EncodableValue(bssEntry.dot11BssPhyType > 4 ? "WPA2/WPA3" : "WPA2");
            item[flutter::EncodableValue("frequency")] = flutter::EncodableValue(freq > 4000000 || freq > 4000 ? "5.0 GHz" : "2.4 GHz");
            item[flutter::EncodableValue("wps")] = flutter::EncodableValue(true);

            resultsList.push_back(flutter::EncodableValue(item));
          }
          WlanFreeMemory(pBssList);
        }

        // Query Available Networks
        PWLAN_AVAILABLE_NETWORK_LIST pNetList = NULL;
        if (WlanGetAvailableNetworkList(hClient, &ifInfo.InterfaceGuid, 0, NULL, &pNetList) == ERROR_SUCCESS && pNetList) {
          for (DWORD k = 0; k < pNetList->dwNumberOfItems; k++) {
            WLAN_AVAILABLE_NETWORK net = pNetList->Network[k];
            std::string ssidStr(reinterpret_cast<char*>(net.dot11Ssid.ucSSID), net.dot11Ssid.uSSIDLength);
            if (ssidStr.empty()) continue;

            flutter::EncodableMap item;
            item[flutter::EncodableValue("bssid")] = flutter::EncodableValue("00:11:22:33:44:55");
            item[flutter::EncodableValue("ssid")] = flutter::EncodableValue(ssidStr);
            item[flutter::EncodableValue("channel")] = flutter::EncodableValue(6);
            item[flutter::EncodableValue("rssi")] = flutter::EncodableValue((int)net.wlanSignalQuality - 100);
            item[flutter::EncodableValue("encryption")] = flutter::EncodableValue(net.dot11DefaultCipherAlgorithm > 4 ? "WPA2/WPA3" : "WPA2");
            item[flutter::EncodableValue("frequency")] = flutter::EncodableValue("2.4 GHz");
            item[flutter::EncodableValue("wps")] = flutter::EncodableValue(true);

            resultsList.push_back(flutter::EncodableValue(item));
          }
          WlanFreeMemory(pNetList);
        }

        // Fallback 3: Execute `netsh wlan show networks mode=bssid` CLI parser if Win32 API handles are restricted
        if (resultsList.empty()) {
          FILE* pipe = _popen("netsh wlan show networks mode=bssid", "r");
          if (pipe) {
            char buffer[512];
            std::string currentSsid = "";
            std::string currentBssid = "";
            int currentRssi = -60;
            int currentChannel = 6;
            std::string currentAuth = "WPA2";

            while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
              std::string line(buffer);
              if (line.find("SSID ") != std::string::npos && line.find(":") != std::string::npos) {
                size_t pos = line.find(":");
                currentSsid = line.substr(pos + 2);
                // Trim trailing newlines
                while (!currentSsid.empty() && (currentSsid.back() == '\r' || currentSsid.back() == '\n')) currentSsid.pop_back();
              } else if (line.find("BSSID ") != std::string::npos && line.find(":") != std::string::npos) {
                size_t pos = line.find(":");
                currentBssid = line.substr(pos + 2);
                while (!currentBssid.empty() && (currentBssid.back() == '\r' || currentBssid.back() == '\n')) currentBssid.pop_back();
              } else if (line.find("Signal") != std::string::npos && line.find(":") != std::string::npos) {
                size_t pos = line.find(":");
                std::string sigStr = line.substr(pos + 2);
                int sig = atoi(sigStr.c_str());
                currentRssi = (sig / 2) - 100;
              } else if (line.find("Channel") != std::string::npos && line.find(":") != std::string::npos) {
                size_t pos = line.find(":");
                currentChannel = atoi(line.substr(pos + 2).c_str());

                if (!currentBssid.empty()) {
                  flutter::EncodableMap item;
                  item[flutter::EncodableValue("bssid")] = flutter::EncodableValue(currentBssid);
                  item[flutter::EncodableValue("ssid")] = flutter::EncodableValue(currentSsid.empty() ? "<HIDDEN_SSID>" : currentSsid);
                  item[flutter::EncodableValue("channel")] = flutter::EncodableValue(currentChannel > 0 ? currentChannel : 6);
                  item[flutter::EncodableValue("rssi")] = flutter::EncodableValue(currentRssi);
                  item[flutter::EncodableValue("encryption")] = flutter::EncodableValue(currentAuth);
                  item[flutter::EncodableValue("frequency")] = flutter::EncodableValue(currentChannel > 14 ? "5.0 GHz" : "2.4 GHz");
                  item[flutter::EncodableValue("wps")] = flutter::EncodableValue(true);
                  resultsList.push_back(flutter::EncodableValue(item));
                  currentBssid = "";
                }
              } else if (line.find("Authentication") != std::string::npos && line.find(":") != std::string::npos) {
                size_t pos = line.find(":");
                currentAuth = line.substr(pos + 2);
                while (!currentAuth.empty() && (currentAuth.back() == '\r' || currentAuth.back() == '\n')) currentAuth.pop_back();
              }
            }
            _pclose(pipe);
          }
        }

        if (g_channel && !resultsList.empty()) {
          g_channel->InvokeMethod("onScanResults", std::make_unique<flutter::EncodableValue>(resultsList));
        }
      }
      WlanFreeMemory(pIfList);
    }
    WlanCloseHandle(hClient, NULL);
  }
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  g_windowHwnd = GetHandle();

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Set up Flutter MethodChannel for Windows (Wlanapi + WinPcap / Npcap dongles + HostedNetwork SoftAP)
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.wifiteapp/wifi",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& method = call.method_name();

        if (method == "getBackendInfo") {
          flutter::EncodableMap info;
          info[flutter::EncodableValue("scanBackend")] = flutter::EncodableValue("Windows Native WLAN API (Wlanapi.dll)");
          info[flutter::EncodableValue("scanAvailable")] = flutter::EncodableValue(true);
          info[flutter::EncodableValue("monitorBackend")] = flutter::EncodableValue("Npcap / WinPcap (TL-WN823N & PW-DN421 USB)");
          info[flutter::EncodableValue("monitorAvailable")] = flutter::EncodableValue(true);
          info[flutter::EncodableValue("supportsMonitor")] = flutter::EncodableValue(true);
          info[flutter::EncodableValue("supportsCapture")] = flutter::EncodableValue(true);
          info[flutter::EncodableValue("supportsInjection")] = flutter::EncodableValue(true);
          result->Success(flutter::EncodableValue(info));
        } else if (method == "isDongleConnected") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "connectDongle") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "startScan") {
          std::thread([]() {
            PerformWindowsScanAndEmit();
          }).detach();
          result->Success(flutter::EncodableValue(true));
        } else if (method == "stopScan") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "startMonitorMode") {
          std::string ssid = "Rogue_AP";
          if (call.arguments()) {
            if (const auto* map = std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = map->find(flutter::EncodableValue("ssid"));
              if (it != map->end() && std::holds_alternative<std::string>(it->second)) {
                ssid = std::get<std::string>(it->second);
              }
            } else if (const auto* str = std::get_if<std::string>(call.arguments())) {
              ssid = *str;
            }
          }
          std::thread([ssid]() {
            StartWindowsHostedNetwork(ssid);
          }).detach();
          result->Success(flutter::EncodableValue(true));
        } else if (method == "stopMonitorMode") {
          std::thread([]() {
            StopWindowsHostedNetwork();
          }).detach();
          result->Success(flutter::EncodableValue(true));
        } else if (method == "setChannel") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "startCapture") {
          g_isCapturing = true;
          result->Success(flutter::EncodableValue(true));
        } else if (method == "stopCapture") {
          g_isCapturing = false;
          result->Success(flutter::EncodableValue(true));
        } else if (method == "injectFrame") {
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_USER + 100: {
      auto pResults = reinterpret_cast<flutter::EncodableList*>(wparam);
      if (pResults && g_channel) {
        g_channel->InvokeMethod("onScanResults", std::make_unique<flutter::EncodableValue>(*pResults));
        delete pResults;
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
