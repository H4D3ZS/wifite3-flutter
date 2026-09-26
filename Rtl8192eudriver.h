#pragma once
// RTL8192EU Userspace USB Driver — Header
//
// Port of wifit3/src/wifit3/chips/rtl8188eus/* (Python → Obj-C++) for
// jailbroken iOS via libusb. The RTL8192EU shares the rtl8xxxu register
// space and USB vendor-control protocol with the 8188EUS; it differs in
// being 2T2R, having a different firmware blob, and needing path-B
// PHY/RF init.
//
// Every register address and bit flag is traced to the kernel
// rtl8xxxu source (regs.h, core.c, 8192e.c) via wifit3's constants.py.

#import <Foundation/Foundation.h>
#include <functional>
#include <vector>
#include <cstdint>
#include <string>
#include <atomic>
#include <mutex>

// Forward-declare libusb types so callers don't need the header.
struct libusb_device_handle;
struct libusb_context;

// ============================================================
// USB vendor-control wire protocol
// (wifit3: constants.py L11-15, kernel: rtl8xxxu.h:34-36)
// ============================================================
static constexpr uint8_t  USB_CMD_REQ           = 0x05;
static constexpr uint8_t  USB_REQTYPE_READ      = 0xC0;
static constexpr uint8_t  USB_REQTYPE_WRITE     = 0x40;
static constexpr uint16_t USB_VENQT_CMD_IDX     = 0x00;
static constexpr unsigned USB_CONTROL_TIMEOUT_MS = 500;

// ============================================================
// VID:PID — TP-Link WN823N (RTL8192EU)
// (kernel: rtl8xxxu_core.c usb_device_id table)
// ============================================================
static constexpr uint16_t RTL8192EU_VID_REALTEK   = 0x0BDA;
static constexpr uint16_t RTL8192EU_PID_818B      = 0x818B;
static constexpr uint16_t RTL8192EU_VID_TPLINK    = 0x2357;
static constexpr uint16_t RTL8192EU_PID_0108      = 0x0108;   // WN823N v2/v3

// ============================================================
// MAC register addresses
// (wifit3: constants.py, kernel: regs.h)
// Shared with RTL8188EUS — same rtl8xxxu register space.
// ============================================================
static constexpr uint16_t REG_SYS_ISO_CTRL       = 0x0000;   // regs.h:9
static constexpr uint16_t REG_SYS_FUNC           = 0x0002;   // regs.h:16
static constexpr uint16_t REG_APS_FSMCO          = 0x0004;   // regs.h:34
static constexpr uint16_t REG_SYS_CLKR           = 0x0008;   // regs.h:47
static constexpr uint16_t REG_9346CR             = 0x000A;   // regs.h:60
static constexpr uint16_t REG_RSV_CTRL           = 0x001C;   // regs.h:72
static constexpr uint16_t REG_RF_CTRL            = 0x001F;   // regs.h:76
static constexpr uint16_t REG_LDOA15_CTRL        = 0x0020;   // regs.h:81
static constexpr uint16_t REG_LDOV12D_CTRL       = 0x0021;   // regs.h:88
static constexpr uint16_t REG_LPLDO_CTRL         = 0x0023;   // regs.h:95
static constexpr uint16_t REG_AFE_XTAL_CTRL      = 0x0024;   // regs.h:99
static constexpr uint16_t REG_EFUSE_CTRL         = 0x0030;   // regs.h:121
static constexpr uint16_t REG_EFUSE_TEST         = 0x0034;   // regs.h:122
static constexpr uint16_t REG_GPIO_MUXCFG        = 0x0040;   // regs.h:141
static constexpr uint16_t REG_MCU_FW_DL          = 0x0080;   // regs.h:219
static constexpr uint16_t REG_HIMR0              = 0x00B0;   // regs.h:238
static constexpr uint16_t REG_HISR0              = 0x00B4;   // regs.h:272
static constexpr uint16_t REG_HIMR1              = 0x00B8;   // regs.h:273
static constexpr uint16_t REG_EFUSE_ACCESS       = 0x00CF;   // regs.h:301
static constexpr uint16_t REG_SYS_CFG            = 0x00F0;   // regs.h:312
static constexpr uint16_t REG_CR                 = 0x0100;   // regs.h:370
static constexpr uint16_t REG_PBP                = 0x0104;   // regs.h:391
static constexpr uint16_t REG_TRXDMA_CTRL        = 0x010C;   // regs.h:405
static constexpr uint16_t REG_TRXFF_BNDY         = 0x0114;   // regs.h:423
static constexpr uint16_t REG_HMTFR              = 0x01CC;   // regs.h:456
static constexpr uint16_t REG_LLT_INIT           = 0x01E0;   // regs.h:462
static constexpr uint16_t REG_RQPN               = 0x0200;   // regs.h:477
static constexpr uint16_t REG_TDECTRL            = 0x0208;   // regs.h:484
static constexpr uint16_t REG_RQPN_NPQ           = 0x0214;   // regs.h:492
static constexpr uint16_t REG_TXPKTBUF_BCNQ_BDNY = 0x0424;   // regs.h:550
static constexpr uint16_t REG_TXPKTBUF_MGQ_BDNY  = 0x0425;   // regs.h:551
static constexpr uint16_t REG_TXPAUSE            = 0x0522;   // regs.h:671
static constexpr uint16_t REG_BW_OPMODE          = 0x0603;   // regs.h:738
static constexpr uint16_t REG_RCR                = 0x0608;   // regs.h:746
static constexpr uint16_t REG_RX_DRVINFO_SZ      = 0x060F;   // regs.h:787
static constexpr uint16_t REG_RXFLTMAP1          = 0x06A2;   // regs.h ctrl-subtype map
static constexpr uint16_t REG_FW_START_ADDRESS   = 0x1000;   // regs.h:1200
static constexpr uint16_t REG_USB_SPECIAL_OPTION = 0xFE55;   // regs.h:1248
static constexpr uint16_t REG_MAX_AGGR_NUM       = 0x04CA;   // regs.h:632

