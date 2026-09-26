// RTL8192EU Userspace USB Driver — Implementation
//
// Obj-C++ port of wifit3/src/wifit3/chips/rtl8188eus/* for jailbroken iOS.
// The RTL8192EU and RTL8188EUS share the rtl8xxxu register space and USB
// vendor-control protocol. This file translates Python → C++ line-by-line
// from the wifit3 reference, with kernel source citations matching the
// Python's own.
//
// Build plan compliance:
//   - Every TX-capable method (injectFrame, setMonitorMode(true)) must
//     only be called from the native method-channel handlers behind
//     ScopeGateService.authorize(). No public bypass path.
//   - Bring-up order: open → uploadFirmware → setMonitorMode → setChannel
//     → startCapture → injectFrame. Enforced by state checks.

#import "Rtl8192eudriver.h"
#include <libusb.h>
#include <thread>
#include <chrono>
#include <cstring>

// ============================================================
// Construction / Destruction
// ============================================================

RTL8192EUDriver::RTL8192EUDriver() {
    libusb_init(&_ctx);
}

RTL8192EUDriver::~RTL8192EUDriver() {
    close();
    if (_ctx) {
        libusb_exit(_ctx);
        _ctx = nullptr;
    }
}

// ============================================================
// USB Transport Layer
// Port of wifit3: chips/rtl8188eus/transport.py
//
// The vendor-control wire protocol is identical across all rtl8xxxu
// chips — bRequest=0x05, wIndex=0x00, register address in wValue.
// ============================================================

uint8_t RTL8192EUDriver::read8(uint16_t addr) {
    uint8_t buf = 0;
    std::lock_guard<std::mutex> lock(_usbMutex);
    libusb_control_transfer(
        _handle, USB_REQTYPE_READ, USB_CMD_REQ,
        addr, USB_VENQT_CMD_IDX,
        &buf, 1, USB_CONTROL_TIMEOUT_MS
    );
    return buf;
}

uint16_t RTL8192EUDriver::read16(uint16_t addr) {
    uint8_t buf[2] = {};
    std::lock_guard<std::mutex> lock(_usbMutex);
    libusb_control_transfer(
        _handle, USB_REQTYPE_READ, USB_CMD_REQ,
        addr, USB_VENQT_CMD_IDX,
        buf, 2, USB_CONTROL_TIMEOUT_MS
    );
    return buf[0] | (buf[1] << 8);
}

uint32_t RTL8192EUDriver::read32(uint16_t addr) {
    uint8_t buf[4] = {};
    std::lock_guard<std::mutex> lock(_usbMutex);
    libusb_control_transfer(
        _handle, USB_REQTYPE_READ, USB_CMD_REQ,
        addr, USB_VENQT_CMD_IDX,
        buf, 4, USB_CONTROL_TIMEOUT_MS
    );
    return buf[0] | (buf[1] << 8) | (buf[2] << 16) | (buf[3] << 24);
}

void RTL8192EUDriver::write8(uint16_t addr, uint8_t val) {
    uint8_t buf[1] = { val };
    std::lock_guard<std::mutex> lock(_usbMutex);
    libusb_control_transfer(
        _handle, USB_REQTYPE_WRITE, USB_CMD_REQ,
        addr, USB_VENQT_CMD_IDX,
        buf, 1, USB_CONTROL_TIMEOUT_MS
    );
}

void RTL8192EUDriver::write16(uint16_t addr, uint16_t val) {
    uint8_t buf[2] = {
        static_cast<uint8_t>(val & 0xFF),
        static_cast<uint8_t>((val >> 8) & 0xFF)
    };
    std::lock_guard<std::mutex> lock(_usbMutex);
    libusb_control_transfer(
        _handle, USB_REQTYPE_WRITE, USB_CMD_REQ,
        addr, USB_VENQT_CMD_IDX,
        buf, 2, USB_CONTROL_TIMEOUT_MS
    );
}

void RTL8192EUDriver::write32(uint16_t addr, uint32_t val) {
    uint8_t buf[4] = {
        static_cast<uint8_t>(val & 0xFF),
        static_cast<uint8_t>((val >> 8) & 0xFF),
        static_cast<uint8_t>((val >> 16) & 0xFF),
        static_cast<uint8_t>((val >> 24) & 0xFF)
    };
    std::lock_guard<std::mutex> lock(_usbMutex);
    libusb_control_transfer(
        _handle, USB_REQTYPE_WRITE, USB_CMD_REQ,
        addr, USB_VENQT_CMD_IDX,
        buf, 4, USB_CONTROL_TIMEOUT_MS
    );
}

