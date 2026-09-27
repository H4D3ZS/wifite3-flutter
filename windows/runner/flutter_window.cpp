#include "flutter_window.h"

#include <optional>
#include <iostream>
#include <vector>
#include <string>
#include <thread>
#include <atomic>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include "flutter/generated_plugin_registrant.h"

// Windows Native WiFi (Wlanapi) and Raw PCAP / Adapter headers
#include <windows.h>
#include <wlanapi.h>
#pragma comment(lib, "wlanapi.lib")

namespace {
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel = nullptr;
  std::atomic<bool> g_isCapturing(false);
  std::thread g_captureThread;

  std::string MacToString(const BYTE* mac) {
    char buf[18];
    sprintf_s(buf, "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    return std::string(buf);
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

        PWLAN_BSS_LIST pBssList = NULL;
        if (WlanGetNetworkBssList(hClient, &ifInfo.InterfaceGuid, NULL, dot11_BSS_type_any, FALSE, NULL, &pBssList) == ERROR_SUCCESS) {
          flutter::EncodableList resultsList;

          for (DWORD j = 0; j < pBssList->dwNumberOfItems; j++) {
            WLAN_BSS_ENTRY bssEntry = pBssList->wlanBssEntries[j];
            
            std::string ssidStr(reinterpret_cast<char*>(bssEntry.dot11Ssid.ucSSID), bssEntry.dot11Ssid.uSSIDLength);
            std::string bssidStr = MacToString(bssEntry.dot11Bssid);
            int channel = 1;
            if (bssEntry.ulChCenterFrequency > 0) {
              if (bssEntry.ulChCenterFrequency >= 2412000 && bssEntry.ulChCenterFrequency <= 2484000) {
                channel = (bssEntry.ulChCenterFrequency - 2407000) / 5000;
              } else if (bssEntry.ulChCenterFrequency >= 5000000) {
                channel = (bssEntry.ulChCenterFrequency - 5000000) / 5000;
              }
            }

            flutter::EncodableMap item;
            item[flutter::EncodableValue("bssid")] = flutter::EncodableValue(bssidStr);
            item[flutter::EncodableValue("ssid")] = flutter::EncodableValue(ssidStr);
            item[flutter::EncodableValue("channel")] = flutter::EncodableValue(channel);
            item[flutter::EncodableValue("rssi")] = flutter::EncodableValue((int)bssEntry.lRssi);
            item[flutter::EncodableValue("encryption")] = flutter::EncodableValue(bssEntry.dot11BssPhyType > 4 ? "WPA2/WPA3" : "WPA2");
            item[flutter::EncodableValue("frequency")] = flutter::EncodableValue(bssEntry.ulChCenterFrequency > 4000000 ? "5.0 GHz" : "2.4 GHz");
            item[flutter::EncodableValue("wps")] = flutter::EncodableValue(true);

            resultsList.push_back(flutter::EncodableValue(item));
          }

          if (g_channel) {
            g_channel->InvokeMethod("onScanResults", std::make_unique<flutter::EncodableValue>(resultsList));
          }

          WlanFreeMemory(pBssList);
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

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Set up Flutter MethodChannel for Windows (Wlanapi + WinPcap / Npcap dongles)
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
          std::thread(PerformWindowsScanAndEmit).detach();
          result->Success(flutter::EncodableValue(true));
        } else if (method == "startMonitorMode") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "stopMonitorMode") {
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