// ============================================================
// REG_SYS_FUNC bits (regs.h:17-30)
// (wifit3: constants.py L50-54)
// ============================================================
static constexpr uint16_t SYS_FUNC_BBRSTB       = 1 << 0;
static constexpr uint16_t SYS_FUNC_BB_GLB_RSTN  = 1 << 1;
static constexpr uint16_t SYS_FUNC_USBA         = 1 << 2;
static constexpr uint16_t SYS_FUNC_USBD         = 1 << 4;
static constexpr uint16_t SYS_FUNC_CPU_ENABLE   = 1 << 10;
static constexpr uint16_t SYS_FUNC_ELDR         = 1 << 12;
static constexpr uint16_t SYS_FUNC_DIO_RF       = 1 << 13;

// ============================================================
// REG_APS_FSMCO bits (regs.h:35-45)
// (wifit3: constants.py L56-61)
// ============================================================
static constexpr uint32_t APS_FSMCO_MAC_ENABLE    = 1 << 8;
static constexpr uint32_t APS_FSMCO_HW_SUSPEND    = 1 << 11;
static constexpr uint32_t APS_FSMCO_PCIE          = 1 << 12;
static constexpr uint32_t APS_FSMCO_HW_POWERDOWN  = 1 << 15;
static constexpr uint32_t APS_FSMCO_POWER_READY   = 1 << 17;

// ============================================================
// REG_MCU_FW_DL bits (regs.h:220-227)
// (wifit3: constants.py L63-68)
// ============================================================
static constexpr uint32_t MCU_FW_DL_ENABLE        = 1 << 0;
static constexpr uint32_t MCU_FW_DL_READY         = 1 << 1;
static constexpr uint32_t MCU_FW_DL_CSUM_REPORT   = 1 << 2;
static constexpr uint32_t MCU_WINT_INIT_READY      = 1 << 6;
static constexpr uint32_t MCU_FW_RAM_SEL           = 1 << 7;
static constexpr uint32_t MCU_FW_DL_8051_RESET_BIT = 1 << 19;

// ============================================================
// REG_CR bits (regs.h:371-381)
// (wifit3: constants.py L71-95)
// ============================================================
static constexpr uint16_t CR_HCI_TXDMA_ENABLE  = 1 << 0;
static constexpr uint16_t CR_HCI_RXDMA_ENABLE  = 1 << 1;
static constexpr uint16_t CR_TXDMA_ENABLE      = 1 << 2;
static constexpr uint16_t CR_RXDMA_ENABLE      = 1 << 3;
static constexpr uint16_t CR_PROTOCOL_ENABLE   = 1 << 4;
static constexpr uint16_t CR_SCHEDULE_ENABLE   = 1 << 5;
static constexpr uint16_t CR_MAC_TX_ENABLE     = 1 << 6;
static constexpr uint16_t CR_MAC_RX_ENABLE     = 1 << 7;
static constexpr uint16_t CR_SECURITY_ENABLE   = 1 << 9;
static constexpr uint16_t CR_CALTIMER_ENABLE   = 1 << 10;
static constexpr uint16_t CR_INIT_POWER_ON = (
    CR_HCI_TXDMA_ENABLE | CR_HCI_RXDMA_ENABLE |
    CR_TXDMA_ENABLE | CR_RXDMA_ENABLE |
    CR_PROTOCOL_ENABLE | CR_SCHEDULE_ENABLE |
    CR_SECURITY_ENABLE | CR_CALTIMER_ENABLE
);