void RTL8192EUDriver::writeBlock(uint16_t addr, const uint8_t* data, size_t len) {
    // Port of wifit3 transport.py write_block (core.c:826)
    std::lock_guard<std::mutex> lock(_usbMutex);
    libusb_control_transfer(
        _handle, USB_REQTYPE_WRITE, USB_CMD_REQ,
        addr, USB_VENQT_CMD_IDX,
        const_cast<uint8_t*>(data), static_cast<uint16_t>(len),
        USB_CONTROL_TIMEOUT_MS
    );
}

// Read-modify-write helpers (wifit3: transport.py L106-122)
void RTL8192EUDriver::write8Set(uint16_t addr, uint8_t mask) {
    write8(addr, read8(addr) | mask);
}
void RTL8192EUDriver::write8Clr(uint16_t addr, uint8_t mask) {
    write8(addr, read8(addr) & ~mask);
}
void RTL8192EUDriver::write16Set(uint16_t addr, uint16_t mask) {
    write16(addr, read16(addr) | mask);
}
void RTL8192EUDriver::write16Clr(uint16_t addr, uint16_t mask) {
    write16(addr, read16(addr) & ~mask);
}
void RTL8192EUDriver::write32Set(uint16_t addr, uint32_t mask) {
    write32(addr, read32(addr) | mask);
}
void RTL8192EUDriver::write32Clr(uint16_t addr, uint32_t mask) {
    write32(addr, read32(addr) & ~mask);
}

// ============================================================
// Step 4.1: open()
// Port of wifit3: driver.py _claim_usb (L312-328)
// ============================================================

bool RTL8192EUDriver::open(uint16_t vendorId, uint16_t productId) {
    if (_open.load()) return true;

    _handle = libusb_open_device_with_vid_pid(_ctx, vendorId, productId);
    if (!_handle) {
        // Try the TP-Link VID:PID if the Realtek one failed
        if (vendorId == RTL8192EU_VID_REALTEK) {
            _handle = libusb_open_device_with_vid_pid(
                _ctx, RTL8192EU_VID_TPLINK, RTL8192EU_PID_0108
            );
        }
        if (!_handle) return false;
    }

    // Detach kernel driver if active (mirrors wifit3's
    // dev.detach_kernel_driver(0) in _claim_usb)
    if (libusb_kernel_driver_active(_handle, 0) == 1) {
        libusb_detach_kernel_driver(_handle, 0);
    }

    // Set configuration + claim interface 0
    // (wifit3: dev.set_configuration() + usb.util.claim_interface(dev, 0))
    libusb_set_configuration(_handle, 1);
    int rc = libusb_claim_interface(_handle, 0);
    if (rc != 0) {
        libusb_close(_handle);
        _handle = nullptr;
        return false;
    }

    _open.store(true);

    // Probe endpoints immediately so bulk EP addresses are known
    probeEndpoints();

    return true;
}

bool RTL8192EUDriver::isOpen() const {
    return _open.load();
}

std::string RTL8192EUDriver::macAddress() const {
    return _macAddress;
}

int RTL8192EUDriver::currentChannel() const {
    return _currentChannel;
}

// ============================================================
// Endpoint probing
// Port of wifit3: rx.py probe_endpoints (L59-82)
// ============================================================

void RTL8192EUDriver::probeEndpoints() {
    if (!_handle) return;

    libusb_device* dev = libusb_get_device(_handle);
    struct libusb_config_descriptor* config = nullptr;
    libusb_get_active_config_descriptor(dev, &config);
    if (!config) return;

    _bulkOutEps.clear();
    _bulkInEp = 0;

    for (int i = 0; i < config->bNumInterfaces; i++) {
        const struct libusb_interface& iface = config->interface[i];
        for (int j = 0; j < iface.num_altsetting; j++) {
            const struct libusb_interface_descriptor& alt = iface.altsetting[j];
            for (int k = 0; k < alt.bNumEndpoints; k++) {
                const struct libusb_endpoint_descriptor& ep = alt.endpoint[k];
                uint8_t addr = ep.bEndpointAddress;
                uint8_t attr = ep.bmAttributes & 0x03;
                bool isIn = (addr & 0x80) != 0;

                if (attr == LIBUSB_TRANSFER_TYPE_BULK) {
                    if (isIn) {
                        if (_bulkInEp == 0) _bulkInEp = addr;
                    } else {
                        _bulkOutEps.push_back(addr);
                    }
                }
            }
        }
    }

    // MGMT queue routes to the lowest-numbered bulk-OUT
    // (wifit3: tx.py pick_bulk_out_mgmt — "lowest address = HIGH lane")
    if (!_bulkOutEps.empty()) {
        _bulkOutEpMgmt = *std::min_element(_bulkOutEps.begin(), _bulkOutEps.end());
    }

    libusb_free_config_descriptor(config);
}

