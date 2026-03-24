# Wyze Light Control Needs Cloud Service

This project documents a practical reverse-engineering path for controlling an original Wyze Bulb from a computer script instead of the Wyze mobile app.

Current status:

- confirmed: the bulb can be controlled from a local script running on a computer
- confirmed: the stock Wyze app uses Wyze cloud APIs for this bulb
- confirmed: the stock app loses control when WAN internet is blocked
- not solved here: true cloud-independent control during an internet outage

This repository is therefore about two separate outcomes:

1. reproducing Wyze's cloud control call from your own script
2. preserving evidence and notes for the deeper no-cloud reverse-engineering phase

## Tested Device

- Product: original white `Wyze Bulb`
- Model: `WLPA19`
- Firmware: `1.2.0.382`
- Example bulb MAC: `A1B2C3D4E5F6`
- Android app package: `com.hualai`
- Android app version: `3.10.6.753`

## What Was Proven

The validated script path is:

- `POST https://app.wyzecam.com/app/v2/device_list/set_property_list`

Observed property IDs:

- power: `P3`
- brightness: `P1501`

Observed payload patterns:

- on: `P3=1`
- off: `P3=0`
- brightness: `P3=1` and `P1501=<1-100>`

The local helper script [wyze_light_control.py](wyze_light_control.py) was validated live for:

- `on`
- `off`
- `brightness 40`

Each returned `HTTP 200` and `SUCCESS`.

Replace the example MAC and any saved session values with your own before attempting control.

## Important Limitation

This is not yet an outage-proof solution.

The current script reproduces Wyze's cloud API call. It still depends on:

- a valid Wyze session token
- Wyze cloud service being reachable
- WAN internet being available

If your goal is true no-cloud control during an internet outage, the next phase is bulb hardware / firmware reverse engineering, not more app API discovery.

## Quick Start

### 1. Use the existing captured session

If you already have a valid instrumented hook log at:

- `captures/android/logcat/wyze_hook_20260323-192300.txt`

you can run:

```powershell
python .\wyze_light_control.py on
python .\wyze_light_control.py off
python .\wyze_light_control.py brightness 40
```

### 2. Preview without sending

```powershell
python .\wyze_light_control.py on --dry-run
python .\wyze_light_control.py brightness 25 --dry-run
```

### 3. Override session values manually

If the saved token expires, pass fresh values directly:

```powershell
python .\wyze_light_control.py on --access-token "<token>" --phone-id "<phone-id>"
```

## Repository Layout

- [wyze_light_control.py](wyze_light_control.py): minimal control client
- [handoff.md](handoff.md): running investigation log
- [android_reverse_engineering_notes.md](android_reverse_engineering_notes.md): Android-specific reverse-engineering notes
- [docs/REPRODUCTION_GUIDE.md](docs/REPRODUCTION_GUIDE.md): cleaned-up reproduction steps for others

## Sensitive Data Warning

Do not publish raw hook logs or live captures containing:

- `access_token`
- `phone_id`
- full request bodies copied from instrumented sessions

The raw log used during this work contains live session data and should be treated as sensitive.

## Next Technical Branch

The app/API side is now established. The remaining unsolved question is:

- how to control `WLPA19` when Wyze cloud and WAN access are unavailable

That likely requires one or more of:

- bulb teardown
- SoC identification
- UART / flash extraction
- firmware analysis
- alternate firmware feasibility assessment
