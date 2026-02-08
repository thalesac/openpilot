# Honda City 7G (Brazil) — EPS Research & Tuning Guide

> **Vehicle**: Honda City 7th Gen, Brazilian market, 2023+
> **EPS Part Number**: `39990-T14-B030`
> **Platform**: Honda Bosch Radarless (`BOSCH_RADARLESS`)
> **DBC**: `honda_bosch_radarless_generated`
> **Date**: 2026-02-08

---

## Table of Contents

1. [EPS System Architecture](#1-eps-system-architecture)
2. [CAN Messages & Steering Control](#2-can-messages--steering-control)
3. [Current Software Tuning (Stock)](#3-current-software-tuning-stock)
4. [Tuning Comparison vs Other Bosch Radarless Hondas](#4-tuning-comparison-vs-other-bosch-radarless-hondas)
5. [Low-Speed Lockout (23 km/h)](#5-low-speed-lockout-23-kmh)
6. [EPS Firmware Modding Ecosystem](#6-eps-firmware-modding-ecosystem)
7. [EPS Physical Location & Removal](#7-eps-physical-location--removal)
8. [Bench Testing Setup](#8-bench-testing-setup)
9. [Firmware Extraction & Reverse Engineering](#9-firmware-extraction--reverse-engineering)
10. [Software Tuning Opportunities](#10-software-tuning-opportunities)
11. [References & Resources](#11-references--resources)

---

## 1. EPS System Architecture

The Honda City 7G uses a **Honda Bosch EPS** (Electric Power Steering) system with two physically separate components:

| Component | Location | Function |
|-----------|----------|----------|
| **EPS Motor** | Engine bay, bolted onto the steering rack (pinion-assist type) | Brushless DC motor that applies steering torque |
| **EPS Control Unit (ECU)** | Under the dashboard, driver's side, small metal box (~10cm) | Receives CAN commands, controls the motor, enforces torque/speed limits |

The EPS motor shaft gear rotates a worm wheel gear on the pinion shaft. The motor has two connectors: a 3P motor power connector and an 8P angle sensor connector.

The EPS ECU contains: system control CPU, FET drive circuit, H-type FET bridge, power relay, fail-safe relay, and current detection circuitry. It communicates via **F-CAN bus** with the ECM/PCM and gauge control module. It has two connectors: Connector A (11P) and Connector B (16P).

For firmware modding, **only the ECU matters** — flashing is done over CAN through the OBD-II port without physical access to the ECU.

---

## 2. CAN Messages & Steering Control

### Steering Command (STEERING_CONTROL) — Message ID: 0x194 (404)

Sent by openpilot to the EPS:

```
BO_ 404 STEERING_CONTROL: 4 EON
 SG_ SET_ME_X00        : 22|7@0+  (1,0)      [0|127]       "" EPS
 SG_ STEER_TORQUE_REQUEST : 23|1@0+ (1,0)     [0|1]         "" EPS
 SG_ COUNTER           : 29|2@0+  (1,0)       [0|15]        "" EPS
 SG_ CHECKSUM          : 27|4@0+  (1,0)       [0|3]         "" EPS
 SG_ STEER_TORQUE      : 7|16@0-  (-1,0)      [-32767|32767] "" EPS
```

Key fields:
- `STEER_TORQUE`: Signed 16-bit, requested steering torque (negative = right, positive = left)
- `STEER_TORQUE_REQUEST`: Boolean flag (0 = no request, 1 = active steering)
- `COUNTER`: 2-bit rolling counter for message validation
- `CHECKSUM`: 4-bit Honda-specific checksum

### Steering Feedback (STEER_STATUS) — Message ID: 0x18F (399)

Sent by the EPS back to openpilot:

```
BO_ 399 STEER_STATUS: 7 EPS
 SG_ STEER_TORQUE_SENSOR  : 7|16@0-  (-1,0)   [-31000|31000] "tbd" EON
 SG_ STEER_ANGLE_RATE     : 23|16@0- (-0.1,0)  [-31000|31000] "deg/s" EON
 SG_ STEER_STATUS         : 39|4@0+  (1,0)     [0|15]         "" EON
 SG_ STEER_CONTROL_ACTIVE : 35|1@0+  (1,0)     [0|1]          "" EON
 SG_ STEER_CONFIG_INDEX   : 43|4@0+  (1,0)     [0|15]         "" EON
 SG_ COUNTER              : 53|2@0+  (1,0)     [0|3]          "" EON
 SG_ CHECKSUM             : 51|4@0+  (1,0)     [0|15]         "" EON
```

### STEER_STATUS Values

| Value | Name | Meaning |
|-------|------|---------|
| 0 | NORMAL | Steering ready and accepting commands |
| 1 | DRIVER_STEERING | Driver override detected |
| 2 | NO_TORQUE_ALERT_1 | Temporary, usually ignored |
| 3 | LOW_SPEED_LOCKOUT | Below minSteerSpeed — EPS rejects commands |
| 4 | NO_TORQUE_ALERT_2 | Bump or steering nudge |
| 5 | FAULT_1 | Steering fault |
| 6 | TMP_FAULT | Temporary fault |
| 7 | PERMANENT_FAULT | Permanent fault — steering disabled |

### Torque Limit Enforcement Chain

1. **Openpilot application layer**: Max torque ±2560, rate limit ±3 units per 10ms
2. **Panda safety layer**: Blocks all steering if `controls_allowed = false`, validates checksum/counter
3. **EPS firmware**: Enforces its own torque limits (typically ±4096 for Bosch), speed lockout, and rate limiting

---

## 3. Current Software Tuning (Stock)

### Platform Config (`opendbc_repo/opendbc/car/honda/values.py`)

```python
HONDA_CITY_7G = HondaBoschPlatformConfig(
    [HondaCarDocs("Honda City (Brazil only) 2023", "All")],
    CarSpecs(
        mass=3125 * CV.LB_TO_KG,        # 1417 kg
        wheelbase=2.6,                    # meters
        steerRatio=19.0,                  # steering ratio
        centerToFrontRatio=0.41,
        minSteerSpeed=23. * CV.KPH_TO_MS  # 6.39 m/s — EPS lockout speed
    ),
    {Bus.pt: 'honda_bosch_radarless_generated'},
    flags=HondaFlags.BOSCH_RADARLESS,
)
```

### Torque Override (`opendbc_repo/opendbc/car/torque_data/override.toml`)

```toml
"HONDA_CITY_7G" = [1.2, 1.2, 0.23]
# [LAT_ACCEL_FACTOR, MAX_LAT_ACCEL_MEASURED, FRICTION]
```

| Parameter | Value | Meaning |
|-----------|-------|---------|
| LAT_ACCEL_FACTOR | 1.2 | Torque-to-lateral-accel conversion. Higher = less responsive |
| MAX_LAT_ACCEL_MEASURED | 1.2 m/s² | Maximum lateral acceleration capability |
| FRICTION | 0.23 | Steering friction compensation coefficient |

### Controller Parameters

| Parameter | Value | Source |
|-----------|-------|--------|
| Controller Type | Torque (default fallback) | interface.py else clause |
| STEER_MAX | 2560 | lateralParams.torqueV |
| torqueBP / torqueV | [0, 2560] / [0, 2560] | Linear mapping, no speed dependency |
| STEER_DELTA_UP | 3 per cycle (100 Hz) | CarControllerParams |
| STEER_DELTA_DOWN | 3 per cycle (100 Hz) | CarControllerParams |
| STEER_THRESHOLD | 600 | values.py |
| steerActuatorDelay | 0.15 s | interface.py |
| STEER_GLOBAL_MIN_SPEED | 3 mph (1.34 m/s) | CarControllerParams |

### EPS Fingerprint (`opendbc_repo/opendbc/car/honda/fingerprints.py`)

```python
CAR.HONDA_CITY_7G: {
    (Ecu.eps, 0x18da30f1, None): [
        b'39990-T14-B030\x00\x00',
    ],
}
```

---

## 4. Tuning Comparison vs Other Bosch Radarless Hondas

| Parameter | City 7G | Civic 2022 | HR-V 3G | City's Gap |
|-----------|---------|------------|---------|------------|
| **Max Torque** | 2560 | 4096 | 4096 | **62% of others** |
| **LAT_ACCEL_FACTOR** | 1.2 | 2.5 | 2.5 | **2x less responsive** |
| **Friction** | 0.23 | 0.15 | 0.20 | Highest of all |
| **steerRatio** | 19.0 | 15.38 | 15.2 | 25% slower |
| **Controller** | Torque (default) | PID (tuned) | PID (tuned) | Generic fallback |
| **steerActuatorDelay** | 0.15 s | 0.15 s | 0.15 s | Same |
| **STEER_THRESHOLD** | 600 | 600 | 600 | Same |
| **minSteerSpeed** | 23 km/h | inherited | inherited | City has explicit lockout |

### Key Finding

The Honda City 7G is running **conservative default parameters** that were never specifically optimized. It operates at ~60% of the capability that the Civic 2022 and HR-V 3G use on the same Bosch radarless platform. There is significant room for improvement through software-only changes.

---

## 5. Low-Speed Lockout (23 km/h)

### How It Works

The 23 km/h minimum steer speed is **enforced by the EPS firmware itself**, not just openpilot software.

1. Below 23 km/h, the EPS reports `STEER_STATUS = 3` (`LOW_SPEED_LOCKOUT`) on CAN
2. Openpilot reads this status and disables steering commands
3. Sending torque commands anyway causes **oscillation and mechanical noise** because the EPS actively fights back

### Code Path

```python
# carcontroller.py:227
steering_available = CS.out.cruiseState.available and CS.out.vEgo > self.CP.minSteerSpeed

# carstate.py:103-119 — hysteresis to prevent flickering
if CarControllerParams.STEER_GLOBAL_MIN_SPEED < ret.vEgo < (self.CP.minSteerSpeed + 0.5):
    self.low_speed_alert = True
elif ret.vEgo > (self.CP.minSteerSpeed + 1.):
    self.low_speed_alert = False
```

### Resolution

**The only way to remove this lockout is to modify the EPS firmware** to set the minimum speed threshold to 0. The `eps_tool.py` in `rwd-xray` does exactly this for supported Honda EPS variants.

---

## 6. EPS Firmware Modding Ecosystem

### Overview

An active community exists around modifying Honda Bosch EPS firmware. The typical modifications:

1. **Double torque tables** in the unused LKAS range (0xA00-0xE00)
2. **Remove low-speed lockout** (set min steer speed to 0 mph)
3. **Mark firmware** with a `,` character so openpilot can detect the mod

### Key Tools & Repositories

| Tool | URL | Purpose |
|------|-----|---------|
| **rwd-xray** | [github.com/cfranyota/rwd-xray](https://github.com/cfranyota/rwd-xray) | Main EPS firmware extractor and patcher (`eps_tool.py`) |
| **tonton81/autotuner** | [github.com/tonton81/autotuner](https://github.com/tonton81/autotuner) | Alternative EPS tool with torque/filter/speed table mods |
| **wirelessnet2/openpilot (AutoECU)** | [github.com/wirelessnet2/openpilot](https://github.com/wirelessnet2/openpilot) | On-device EPS flashing tool (branch: AutoECU) |
| **HondaReflashTool** | [github.com/bouletmarc/HondaReflashTool](https://github.com/bouletmarc/HondaReflashTool) | General Honda ECU reflash tool (J2534) |
| **sunnypilot** | [github.com/sunnypilot/sunnypilot](https://github.com/sunnypilot/sunnypilot) | Openpilot fork with explicit EPS mod support |

### Successfully Modded EPS Part Numbers

| Part Number | Vehicle | Status |
|-------------|---------|--------|
| 39990-TLA-A040 | Honda CR-V | Supported |
| 39990-TPA-G030 | Honda CR-V | Supported |
| 39990-TBA-A030 | Honda Civic Sedan (2016) | Supported |
| 39990-TBA-C120 | Honda Civic Sedan (2019) | Supported |
| 39990-TBA-C020 | Honda Civic Sedan Sport (2019) | Supported |
| 39990-TEG-A010 | Honda Civic Sedan (Japan) | Supported |
| 39990-TEA-T330 | Honda Civic Hatch (Australia) | Supported |
| 39990-TGG-A120 | Honda Civic Hatch (LX/EX-L) | Supported |
| 39990-TGN-E120 | Honda Civic Hatch (Europe) | Supported |
| 39990-TGG-A020 | Honda Civic Hatch (Sport/Touring) | Supported |
| 39990-TRW-A020 | Honda Clarity | Supported (most documented) |
| 39990-TXM-A040 | Honda Insight | Supported |
| 39990-TVA-A150 | Honda Accord | In development |
| **39990-T14-B030** | **Honda City 7G (Brazil)** | **NOT YET SUPPORTED** |

### T14 Variant Assessment

**Favorable factors:**
- Same Honda Bosch EPS architecture as all successfully modded variants
- Same `39990-` prefix part numbering convention
- Same `.rwd.gz` firmware format expected
- Universal security key (`\x01\x11\x01\x12\x11\x20`) likely works
- `minSteerSpeed` of 23 km/h is similar to other Bosch models

**Risk factors:**
- Newer Bosch radarless platform generation
- Brazil-market, may have unique firmware characteristics
- No community members currently working on this variant
- Bricking risk (mitigated by bench testing with salvage EPS)

### Comma.ai's Position on EPS Mods

- Comma.ai detects modified EPS firmware by monitoring for abnormally high torques
- Mods up to ~2x are generally tolerated; substantially over 2x may result in server bans
- Users wanting EPS mods have migrated to **sunnypilot**
- Reference: [Safer Control of Steering (comma.ai blog)](https://comma-ai.medium.com/safer-control-of-steering-362f3526c9ab)

---

## 7. EPS Physical Location & Removal

### For Firmware Flashing (on the car)

**No physical access needed.** Flashing is done through the **OBD-II port** under the steering wheel using the comma 3X (which has an integrated panda CAN interface). The process takes ~2 minutes with the car in ON position, engine off.

### For Bench Testing (salvage EPS removal)

The EPS ECU removal procedure (Honda Fit/City platform):

1. Disconnect negative battery cable, wait 10+ minutes (SRS capacitor discharge)
2. Remove the under-dash panel (driver's side)
3. Remove the under-dash fuse/relay box
4. Disconnect EPS control unit Connector A (11P) and Connector B (16P)
5. Loosen bolt E, remove bolt F and nut G from the bracket
6. Pull out the EPS control unit with bracket

**Fasteners:** All M6 x 1.0mm, torque 9.8 N-m (7.2 lbf-ft)
**Difficulty:** Easy-moderate, ~1 hour, standard metric tools only
**Airbag concern:** None if only removing the ECU (no steering wheel removal needed)

**Reference:** [hfitinfo.com/hofi-718](https://www.hfitinfo.com/hofi-718.html)

### Calibration After Reinstall

If the EPS ECU or motor is replaced, the **torque sensor neutral position must be recalibrated** using Honda Diagnostic System (HDS) or compatible bi-directional scan tool. Standard OBD-II scanners cannot do this. Dealer cost is approximately $135 USD. Ambient temperature must exceed 20C during calibration.

---

## 8. Bench Testing Setup

### Required Hardware

| Item | Purpose | Approx Cost |
|------|---------|-------------|
| Salvage EPS unit (39990-T14-B030) | Safe testing target | Varies |
| 12V DC power supply (10A+ capable) | Power the EPS ECU | ~$30 |
| CAN interface (see options below) | Communicate with EPS | See below |
| EPS wiring harness / connector | Connect to bench CAN | ~$15 |

### CAN Interface Options

| Option | What It Is | Pros | Cons |
|--------|-----------|------|------|
| **Comma 3X** | Your existing device with integrated panda | Already own it, runs `eps-update.py` directly | Ties up your comma device |
| **Arduino + MCP2515** | DIY CAN transceiver (~$10-15) | Cheap dedicated bench tool | Requires custom code for UDS |
| **Standalone Panda** | comma.ai's USB CAN dongle | Purpose-built, well supported | ~$100 if purchased separately |

### What the Comma Panda Is

The **panda** is comma.ai's CAN bus interface board. It's the hardware that physically connects to the car's CAN network. In older comma setups, it was a separate USB dongle (white/grey/red panda). In the **comma 3X, the panda is integrated inside the device**. It handles CAN message sending/receiving, safety validation, and is the bridge between openpilot software and the car's electrical systems.

### Bench EPS Activation Requirements

The EPS ECU expects several signals to activate:
- **12V power supply** (motor can draw significant current)
- **Vehicle speed** via F-CAN bus (can be simulated)
- **Engine RPM** via CAN (can be simulated)
- **Torque sensor input** via SENT (Single Edge Nibble Transmission) protocol (may need emulation with PIC microcontroller)

---

## 9. Firmware Extraction & Reverse Engineering

### Step-by-Step Process

#### Step 1: Obtain Stock Firmware

Option A — Dump from live EPS via CAN:
```
1. Connect panda/comma device to EPS (via OBD-II or bench harness)
2. Use UDS protocol to enter diagnostic session
3. Security access with key: \x01\x11\x01\x12\x11\x20 (universal Honda Bosch — unconfirmed for T14)
4. Read firmware memory region
5. Save binary dump
```

Option B — Download `.rwd.gz` from Honda firmware distribution servers (if available for T14)

Useful tool: `panda/examples/query_fw_versions.py` to identify the ECU before attempting a dump.

#### Step 2: Analyze the Binary

- Firmware is likely Renesas/SH2A or ARM Cortex-based Bosch MCU
- Compare byte patterns against known modded EPS firmwares (e.g., TLA-A040, TBA-A030)
- Locate:
  - **Torque lookup tables** (7 rows of speed-indexed values)
  - **Speed lockout threshold** (the 23 km/h value)
  - **Filter/damping tables**
  - **Firmware version string**

#### Step 3: Patch

Using `eps_tool.py` as reference (once offsets are found):

1. Double torque values in the 0xA00-0xE00 range (unused by stock LKAS)
2. Set minimum speed threshold to 0
3. Insert `,` marker in firmware version string (for openpilot detection)
4. Recalculate checksums

The modified torque curve should be "about halfway between stock curve and linear slope" to avoid instability. Hardware clamping at 0x067F (1663) provides an upper safety bound regardless of software values.

#### Step 4: Flash

```bash
# Kill openpilot first (if on comma device)
tmux kill-server

# Flash the modified firmware
python eps-update.py --bus 1 --skip-checksum --danger mod.rwd
```

**Always test on the bench EPS first.** Once verified, flash on the car through OBD-II (~2 minutes, car ON, engine off).

#### Step 5: Recovery

- **Bench EPS bricked:** Re-flash stock firmware or use Honda HDS dealer tool
- **Car EPS bricked:** Swap in the bench EPS (same part number) or dealer reflash

---

## 10. Software Tuning Opportunities

These changes can be made **without any EPS firmware modification**, purely in openpilot/opendbc code:

### Safe Changes (well within hardware limits)

| Parameter | Current | Target | Change | File |
|-----------|---------|--------|--------|------|
| torqueBP/torqueV | [0, 2560] | [0, 4096] | +60% max torque | interface.py |
| LAT_ACCEL_FACTOR | 1.2 | 2.0-2.5 | 2x more responsive | override.toml |
| FRICTION | 0.23 | 0.18-0.20 | Reduce friction comp | override.toml |
| Controller | Torque (default) | PID (explicit) | Dedicated tuning | interface.py |

### Requires Testing / Validation

| Parameter | Current | Notes |
|-----------|---------|-------|
| steerRatio | 19.0 | Verify against actual physical specs — may be inaccurate |
| steerActuatorDelay | 0.15 s | May benefit from measurement with step response |
| STEER_DELTA_UP/DOWN | 3/3 | Could increase for faster response, but may cause oscillation |

### What These Won't Fix

- **Low-speed lockout (23 km/h)** — requires EPS firmware mod
- **EPS hardware torque ceiling** — requires EPS firmware mod
- **EPS rate limiting** — internal to EPS firmware

---

## 11. References & Resources

### Openpilot / opendbc Source Files

- `opendbc_repo/opendbc/car/honda/values.py` — Car definitions and configs
- `opendbc_repo/opendbc/car/honda/interface.py` — Lateral/longitudinal tuning parameters
- `opendbc_repo/opendbc/car/honda/carcontroller.py` — Steering command generation
- `opendbc_repo/opendbc/car/honda/carstate.py` — Steering state reading and fault detection
- `opendbc_repo/opendbc/car/honda/fingerprints.py` — EPS firmware fingerprints
- `opendbc_repo/opendbc/car/torque_data/override.toml` — Torque tuning overrides
- `opendbc_repo/opendbc/safety/modes/honda.h` — Panda safety enforcement
- `opendbc_repo/opendbc/dbc/honda_bosch_radarless_generated.dbc` — CAN message definitions

### Community & Tools

- [rwd-xray (EPS patcher)](https://github.com/cfranyota/rwd-xray)
- [tonton81/autotuner](https://github.com/tonton81/autotuner)
- [wirelessnet2/openpilot AutoECU](https://github.com/wirelessnet2/openpilot)
- [HondaReflashTool](https://github.com/bouletmarc/HondaReflashTool)
- [sunnypilot](https://github.com/sunnypilot/sunnypilot)

### Guides & Articles

- [Honda Clarity EPS Mod (Eric Shi / wirelessnet2)](https://wirelessnet2.medium.com/eps-fw-modifications-for-the-honda-clarity-39990-trw-a020-beta-373b3e7ba528)
- [Civic EPS Mod Guide (jrdsgl.com)](https://jrdsgl.com/how-to-modify-your-civics-eps-firmware-with-a-comma3x/)
- [Safer Control of Steering (comma.ai)](https://comma-ai.medium.com/safer-control-of-steering-362f3526c9ab)

### Honda Service Manuals (Fit/City Platform)

- [EPS Control Unit Removal](https://www.hfitinfo.com/hofi-718.html)
- [EPS Motor Removal](https://www.hfitinfo.com/hofi-719.html)
- [EPS System Description](https://www.hfitinfo.com/hofi-720.html)

### Community Discussion

- comma.ai Discord `#fw-mods` channel
- [Ridgeline EPS mod bounty thread](https://www.ridgelineownersclub.com/threads/2022-ridgeline-eps-mod-1000-bounty.236326/)

### Brazilian Market Parts

- Search "Coluna de Direcao Eletrica Honda City" for salvage EPS units
- [SpeedParts](https://speedparts.com.br/) and [DHME](https://www.dhme.com.br/) list Honda City EPS assemblies