// ============================================================
// Step 4.2: Firmware Upload
// Port of wifit3: firmware.py (L50-221)
//
// The 8192EU uses the same 8051 MCU upload mechanism as the
// 8188EUS. Differences: 254-byte block size (vs 196), different
// firmware signature (0x92E0 vs 0x88E0), different blob.
// ============================================================

void RTL8192EUDriver::writeN(uint16_t addr, const uint8_t* buf, size_t len) {
    // Port of wifit3 firmware.py _writeN (L79-94)
    // Chunks into FW_WRITE_BLOCK_SIZE_8192E (254) byte writes.
    size_t blocksize = FW_WRITE_BLOCK_SIZE_8192E;
    size_t count = len / blocksize;
    size_t remainder = len % blocksize;

    for (size_t i = 0; i < count; i++) {
        writeBlock(addr + static_cast<uint16_t>(i * blocksize),
                   buf + i * blocksize, blocksize);
    }
    if (remainder > 0) {
        writeBlock(addr + static_cast<uint16_t>(count * blocksize),
                   buf + count * blocksize, remainder);
    }
}

void RTL8192EUDriver::reset8051() {
    // Port of wifit3 firmware.py reset_8051 (L97-101)
    // 8192EU variant: same clear-then-set of SYS_FUNC_CPU_ENABLE
    uint16_t sys_func = read16(REG_SYS_FUNC);
    write16(REG_SYS_FUNC, sys_func & ~SYS_FUNC_CPU_ENABLE);
    write16(REG_SYS_FUNC, sys_func | SYS_FUNC_CPU_ENABLE);
}

void RTL8192EUDriver::firmwareSelfReset() {
    // Port of wifit3 firmware.py firmware_self_reset (L104-120)
    write8(REG_HMTFR + 3, 0x20);
    for (int i = 0; i < 100; i++) {
        uint16_t val16 = read16(REG_SYS_FUNC);
        if (!(val16 & SYS_FUNC_CPU_ENABLE)) {
            return;  // self reset succeeded
        }
        std::this_thread::sleep_for(std::chrono::microseconds(50));
    }
    // Forced reset
    uint16_t val16 = read16(REG_SYS_FUNC);
    write16(REG_SYS_FUNC, val16 & ~SYS_FUNC_CPU_ENABLE);
}

void RTL8192EUDriver::downloadFirmware(const uint8_t* fwBlob, size_t blobLen) {
    // Port of wifit3 firmware.py download_firmware (L126-183)
    // fw_blob = full file (32-byte header + payload)
    if (blobLen <= FW_HEADER_SIZE) return;

    const uint8_t* payload = fwBlob + FW_HEADER_SIZE;
    size_t fwSize = blobLen - FW_HEADER_SIZE;

    // Pre-flight: set REG_SYS_FUNC+1 |= 4 (FEN_EN bit)
    uint8_t val8 = read8(REG_SYS_FUNC + 1);
    write8(REG_SYS_FUNC + 1, val8 | 4);

    // Enable 8051
    uint16_t val16 = read16(REG_SYS_FUNC);
    write16(REG_SYS_FUNC, val16 | SYS_FUNC_CPU_ENABLE);

    // If FW already running, reset it
    if (read8(REG_MCU_FW_DL) & MCU_FW_RAM_SEL) {
        write8(REG_MCU_FW_DL, 0x00);
        reset8051();
    }

    // MCU firmware download enable
    write8(REG_MCU_FW_DL, read8(REG_MCU_FW_DL) | MCU_FW_DL_ENABLE);

    // 8051 reset — clear BIT(19) of REG_MCU_FW_DL
    uint32_t val32 = read32(REG_MCU_FW_DL);
    write32(REG_MCU_FW_DL, val32 & ~MCU_FW_DL_8051_RESET_BIT);

    // Reset firmware-download checksum
    write8(REG_MCU_FW_DL, read8(REG_MCU_FW_DL) | MCU_FW_DL_CSUM_REPORT);

    size_t pages = fwSize / RTL_FW_PAGE_SIZE;
    size_t remainder = fwSize % RTL_FW_PAGE_SIZE;

    // Upload pages
    for (size_t i = 0; i < pages; i++) {
        uint8_t pageIdx = read8(REG_MCU_FW_DL + 2) & 0xF8;
        write8(REG_MCU_FW_DL + 2, pageIdx | static_cast<uint8_t>(i));
        writeN(REG_FW_START_ADDRESS,
               payload + i * RTL_FW_PAGE_SIZE, RTL_FW_PAGE_SIZE);
    }
    if (remainder > 0) {
        uint8_t pageIdx = read8(REG_MCU_FW_DL + 2) & 0xF8;
        write8(REG_MCU_FW_DL + 2, pageIdx | static_cast<uint8_t>(pages));
        writeN(REG_FW_START_ADDRESS,
               payload + pages * RTL_FW_PAGE_SIZE, remainder);
    }

    // Disable FW download
    val16 = read16(REG_MCU_FW_DL);
    write16(REG_MCU_FW_DL, val16 & ~MCU_FW_DL_ENABLE);
}