// ============================================================
// REG_RF_CTRL bits (regs.h:76-79)
// ============================================================
static constexpr uint8_t RF_ENABLE  = 1 << 0;
static constexpr uint8_t RF_RSTB    = 1 << 1;
static constexpr uint8_t RF_SDMRSTB = 1 << 2;

// ============================================================
// REG_RCR bits — Monitor-mode RX filter
// (wifit3: constants.py L211-249)
// ============================================================
static constexpr uint32_t RCR_ACCEPT_AP          = 1 << 0;
static constexpr uint32_t RCR_ACCEPT_PHYS_MATCH  = 1 << 1;
static constexpr uint32_t RCR_ACCEPT_MCAST       = 1 << 2;
static constexpr uint32_t RCR_ACCEPT_BCAST       = 1 << 3;
static constexpr uint32_t RCR_ACCEPT_CRC32       = 1 << 8;
static constexpr uint32_t RCR_ACCEPT_ICV         = 1 << 9;
static constexpr uint32_t RCR_ACCEPT_DATA_FRAME  = 1 << 11;
static constexpr uint32_t RCR_ACCEPT_CTRL_FRAME  = 1 << 12;
static constexpr uint32_t RCR_ACCEPT_MGMT_FRAME  = 1 << 13;
static constexpr uint32_t RCR_HTC_LOC_CTRL       = 1 << 14;
static constexpr uint32_t RCR_APPEND_PHYSTAT      = 1 << 28;
static constexpr uint32_t RCR_APPEND_ICV          = 1 << 29;
static constexpr uint32_t RCR_APPEND_MIC          = 1 << 30;

// Full monitor-mode RCR. Identical to wifit3's RCR_MONITOR (0x70007B0F).
// ALL accept-bits + HTC_LOC + 3 APPEND. Without ACCEPT_DATA_FRAME,
// EAPOL is invisible. Without ACCEPT_CTRL_FRAME, ACKs are invisible.
static constexpr uint32_t RCR_MONITOR = (
    RCR_ACCEPT_AP | RCR_ACCEPT_PHYS_MATCH |
    RCR_ACCEPT_MCAST | RCR_ACCEPT_BCAST |
    RCR_ACCEPT_DATA_FRAME | RCR_ACCEPT_CTRL_FRAME |
    RCR_ACCEPT_MGMT_FRAME | RCR_HTC_LOC_CTRL |
    RCR_APPEND_PHYSTAT | RCR_APPEND_ICV | RCR_APPEND_MIC
);

// ============================================================
// Firmware upload tunables
// (wifit3: constants.py L98-105)
// ============================================================
static constexpr int RTL_FW_PAGE_SIZE           = 4096;
static constexpr int RTL8XXXU_FIRMWARE_POLL_MAX = 1000;
static constexpr int RTL8XXXU_MAX_REG_POLL      = 500;
static constexpr int FW_HEADER_SIZE             = 32;
// 8192EU uses 254-byte block size (vs 8188EUS's 196).
// (kernel: 8192e.c fileops .writeN_block_size)
static constexpr int FW_WRITE_BLOCK_SIZE_8192E  = 254;
// 8192EU firmware signature (signature & 0xFFF0).
// (kernel: core.c:2136 — 0x92E0 family)
static constexpr uint16_t FW_SIGNATURE_92E      = 0x92E0;

// ============================================================
// RX descriptor — rxdesc16 (24 bytes, not 16)
// (wifit3: constants.py L268-276, rx.py)
// Same format for 8192EU and 8188EUS.
// ============================================================
static constexpr int RX_PKT_DESC_SZ   = 24;   // 6 × u32 (including tsfl)
static constexpr int RX_FRAME_ALIGN   = 128;  // roundup(..., 128) between frames in a URB
static constexpr int PHY_STATS_SZ     = 32;   // REG_RX_DRVINFO_SZ=4 → 4×8=32 bytes
static constexpr int PHY_STATS_PWDB_OFFSET = 4;  // cck_sig_qual_ofdm_pwdb_all
static constexpr int PHY_STATS_CCK_AGC_RPT_OFFSET = 5;
static constexpr int DESC_RATE_LAST_CCK = 0x03;  // rates 0..3 = CCK

