# Honda City 7G Openpilot Fork

## Project Overview
Openpilot fork for Honda City 7G (Brazil, 2023). Based on mvl-boston/openpilot with custom lateral/longitudinal tuning and radarless brake fix.

- **Car:** Honda City 7G, Brazilian market, 2023
- **EPS:** 39990-T14-B030 (Bosch Radarless, no radar)
- **Device:** comma 3X (Tailscale IP: 100.64.168.48, user: comma)
- **Platform:** BOSCH_RADARLESS, DBC: honda_bosch_radarless_generated
- **EPS hardware torque ceiling:** 4096
- **Low-speed lockout:** 23 km/h (EPS firmware enforced)

## Git Remotes

### Parent repo (openpilot)
| Remote | URL | Purpose |
|--------|-----|---------|
| `origin` | https://github.com/mvl-boston/openpilot.git | Base fork (mvl-boston) |
| `upstream` | https://github.com/commaai/openpilot.git | Official openpilot (pull updates) |
| `thales` | git@github.com:thalesac/openpilot.git | Personal fork (push here) |

### Submodule (opendbc_repo)
| Remote | URL | Purpose |
|--------|-----|---------|
| `origin` | https://github.com/commaai/opendbc.git | Official opendbc |
| `mvlboston` | https://github.com/mvl-boston/opendbc.git | MVL's fork (reference branches) |
| `thales` | git@github.com:thalesac/opendbc.git | Personal fork (push here) |

### Pulling upstream updates
```bash
# openpilot
git fetch upstream master
git merge upstream/master

# opendbc (from repo root)
cd opendbc_repo
git fetch origin master
git merge origin/master
```

### Pushing changes
```bash
# openpilot (LFS push is disabled — we only change code, not binaries)
git push thales master

# opendbc (from opendbc_repo/)
cd opendbc_repo
git push thales honda-city-7g
```

## Key Files (Honda City 7G)

### Lateral tuning
- `opendbc_repo/opendbc/car/honda/interface.py` — PID gains, steerActuatorDelay, kf (City 7G elif block ~line 203)
- `opendbc_repo/opendbc/car/honda/values.py` — steerRatio, mass, wheelbase, STEER_DELTA override in CarControllerParams.__init__
- `opendbc_repo/opendbc/car/torque_data/override.toml` — LAT_ACCEL_FACTOR, FRICTION

### Longitudinal / braking
- `opendbc_repo/opendbc/car/honda/hondacan.py` — BRAKE_REQUEST fix (radarless), ACC_CONTROL commands
- `opendbc_repo/opendbc/car/honda/carcontroller.py` — gas/brake command generation, rate limiting

### Car state / detection
- `opendbc_repo/opendbc/car/honda/carstate.py` — STEER_STATUS, LOW_SPEED_LOCKOUT, lead detection
- `opendbc_repo/opendbc/car/honda/fingerprints.py` — firmware version fingerprints

### Documentation
- `docs/TUNING_HISTORY.md` — Full lateral tuning history (v1-v7) with telemetry data
- `docs/HONDA_CITY_7G_EPS_RESEARCH.md` — EPS architecture, firmware modding research
- `docs/comma3x-backup/` — Device backup and restore instructions

## Device (comma 3X) Operations

### SSH access
```bash
ssh comma@100.64.168.48  # via Tailscale
```

### Python environment on device
```bash
PYTHONPATH=/data/openpilot /usr/local/venv/bin/python3
```

### Clearing cached params (required after tuning changes)
```python
from openpilot.common.params import Params
p = Params()
p.remove("CarParamsCache")
p.remove("CarParamsPersistent")
```
Then cycle ignition (not device reboot) for re-fingerprinting.

### Preventing auto-updater from reverting changes
```python
from openpilot.common.params import Params
Params().put_bool("DisableUpdates", True)
```

### Device opendbc branch
The device runs `fit-taiwan` + custom commits (not mvl-boston/master). Check with:
```bash
cd /data/openpilot/opendbc_repo && git log --oneline -5
```

## Current Tuning (v7)

| Parameter | Value |
|-----------|-------|
| Controller | PID |
| STEER_MAX | 4096 |
| kpV | [0.15, 0.5] |
| kiV | [0.02, 0.15] |
| kf | 0.00018 |
| LAT_ACCEL_FACTOR | 2.5 |
| FRICTION | 0.15 |
| steerRatio | 17.5 |
| steerActuatorDelay | 0.12 |
| STEER_DELTA_UP/DOWN | 5 |

## Applied Fixes
- **BRAKE_REQUEST for radarless** — Moved from radar-only to common ACC_CONTROL so City 7G receives explicit brake commands (from mvl-boston/radarless-brake-fix)

## Known Limitations
1. EPS hardware torque ceiling at 4096 — only EPS firmware modding can increase
2. 23 km/h low-speed lockout — EPS firmware enforced, not bypassable in software
3. Vision-only lead detection (no radar) — 49-67% dropout rate on curves/intersections
4. ExperimentalMode is ON — uses min(e2e, MPC) for braking (more conservative)