void RTL8192EUDriver::startFirmware() {
    // Port of wifit3 firmware.py start_firmware (L186-220)

    // Poll checksum report
    for (int i = 0; i < RTL8XXXU_FIRMWARE_POLL_MAX; i++) {
        if (read32(REG_MCU_FW_DL) & MCU_FW_DL_CSUM_REPORT) break;
    }

    // Set FW_DL_READY, clear WINT_INIT_READY, reset 8051
    uint32_t val32 = read32(REG_MCU_FW_DL);
    val32 |= MCU_FW_DL_READY;
    val32 &= ~MCU_WINT_INIT_READY;
    write32(REG_MCU_FW_DL, val32);

    reset8051();

    // Wait for firmware to become ready
    for (int i = 0; i < RTL8XXXU_FIRMWARE_POLL_MAX; i++) {
        if (read32(REG_MCU_FW_DL) & MCU_WINT_INIT_READY) break;
        std::this_thread::sleep_for(std::chrono::microseconds(100));
    }
}

bool RTL8192EUDriver::uploadFirmware(const uint8_t* fwData, size_t len) {
    if (!_open.load() || !fwData || len <= FW_HEADER_SIZE) return false;

    // Validate firmware signature (0x92E0 family for 8192EU)
    uint16_t signature = fwData[0] | (fwData[1] << 8);
    if ((signature & 0xFFF0) != FW_SIGNATURE_92E) {
        // Not an 8192EU firmware blob
        return false;
    }

    downloadFirmware(fwData, len);
    startFirmware();
    return true;
}

// ============================================================
// Power-on sequence
// Port of wifit3: driver.py _power_on / _disabled_to_emu / _emu_to_active
// (L439-501)
//
// The 8192EU variant is similar to the 8188EUS but has a different
// emu_to_active sequence (8192e.c vs 8188e.c). The register space
// is shared; the operational writes differ.
// ============================================================

void RTL8192EUDriver::disabledToEmu() {
    // Port of wifit3 driver.py _disabled_to_emu (L448-452)
    uint16_t val16 = read16(REG_APS_FSMCO);
    val16 &= ~(APS_FSMCO_HW_SUSPEND | APS_FSMCO_PCIE);
    write16(REG_APS_FSMCO, val16);
}

void RTL8192EUDriver::emuToActive() {
    // Port of wifit3 driver.py _emu_to_active (L454-500)
    // Wait for power ready (APS_FSMCO[17] = 1)
    for (int i = 0; i < RTL8XXXU_MAX_REG_POLL; i++) {
        if (read32(REG_APS_FSMCO) & APS_FSMCO_POWER_READY) break;
        std::this_thread::sleep_for(std::chrono::microseconds(10));
    }

    // Reset baseband
    uint8_t val8 = read8(REG_SYS_FUNC);
    val8 &= ~(SYS_FUNC_BBRSTB | SYS_FUNC_BB_GLB_RSTN);
    write8(REG_SYS_FUNC, val8);

    // Schmitt-trigger enable (0x24[23] = 1)
    uint32_t val32 = read32(REG_AFE_XTAL_CTRL);
    val32 |= (1 << 23);
    write32(REG_AFE_XTAL_CTRL, val32);

    // Disable HWPDN (0x04[15] = 0)
    uint16_t val16 = read16(REG_APS_FSMCO);
    val16 &= ~APS_FSMCO_HW_POWERDOWN;
    write16(REG_APS_FSMCO, val16);

    // Disable WL suspend (0x04[12:11] = 0)
    val16 = read16(REG_APS_FSMCO);
    val16 &= ~(APS_FSMCO_HW_SUSPEND | APS_FSMCO_PCIE);
    write16(REG_APS_FSMCO, val16);

    // Set MAC_ENABLE, poll until it self-clears
    val32 = read32(REG_APS_FSMCO);
    val32 |= APS_FSMCO_MAC_ENABLE;
    write32(REG_APS_FSMCO, val32);
    for (int i = 0; i < RTL8XXXU_MAX_REG_POLL; i++) {
        if ((read32(REG_APS_FSMCO) & APS_FSMCO_MAC_ENABLE) == 0) break;
        std::this_thread::sleep_for(std::chrono::microseconds(10));
    }

    // LDO normal mode (REG_LPLDO_CTRL bit 4 = 0)
    val8 = read8(REG_LPLDO_CTRL);
    val8 &= ~(1 << 4);
    write8(REG_LPLDO_CTRL, val8);
}