// ============================================================
// TX descriptor — txdesc32 (32 bytes)
// (wifit3: constants.py L300-321, tx.py)
// Same format for 8192EU and 8188EUS.
// ============================================================
static constexpr int TX_DESC_SZ       = 32;
static constexpr uint8_t  TXDESC_BROADMULTICAST    = 1 << 0;
static constexpr uint8_t  TXDESC_LAST_SEGMENT      = 1 << 2;
static constexpr uint8_t  TXDESC_FIRST_SEGMENT     = 1 << 3;
static constexpr uint8_t  TXDESC_OWN               = 1 << 7;
static constexpr int      TXDESC_QUEUE_SHIFT        = 8;
static constexpr uint32_t TXDESC_QUEUE_MGNT         = 0x12;
static constexpr uint32_t TXDESC40_AGG_BREAK        = 1 << 16;
static constexpr uint32_t TXDESC_ANTENNA_SELECT_A   = 1 << 24;
static constexpr uint32_t TXDESC_ANTENNA_SELECT_B   = 1 << 25;
static constexpr uint32_t TXDESC_ANTENNA_SELECT_C   = 1 << 29;
static constexpr uint32_t TXDESC32_USE_DRIVER_RATE  = 1 << 8;
static constexpr uint32_t TXDESC32_RETRY_LIMIT_ENABLE = 1 << 17;
static constexpr int      TXDESC32_RETRY_LIMIT_SHIFT  = 18;
static constexpr int      TXDESC32_RETRY_LIMIT_MGNT   = 6;

// ============================================================
// FPGA / RF SIPI registers for channel tune
// (wifit3: constants.py L147-184)
// ============================================================
static constexpr uint16_t REG_FPGA0_RF_MODE          = 0x0800;
static constexpr uint16_t REG_FPGA0_XA_HSSI_PARM2    = 0x0824;
static constexpr uint16_t REG_FPGA0_XB_HSSI_PARM2    = 0x082C;
static constexpr uint16_t REG_FPGA0_XA_LSSI_PARM     = 0x0840;
static constexpr uint16_t REG_FPGA0_XA_RF_INT_OE     = 0x0860;
static constexpr uint16_t REG_FPGA0_XB_RF_INT_OE     = 0x0864;
static constexpr uint16_t REG_FPGA1_RF_MODE           = 0x0900;
static constexpr uint16_t REG_OFDM0_TRX_PATH_ENABLE   = 0x0C04;
static constexpr uint32_t FPGA_RF_MODE                 = 1 << 0;
static constexpr uint32_t FPGA_RF_MODE_CCK             = 1 << 24;
static constexpr uint32_t FPGA_RF_MODE_OFDM            = 1 << 25;

// RF6052 channel register
static constexpr uint8_t  RF6052_REG_MODE_AG     = 0x18;
static constexpr uint32_t MODE_AG_CHANNEL_MASK   = 0x3FF;

// LSSI encoding for write_rfreg
static constexpr int      FPGA0_LSSI_PARM_ADDR_SHIFT = 20;
static constexpr uint32_t FPGA0_LSSI_PARM_DATA_MASK  = 0x000FFFFF;

// ============================================================
// LLT init (regs.h:463-466)
// ============================================================
static constexpr uint32_t LLT_OP_WRITE = 0x1 << 30;
static constexpr uint32_t LLT_OP_MASK  = 0x3 << 30;

// 8192EU-specific FIFO page counts
// (kernel: 8192e.c fileops — differs from 8188EUS)
static constexpr int TOTAL_PAGE_NUM_8192E   = 0xF8;
static constexpr int PAGE_NUM_HI_PQ_8192E   = 0x0E;
static constexpr int PAGE_NUM_LO_PQ_8192E   = 0x0A;
static constexpr int PAGE_NUM_NORM_PQ_8192E  = 0x0A;
static constexpr int LAST_LLT_ENTRY_8192E    = 247;
static constexpr uint16_t TRXFF_BOUNDARY_8192E = 0x3F7F;

// ============================================================
// Decoded RX descriptor
// (wifit3: rx.py RxDesc16 dataclass, L86-108)
// ============================================================
struct RxDesc16 {
    uint16_t pkt_len;
    bool     crc_err;
    bool     icv_err;
    int      drv_info_sz_bytes;   // w0[19:16] × 8
    int      shift;               // w0[25:24]
    bool     phy_stats_present;   // w0[26]
    int      pkt_cnt;             // w2[23:16]
    int      rxmcs;               // w3[5:0]
    int      rpt_sel;             // w3[15:14] — non-zero = TX report

    int mpduOffset() const {
        return RX_PKT_DESC_SZ + drv_info_sz_bytes + shift;
    }
    int totalSize() const {
        return mpduOffset() + pkt_len;
    }
};

