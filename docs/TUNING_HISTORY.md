# Honda City 7G Lateral Tuning History

## Platform
- Car: Honda City 7G (Brazil, 2023)
- EPS: 39990-T14-B030 (Bosch Radarless)
- Device: comma 3X (Tailscale: 100.64.168.48)
- EPS hardware torque ceiling: 4096
- Low-speed lockout: 23 km/h (EPS firmware enforced)

---

## Stock (baseline)
Controller: generic torque (fallback `else` block)
```
STEER_MAX = 2560
steerRatio = 19.0
steerActuatorDelay = 0.1
LAT_ACCEL_FACTOR = 1.2
FRICTION = 0.23
```
**Feel:** Weak, sluggish, oscillates on curves, delayed response.

---

## v1 — Dedicated PID + max torque
Changed from generic torque controller to speed-dependent PID. Copied Civic 2022 baseline.
```
STEER_MAX = 4096
kpBP/kpV = [[0, 10], [0.05, 0.5]]
kiBP/kiV = [[0, 10], [0.0125, 0.125]]
kf = 0.00006 (default)
LAT_ACCEL_FACTOR = 2.5
FRICTION = 0.15
steerRatio = 19.0
steerActuatorDelay = 0.1
```
**Files changed:** interface.py (added City 7G elif block), override.toml
**Feel:** Noticeably stronger, but still sluggish on curve entry. Saturation on sharp curves.

---

## v2 — Increased kp low-speed + added kf
```
kpV = [0.05, 0.5] -> [0.15, 0.5]   (3x low-speed proportional)
kf = 0.00006 -> 0.00012             (2x feedforward)
```
**Feel:** Better initial response, but still saturates for extended periods on curves. Oscillation reduced.

---

## v3 — Increased ki (integral gains)
```
kiV = [0.0125, 0.125] -> [0.02, 0.15]  (+60% low, +20% high)
```
**Telemetry analysis (v2 vs v3):**
- v2 had 187 saturation samples in one segment
- v3 had 44 saturation events in ~8 min — faster recovery from saturation
- Saturation threshold: ~16° angle at >44 kph (EPS hardware ceiling)

**Saturation clusters observed (v3):**
| Time | Speed | Angle | Duration | Direction |
|------|-------|-------|----------|-----------|
| 5-7s | 57-58 kph | +17-19° | 1.5s | right |
| 30-33s | 60-63 kph | -13 to -17° | 4s | left |
| 38-47s | 64-65 kph | -20 to -21° | ~5s | left |
| 72-77s | 65-66 kph | +18° | 5.5s | right |
| 275-276s | 53 kph | -20 to -22° | 1.5s | left |
| 315-362s | 44-61 kph | +/-17-22° | scattered | both |

**Feel:** User reported "better." Controller recovers faster from saturation.

---

## v4 — Increased kf (feedforward)
```
kf = 0.00012 -> 0.00015  (+25% feedforward)
```
**Rationale:** Faster initial torque response on curve entry, before PID error accumulates.
**Status:** Applied on device, not yet tested with ignition cycle.

---

## v5 — steerRatio + steerActuatorDelay (current)
```
steerRatio = 19.0 -> 16.5     (closer to Civic 2022's 15.2)
steerActuatorDelay = 0.1 -> 0.12  (more anticipation)
```
**Rationale:**
- steerRatio 19.0 was likely a rough estimate. Lowering it makes the controller
  think less steering angle is needed per curve, so it applies torque more aggressively.
- steerActuatorDelay increase gives the controller slightly more lookahead for smoother
  curve entry.

**Status:** Applied on device, waiting for ignition cycle.

## v6 — steerRatio refinement
```
steerRatio = 16.5 -> 17.5  (middle ground — 16.5 was too aggressive)
```
**Telemetry (v6 vs v5):**
- v5: 31 sat samples, first at +8° (too aggressive — saturating on gentle curves)
- v6: 31 sat samples, first at +13° (better onset angle)
- Only 2 saturation clusters vs 5 in v5 — much cleaner profile
**Feel:** User reported "feels better" — good compromise between responsiveness and smoothness.

---

## v7 — Faster torque ramp + feedforward (current)
```
STEER_DELTA_UP/DOWN = 3 -> 5   (67% faster torque ramp, per-car override)
kf = 0.00015 -> 0.00018         (20% more feedforward)
```
**Rationale:** Faster ramp gets to max torque quicker on curve entry. Higher feedforward
gives more immediate response before PID error accumulates.
**Files changed:** values.py (CarControllerParams.__init__ per-car override), interface.py
**Status:** Applied on device, waiting for test.

---

## Full Parameter Comparison

| Parameter | Stock | v1 | v2 | v3 | v4 | v5 | v6 | v7 |
|-----------|-------|----|----|----|----|----|----|----|
| Controller | torque | PID | PID | PID | PID | PID | PID | PID |
| STEER_MAX | 2560 | 4096 | 4096 | 4096 | 4096 | 4096 | 4096 | 4096 |
| kpV low | N/A | 0.05 | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 |
| kpV high | N/A | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 |
| kiV low | N/A | 0.0125 | 0.0125 | 0.02 | 0.02 | 0.02 | 0.02 | 0.02 |
| kiV high | N/A | 0.125 | 0.125 | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 |
| kf | 0.00006 | 0.00006 | 0.00012 | 0.00012 | 0.00015 | 0.00015 | 0.00015 | **0.00018** |
| LAT_ACCEL_FACTOR | 1.2 | 2.5 | 2.5 | 2.5 | 2.5 | 2.5 | 2.5 | 2.5 |
| FRICTION | 0.23 | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 | 0.15 |
| steerRatio | 19.0 | 19.0 | 19.0 | 19.0 | 19.0 | 16.5 | 17.5 | 17.5 |
| steerActuatorDelay | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.12 | 0.12 | 0.12 |
| STEER_DELTA_UP | 3 | 3 | 3 | 3 | 3 | 3 | 3 | **5** |
| STEER_DELTA_DOWN | 3 | 3 | 3 | 3 | 3 | 3 | 3 | **5** |

## Saturation Comparison

| Version | Sat samples | First sat angle | Clusters | User feel |
|---------|------------|----------------|----------|-----------|
| v2 | 187 | +17° | many | baseline |
| v3 | 44 | +17° @ 57 kph | 6 | "better" |
| v5 | 31 | +8° @ 61 kph | 5 | "bit worse" |
| v6 | 31 | +13° @ 59 kph | 2 | "feels better" |
| v7 | ? | ? | ? | pending |

---

## Key Findings
1. EPS hardware ceiling at 4096 is the main bottleneck — no software tuning can push past it
2. Saturation occurs on curves >13-17° at speeds >50 kph
3. PID controller with aggressive gains is significantly better than generic torque controller
4. steerRatio has big impact on feel — 16.5 too aggressive, 17.5 good middle ground
5. The City 7G EPS (39990-T14-B030) needs firmware modding for further improvement
6. Only EPS firmware can also remove the 23 km/h low-speed lockout

## Next Steps
- [ ] Test v7 (STEER_DELTA + kf bump) and compare
- [ ] Commit v5 if improvement confirmed
- [ ] Research EPS firmware modding path (rwd-xray, AutoECU, bench testing)
- [ ] Consider STEER_DELTA_UP/DOWN increase if ramp speed still feels slow