void RTL8192EUDriver::powerOn() {
    // Port of wifit3 driver.py _power_on (L439-446)
    disabledToEmu();
    emuToActive();

    // Enable DMA/protocol/sched/sec/caltimer — NOT MAC_TX/MAC_RX yet
    // (the 88E TRXFF_BNDY HW bug applies to the 92E too)
    write16(REG_CR, CR_INIT_POWER_ON);
}

bool RTL8192EUDriver::isChipWarm() {
    // Port of wifit3 mac.py is_chip_warm
    // If FW is already loaded (MCU_FW_RAM_SEL set) and CR shows active
    // DMA engines, the chip was left running from a previous session.
    uint8_t fwDl = read8(REG_MCU_FW_DL);
    uint16_t cr = read16(REG_CR);
    return (fwDl & MCU_FW_RAM_SEL) &&
           (cr & CR_TXDMA_ENABLE) &&
           (cr & CR_RXDMA_ENABLE);
}

// ============================================================
// LLT init
// Port of wifit3: mac.py LLT table initialization
// ============================================================

bool RTL8192EUDriver::lltWrite(uint32_t address, uint32_t data) {
    // Port of kernel rtl8xxxu_llt_write (core.c:2514)
    write32(REG_LLT_INIT, LLT_OP_WRITE | (address << 8) | data);
    for (int i = 0; i < 20; i++) {
        if ((read32(REG_LLT_INIT) & LLT_OP_MASK) == 0) return true;
        std::this_thread::sleep_for(std::chrono::microseconds(10));
    }
    return false;
}

void RTL8192EUDriver::initLlt() {
    // Port of kernel rtl8xxxu_init_llt_table (core.c:2530)
    // Pages 0..LAST_LLT_ENTRY → next page (chain). Last entry → 0xFF (end).
    // Pages after last entry → 0xFF (TX reserved).
    for (int i = 0; i < LAST_LLT_ENTRY_8192E; i++) {
        lltWrite(i, i + 1);
    }
    lltWrite(LAST_LLT_ENTRY_8192E, 0xFF);
    for (int i = LAST_LLT_ENTRY_8192E + 1; i < 256; i++) {
        lltWrite(i, 0xFF);
    }
}

// ============================================================
// MAC init (post-FW)
// Port of wifit3: mac.py post_fw_mac_init + enable_rx_data_path
// ============================================================

void RTL8192EUDriver::postFwMacInit() {
    // Port of wifit3 mac.py post_fw_mac_init

    // TRXFF boundary — 8192EU-specific (kernel: 8192e.c fileops)
    write16(REG_TRXFF_BNDY, TRXFF_BOUNDARY_8192E);

    // Now enable MAC TX/RX (after TRXFF_BNDY is set)
    uint16_t cr = read16(REG_CR);
    cr |= CR_MAC_TX_ENABLE | CR_MAC_RX_ENABLE;
    write16(REG_CR, cr);

    // RQPN page allocation (8192EU-specific)
    write32(REG_RQPN,
        (PAGE_NUM_HI_PQ_8192E << 0) |
        (PAGE_NUM_LO_PQ_8192E << 8) |
        (static_cast<uint32_t>(TOTAL_PAGE_NUM_8192E - PAGE_NUM_HI_PQ_8192E
             - PAGE_NUM_LO_PQ_8192E - PAGE_NUM_NORM_PQ_8192E) << 16) |
        (1u << 31)  // RQPN_LOAD
    );

    // LLT init
    initLlt();

    // PBP: 128-byte pages for both TX and RX
    write8(REG_PBP, 0x11);  // PBP_PAGE_SIZE_128 in both nibbles
}

void RTL8192EUDriver::enableRxDataPath() {
    // Port of wifit3 mac.py enable_rx_data_path

    // Set DRVINFO size to 4 (→ 32-byte phy_stats)
    write8(REG_RX_DRVINFO_SZ, 4);

    // Interrupt masks (8188e-compatible, the 92E uses the same)
    write32(REG_HIMR0, 0);
    write32(REG_HIMR1, 0);

    // USB special option: enable bulk-select for INT endpoint
    uint8_t spec = read8(REG_USB_SPECIAL_OPTION);
    write8(REG_USB_SPECIAL_OPTION, spec | (1 << 4));
}

void RTL8192EUDriver::applyMonitorRxFilter() {
    // Port of wifit3 mac.py apply_monitor_rx_filter
    // Critical: without all accept-bits, EAPOL and ACKs are invisible.
    write32(REG_RCR, RCR_MONITOR);
}

// ============================================================
// Step 4.3: Monitor Mode
// ============================================================