// ============================================================
// A raw captured frame delivered to the callback
// ============================================================
struct RawFrame {
    std::vector<uint8_t> data;
    int rssi_dbm;
    int channel;
};

// ============================================================
// RTL8192EUDriver — the main driver class
// ============================================================
class RTL8192EUDriver {
public:
    RTL8192EUDriver();
    ~RTL8192EUDriver();

    // ---- lifecycle (build plan Step 4 order) ----

    // Step 4.1: USB enumerate + claim
    bool open(uint16_t vendorId = RTL8192EU_VID_REALTEK,
              uint16_t productId = RTL8192EU_PID_818B);

    // Step 4.2: firmware upload (port of wifit3 firmware.py)
    bool uploadFirmware(const uint8_t* fwData, size_t len);

    // Step 4.3: monitor mode (port of wifit3 mac.py)
    bool setMonitorMode(bool enabled);

    // Step 4.4: channel tune (port of wifit3 chan.py)
    bool setChannel(int channel);

    // Step 4.3 (RX): passive capture loop
    using FrameCallback = std::function<void(const RawFrame&)>;
    void startCapture(FrameCallback onFrame);
    void stopCapture();

    // Step 4.5: TX inject (port of wifit3 tx.py)
    bool injectFrame(const std::vector<uint8_t>& frameBytes);

    // Teardown
    void close();

    // ---- state queries ----
    bool isOpen() const;
    std::string macAddress() const;
    int currentChannel() const;

private:
    // ---- USB transport (port of wifit3 transport.py) ----
    uint8_t  read8(uint16_t addr);
    uint16_t read16(uint16_t addr);
    uint32_t read32(uint16_t addr);
    void write8(uint16_t addr, uint8_t val);
    void write16(uint16_t addr, uint16_t val);
    void write32(uint16_t addr, uint32_t val);
    void writeBlock(uint16_t addr, const uint8_t* data, size_t len);

    // read-modify-write helpers (wifit3: transport.py L106-122)
    void write8Set(uint16_t addr, uint8_t mask);
    void write8Clr(uint16_t addr, uint8_t mask);
    void write16Set(uint16_t addr, uint16_t mask);
    void write16Clr(uint16_t addr, uint16_t mask);
    void write32Set(uint16_t addr, uint32_t mask);
    void write32Clr(uint16_t addr, uint32_t mask);

    // ---- power on (port of wifit3 driver.py L439-501) ----
    void powerOn();
    void disabledToEmu();
    void emuToActive();

    // ---- firmware internals (port of wifit3 firmware.py) ----
    void writeN(uint16_t addr, const uint8_t* buf, size_t len);
    void reset8051();
    void firmwareSelfReset();
    void downloadFirmware(const uint8_t* fwBlob, size_t blobLen);
    void startFirmware();

    // ---- MAC init (port of wifit3 mac.py) ----
    void postFwMacInit();
    bool isChipWarm();
    void applyMonitorRxFilter();
    void enableRxDataPath();

    // ---- RF SIPI (port of wifit3 phy.py) ----
    void writeRfReg(int path, uint8_t reg, uint32_t data);
    uint32_t readRfReg(int path, uint8_t reg);

    // ---- RX internals (port of wifit3 rx.py) ----
    RxDesc16 parseRxDesc16(const uint8_t* buf);
    int parseRssi(const uint8_t* phyStats, int rxmcs);
    void rxLoop();

    // ---- TX internals (port of wifit3 tx.py) ----
    void buildTxDescMgmt(uint8_t* desc, uint16_t pktLen, bool isBroadcast);
    void calcTxDescCsum(uint8_t* desc);

    // ---- LLT init ----
    bool lltWrite(uint32_t address, uint32_t data);
    void initLlt();

    // ---- endpoint probing ----
    void probeEndpoints();

    // ---- state ----
    libusb_context*         _ctx       = nullptr;
    libusb_device_handle*   _handle    = nullptr;
    std::atomic<bool>       _open{false};
    std::atomic<bool>       _capturing{false};
    int                     _currentChannel = 1;
    uint8_t                 _bulkInEp  = 0;
    uint8_t                 _bulkOutEpMgmt = 0;
    std::vector<uint8_t>    _bulkOutEps;
    std::string             _macAddress;
    FrameCallback           _frameCallback;
    std::mutex              _usbMutex;

    // CCK RSSI lookup (wifit3: rx.py L135 — TSMC table)
    static constexpr int CCK_LNA_GAIN_TSMC[8] = {29, 20, 12, 3, -6, -15, -24, -33};
};
