# 🛡️ WiFite3 Flutter Cross-Platform Engine (2026 Edition)

A state-of-the-art, cross-platform Wi-Fi security auditing, analysis, and educational penetration testing suite built with **Flutter**, **Clean Architecture / DDD**, and high-performance native drivers (**C++ Win32 / Wlanapi / Npcap**, **Android Kali NetHunter Root**, and **iOS Apple80211 / RTL8192EU Objective-C++**).

> ⚠️ **DISCLAIMER & AUTHORIZED USE ONLY**  
> WiFite3 is designed strictly for **authorized security auditing**, network resilience testing, and educational research on owned or explicitly authorized equipment. Unauthorized access or disruption of third-party wireless networks is strictly illegal and violates cyber safety regulations.

---

## 🌟 Key Features & Capabilities

- **📱 Multi-Platform Architecture**:
  - 🍏 **iOS (Jailbroken / TrollStore)**: Direct kernel-level USB interaction with Realtek RTL8192EU dongles (`Rtl8192eudriver.mm`).
  - 🤖 **Android (Infinix Zero 5G 2023 & Rooted NetHunter)**: Native `su -c` execution engine (`MainActivity.kt`) running `iw`, `tcpdump`, and `aireplay-ng`.
  - 💻 **Windows Desktop (10/11)**: Native C++ engine (`flutter_window.cpp`) interfacing directly with `Wlanapi.dll` and **Npcap** for dual-USB adapter injection (**TL-WN823N** & **PW-DN421**).
- **⚡ Dual-Dongle Fluxion-NG 2026 Engine**:
  - Automatically splits duties across two attached USB dongles (Interface 1 for continuous Deauth Jamming & Interface 2 for Rogue SoftAP & Responsive Captive Portal HTTP / DNS server).
- **🔒 WPA3-SAE & Dragonblood Side-Channel Audit**:
  - 802.11w Protected Management Frame (PMF) auditing and SAE Commit (Auth Algo 3, ECDH P-256) timing analysis.
- **🎯 PMKID Client-less Harvest Attack**:
  - Client-less Auth/Assoc frame injection to capture EAPOL M1 PMKID Key Data Elements without connected clients.
- **🔑 Multi-Algorithm WPS PIN Engine**:
  - Computes candidate WPS PINs using Broadcom (`pin24`), D-Link (`pinDlink`), ASUS (`pinAsus`), and 3WiFi database algorithms.
- **🔄 WEP ARP Replay Engine**:
  - Continuous 802.11 ARP request re-injection for rapid IV generation.
- **🔍 Hidden SSID Decloaking**:
  - Real-time 802.11 Management Beacon/Probe IE Tag 0 extraction.

---

## 🏗️ Clean Architecture / DDD Design

```
lib/
├── domain/                    # Enterprise Domain Core (Entities & Pure Interfaces)
│   ├── entities/              # AccessPoint, CapturedFrame, BackendInfo
│   ├── repositories/          # WifiRepository contract interface
│   └── usecases/              # Pure Business Logic (PMKID, Deauth, WPA3-SAE, EvilTwin, AutoPwn)
├── data/                      # Infrastructure Implementation
│   ├── datasources/           # NativeBridge platform channels
│   └── repositories/          # WifiRepositoryImpl hardware mapping
└── presentation/              # High-Tech Cyber UI
    ├── viewmodels/            # ChangeNotifier ViewModels (State Holders)
    └── screens/               # Mobile Responsive Screens (ScannerScreen, TargetScreen, AutoPwnScreen, EvilTwinScreen)
```

---

## 🔌 Hardware Compatibility Matrix

| Platform | Interface / Method | Injection Support | Supported Adapters |
| :--- | :--- | :---: | :--- |
| **Windows 10/11** | Npcap / WinPcap & Wlanapi.dll | ✅ Yes | TP-Link TL-WN823N, PW-DN421 (Atheros), RTL8192EU |
| **Android (NetHunter)** | Root `su -c` (`iw`, `tcpdump`, `aireplay-ng`) | ✅ Yes | Internal `wlan0mon` or OTG USB Adapters |
| **iOS (TrollStore)** | Native USB Host Driver | ✅ Yes | Realtek RTL8192EU |

---

## 🛠️ Windows Dual-Dongle Setup Guide

To enable raw 802.11 monitor mode and packet injection on Windows with your **TP-Link TL-WN823N** and **PW-DN421**:
1. Download and install [Npcap](https://npcap.com/#download).
2. During installation, **check the box**: `"Support raw 802.11 traffic (and monitor mode) for wireless adapters"`.
3. **Restart your Windows PC**.
4. Launch the application:
   ```bash
   flutter run -d windows
   ```

---

## 🤝 Contributing & License

Licensed under the MIT License. Contributions and security pull requests are welcome!