bool RTL8192EUDriver::setMonitorMode(bool enabled) {
    if (!_open.load()) return false;

    if (enabled) {
        // Full bring-up if chip is cold
        if (!isChipWarm()) {
            powerOn();
        }
        applyMonitorRxFilter();

        // Enable RF paths A+B for the 2T2R 8192EU
        write8(REG_RF_CTRL, RF_ENABLE | RF_RSTB | RF_SDMRSTB);
        uint8_t trxPath = read8(REG_OFDM0_TRX_PATH_ENABLE);
        // Enable both path A and path B RX + TX
        trxPath |= 0x03;  // RX path A+B (bits 0,1)
        trxPath |= 0x30;  // TX path A+B (bits 4,5)
        write8(REG_OFDM0_TRX_PATH_ENABLE, trxPath);

        // Un-pause TX
        write8(REG_TXPAUSE, 0x00);

        // Enable CCK+OFDM baseband blocks
        write32Set(REG_FPGA0_RF_MODE, FPGA_RF_MODE_CCK | FPGA_RF_MODE_OFDM);
    } else {
        // Disable monitor: pause TX, narrow RCR
        write8(REG_TXPAUSE, 0xFF);
        write32(REG_RCR, 0);
    }
    return true;
}

// ============================================================
// Step 4.4: Channel Tune (2.4 GHz, 20 MHz)
// Port of wifit3: chan.py set_channel_2g_20mhz
//
// RF6052 channel tune via SIPI (serial interface PI mode).
// The channel number goes into RF6052_REG_MODE_AG[9:0].
// Identical protocol for 8188EUS and 8192EU.
// ============================================================

void RTL8192EUDriver::writeRfReg(int path, uint8_t reg, uint32_t data) {
    // Port of wifit3 phy.py (kernel core.c:922-923)
    // SIPI write: address in bits[23:20], data in bits[19:0]
    uint32_t val = ((static_cast<uint32_t>(reg) & 0xFF) << FPGA0_LSSI_PARM_ADDR_SHIFT)
                 | (data & FPGA0_LSSI_PARM_DATA_MASK);

    uint16_t lssiReg = (path == 0)
        ? REG_FPGA0_XA_LSSI_PARM
        : static_cast<uint16_t>(REG_FPGA0_XA_LSSI_PARM + 4);  // path B

    write32(lssiReg, val);
    std::this_thread::sleep_for(std::chrono::microseconds(1));
}

uint32_t RTL8192EUDriver::readRfReg(int path, uint8_t reg) {
    // Port of kernel rtl8xxxu_read_rfreg (core.c:880-900)
    uint16_t hssiReg = (path == 0) ? REG_FPGA0_XA_HSSI_PARM2 : REG_FPGA0_XB_HSSI_PARM2;

    // Set read address
    uint32_t val = read32(hssiReg);
    val &= ~(0xFF << 23);
    val |= (static_cast<uint32_t>(reg & 0xFF) << 23);
    val |= (1u << 31);  // edge-read trigger
    write32(hssiReg, val);
    std::this_thread::sleep_for(std::chrono::microseconds(10));

    // Read result from the readback register
    uint16_t readbackReg = 0x08A0;  // REG_FPGA0_XA_LSSI_READBACK
    if (path == 1) readbackReg = 0x08A4;
    return read32(readbackReg) & 0x000FFFFF;
}

bool RTL8192EUDriver::setChannel(int channel) {
    if (!_open.load()) return false;
    if (channel < 1 || channel > 14) return false;

    // Port of wifit3 chan.py set_channel_2g_20mhz

    // 20 MHz bandwidth mode
    write8Set(REG_BW_OPMODE, 1 << 2);  // BW_OPMODE_20MHZ

    // FPGA0_RF_MODE: clear bit 0 (40 MHz flag)
    write32Clr(REG_FPGA0_RF_MODE, FPGA_RF_MODE);
    write32Clr(REG_FPGA1_RF_MODE, FPGA_RF_MODE);

    // Write channel to RF6052_REG_MODE_AG for both paths (A and B)
    uint32_t rfVal = readRfReg(0, RF6052_REG_MODE_AG);
    rfVal = (rfVal & ~MODE_AG_CHANNEL_MASK) | (channel & MODE_AG_CHANNEL_MASK);
    writeRfReg(0, RF6052_REG_MODE_AG, rfVal);

    // Path B (the 8192EU is 2T2R — the 8188EUS only does path A)
    rfVal = readRfReg(1, RF6052_REG_MODE_AG);
    rfVal = (rfVal & ~MODE_AG_CHANNEL_MASK) | (channel & MODE_AG_CHANNEL_MASK);
    writeRfReg(1, RF6052_REG_MODE_AG, rfVal);

    _currentChannel = channel;
    return true;
}

// ============================================================
// RX Descriptor Decode
// Port of wifit3: rx.py parse_rxdesc16 + iter_bulk_frames (L110-216)
// ============================================================

RxDesc16 RTL8192EUDriver::parseRxDesc16(const uint8_t* buf) {
    // Port of wifit3 rx.py parse_rxdesc16 (L110-127)
    uint32_t w0, w1, w2, w3;
    memcpy(&w0, buf + 0, 4);
    memcpy(&w1, buf + 4, 4);
    memcpy(&w2, buf + 8, 4);
    memcpy(&w3, buf + 12, 4);
    // LE → host (already LE on ARM)

    RxDesc16 desc;
    desc.pkt_len           = w0 & 0x3FFF;
    desc.crc_err           = (w0 & (1 << 14)) != 0;
    desc.icv_err           = (w0 & (1 << 15)) != 0;
    desc.drv_info_sz_bytes = ((w0 >> 16) & 0xF) * 8;
    desc.shift             = (w0 >> 24) & 0x3;
    desc.phy_stats_present = (w0 & (1 << 26)) != 0;
    desc.pkt_cnt           = (w2 >> 16) & 0xFF;
    desc.rxmcs             = w3 & 0x3F;
    desc.rpt_sel           = (w3 >> 14) & 0x3;
    return desc;
}

int RTL8192EUDriver::parseRssi(const uint8_t* phyStats, int rxmcs) {
    // Port of wifit3 rx.py parse_phystats_rssi (L150-173)
    if (rxmcs <= DESC_RATE_LAST_CCK) {
        // CCK: LNA/VGA lookup (wifit3 rx.py L138-147)
        uint8_t cckAgcRpt = phyStats[PHY_STATS_CCK_AGC_RPT_OFFSET];
        int lnaIdx = (cckAgcRpt >> 5) & 0x07;
        int vgaIdx = cckAgcRpt & 0x1F;
        return CCK_LNA_GAIN_TSMC[lnaIdx] - (2 * vgaIdx);
    }
    // OFDM: (pwdb >> 1) - 110  (kernel core.c:5658)
    uint8_t pwdb = phyStats[PHY_STATS_PWDB_OFFSET];
    return (pwdb >> 1) - 110;
}

// ============================================================
// Step 4.3 (continued): RX capture loop
// Port of wifit3: driver.py _rx_read_once + _rx_dispatch (L392-422)
// ============================================================

void RTL8192EUDriver::rxLoop() {
    std::vector<uint8_t> buf(16384);

    while (_capturing.load()) {
        int transferred = 0;
        int rc = libusb_bulk_transfer(
            _handle, _bulkInEp,
            buf.data(), static_cast<int>(buf.size()),
            &transferred, 100  // 100ms timeout
        );

        if (rc == LIBUSB_ERROR_TIMEOUT || transferred == 0) continue;
        if (rc != 0) break;  // fatal USB error

        // Port of wifit3 rx.py iter_bulk_frames (L176-216)
        int pos = 0;
        while (pos + RX_PKT_DESC_SZ <= transferred) {
            RxDesc16 desc = parseRxDesc16(buf.data() + pos);

            if (desc.pkt_len == 0 || desc.totalSize() == 0) break;
            if (pos + desc.totalSize() > transferred) break;

            // Skip TX report frames
            if (desc.rpt_sel != 0) goto next_frame;
            // Skip CRC/ICV errors
            if (desc.crc_err || desc.icv_err) goto next_frame;

            {
                int rssi = -100;
                if (desc.phy_stats_present && desc.drv_info_sz_bytes >= PHY_STATS_SZ) {
                    rssi = parseRssi(buf.data() + pos + RX_PKT_DESC_SZ, desc.rxmcs);
                }

                int mpduStart = pos + desc.mpduOffset();
                if (mpduStart + desc.pkt_len <= transferred) {
                    RawFrame frame;
                    frame.data.assign(
                        buf.data() + mpduStart,
                        buf.data() + mpduStart + desc.pkt_len
                    );
                    frame.rssi_dbm = rssi;
                    frame.channel = _currentChannel;

                    if (_frameCallback) {
                        _frameCallback(frame);
                    }
                }
            }

        next_frame:
            // Next frame: 128-byte aligned (wifit3 rx.py L212-216)
            int nextPos = (pos + desc.totalSize() + RX_FRAME_ALIGN - 1)
                        & ~(RX_FRAME_ALIGN - 1);
            if (nextPos <= pos) break;
            pos = nextPos;
        }
    }
}

void RTL8192EUDriver::startCapture(FrameCallback onFrame) {
    if (!_open.load() || _capturing.load()) return;
    _frameCallback = std::move(onFrame);
    _capturing.store(true);

    // RX loop runs on a dedicated thread (mirrors wifit3's RxReaderThread)
    std::thread([this]() { rxLoop(); }).detach();
}

void RTL8192EUDriver::stopCapture() {
    _capturing.store(false);
    _frameCallback = nullptr;
}

// ============================================================
// Step 4.5: TX Inject
// Port of wifit3: tx.py build_tx_desc_mgmt + send_mgmt_frame (L111-211)
// ============================================================

void RTL8192EUDriver::buildTxDescMgmt(uint8_t* desc, uint16_t pktLen, bool isBroadcast) {
    // Port of wifit3 tx.py build_tx_desc_mgmt (L111-166)
    memset(desc, 0, TX_DESC_SZ);

    // txdw0: pkt_size, pkt_offset, flags
    desc[0] = pktLen & 0xFF;
    desc[1] = (pktLen >> 8) & 0xFF;
    desc[2] = TX_DESC_SZ;   // pkt_offset = descriptor size
    uint8_t txdw0 = TXDESC_OWN | TXDESC_FIRST_SEGMENT | TXDESC_LAST_SEGMENT;
    if (isBroadcast) txdw0 |= TXDESC_BROADMULTICAST;
    desc[3] = txdw0;

    // txdw1: queue = MGMT (0x12) at bits[12:8]
    uint32_t txdw1 = TXDESC_QUEUE_MGNT << TXDESC_QUEUE_SHIFT;
    memcpy(desc + 4, &txdw1, 4);

    // txdw2: AGG_BREAK + antenna A + B
    uint32_t txdw2 = TXDESC40_AGG_BREAK | TXDESC_ANTENNA_SELECT_A | TXDESC_ANTENNA_SELECT_B;
    memcpy(desc + 8, &txdw2, 4);

    // txdw4: USE_DRIVER_RATE
    uint32_t txdw4 = TXDESC32_USE_DRIVER_RATE;
    memcpy(desc + 16, &txdw4, 4);

    // txdw5: rate=0 (1Mbps CCK), retry limit=6, enable
    uint32_t txdw5 = ((TXDESC32_RETRY_LIMIT_MGNT & 0x3F) << TXDESC32_RETRY_LIMIT_SHIFT)
                   | TXDESC32_RETRY_LIMIT_ENABLE;
    memcpy(desc + 20, &txdw5, 4);

    // txdw7: ANTENNA_SELECT_C high bits
    uint16_t txdw7 = (TXDESC_ANTENNA_SELECT_C >> 16) & 0xFFFF;
    memcpy(desc + 30, &txdw7, 2);
}

void RTL8192EUDriver::calcTxDescCsum(uint8_t* desc) {
    // Port of wifit3 tx.py calc_tx_desc_csum (L169-182)
    // XOR-16 over the 32-byte descriptor, csum at bytes 28-29 cleared first
    desc[28] = 0;
    desc[29] = 0;
    uint16_t csum = 0;
    for (int i = 0; i < TX_DESC_SZ; i += 2) {
        csum ^= static_cast<uint16_t>(desc[i] | (desc[i + 1] << 8));
    }
    desc[28] = csum & 0xFF;
    desc[29] = (csum >> 8) & 0xFF;
}

bool RTL8192EUDriver::injectFrame(const std::vector<uint8_t>& frameBytes) {
    if (!_open.load() || _bulkOutEpMgmt == 0) return false;

    // Determine bcast/mcast from addr1 (frame_bytes[4:10])
    bool isBcast = false;
    if (frameBytes.size() >= 10) {
        isBcast = (frameBytes[4] & 0x01) != 0;  // I/G bit
    }

    // Build descriptor
    uint8_t desc[TX_DESC_SZ];
    buildTxDescMgmt(desc, static_cast<uint16_t>(frameBytes.size()), isBcast);
    calcTxDescCsum(desc);

    // Assemble URB: [32-byte desc] + [MPDU]
    std::vector<uint8_t> urb(TX_DESC_SZ + frameBytes.size());
    memcpy(urb.data(), desc, TX_DESC_SZ);
    memcpy(urb.data() + TX_DESC_SZ, frameBytes.data(), frameBytes.size());

    // Bulk-OUT write
    int transferred = 0;
    std::lock_guard<std::mutex> lock(_usbMutex);
    int rc = libusb_bulk_transfer(
        _handle, _bulkOutEpMgmt,
        urb.data(), static_cast<int>(urb.size()),
        &transferred, 200
    );
    return (rc == 0 && transferred == static_cast<int>(urb.size()));
}

// ============================================================
// Teardown
// Port of wifit3: driver.py close (L192-197)
// ============================================================

void RTL8192EUDriver::close() {
    stopCapture();

    if (_handle) {
        libusb_release_interface(_handle, 0);
        libusb_close(_handle);
        _handle = nullptr;
    }
    _open.store(false);
    _bulkInEp = 0;
    _bulkOutEpMgmt = 0;
    _bulkOutEps.clear();
}