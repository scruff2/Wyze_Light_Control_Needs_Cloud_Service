# Reproduction Guide

This guide is for reproducing the working script-based control path that was validated for the original Wyze Bulb.

## Goal

Control the bulb from a computer script without using the Wyze mobile app UI.

This guide does not provide true offline control. It reproduces Wyze's cloud-backed control call.

## Environment Used

- Windows host
- Python `3.14.2`
- Android phone with USB debugging
- Wyze app `3.10.6.753`
- Original white Wyze Bulb `WLPA19`

## Phase 1: Establish The Constraint

Before doing any app reverse engineering, confirm whether the stock app works without internet.

Observed result in this project:

- when WAN internet was blocked at the router, the Wyze app lost bulb control

Meaning:

- the normal control path is not a usable local-only app-to-bulb flow

## Phase 2: Identify The Android Control Path

### What was captured

- the Wyze Android APK set was extracted from the phone
- the app was decompiled
- the final request dispatch path was instrumented

### Key findings

- cloud base:
  - `https://app.wyzecam.com/app/`
- live control endpoint:
  - `https://app.wyzecam.com/app/v2/device_list/set_property_list`
- device:
  - `device_mac = A1B2C3D4E5F6`
  - `device_model = WLPA19`
- property IDs:
  - `P3` = power
  - `P1501` = brightness

### Verified payload shapes

Power on:

```json
{
  "device_list": [
    {
      "device_mac": "A1B2C3D4E5F6",
      "device_model": "WLPA19",
      "property_list": [
        { "pid": "P3", "pvalue": "1" }
      ]
    }
  ]
}
```

Power off:

```json
{
  "device_list": [
    {
      "device_mac": "A1B2C3D4E5F6",
      "device_model": "WLPA19",
      "property_list": [
        { "pid": "P3", "pvalue": "0" }
      ]
    }
  ]
}
```

Brightness:

```json
{
  "device_list": [
    {
      "device_mac": "A1B2C3D4E5F6",
      "device_model": "WLPA19",
      "property_list": [
        { "pid": "P3", "pvalue": "1" },
        { "pid": "P1501", "pvalue": "40" }
      ]
    }
  ]
}
```

Important detail:

- brightness writes were observed as combined `P3=1` and `P1501=<level>` payloads

## Phase 3: Use The Local Client

The repository includes [wyze_light_control.py](../wyze_light_control.py).

### Create a local config file

Copy the example and fill in your own values:

```powershell
Copy-Item .\local_config.example.json .\local_config.json
```

The script now expects sensitive values to come from untracked local state rather than committed source defaults.

Preferred fields to store in `local_config.json`:

- `device_mac`
- `access_token`
- `phone_id`

### Preview the request

```powershell
python .\wyze_light_control.py on --dry-run
python .\wyze_light_control.py brightness 25 --dry-run
```

### Send live commands

```powershell
python .\wyze_light_control.py on
python .\wyze_light_control.py off
python .\wyze_light_control.py brightness 40
```

### How the script gets session values

Resolution order is:

1. CLI arguments
2. environment variables
3. `local_config.json`
4. captured hook log, for `access_token` and `phone_id` only

Supported environment variables include:

- `WYZE_DEVICE_MAC`
- `WYZE_DEVICE_MODEL`
- `WYZE_ACCESS_TOKEN`
- `WYZE_PHONE_ID`
- `WYZE_APP_NAME`
- `WYZE_APP_VERSION`
- `WYZE_PHONE_SYSTEM_TYPE`
- `WYZE_SC`
- `WYZE_SV`

Fallback hook log path:

- `captures/android/logcat/wyze_hook_20260323-192300.txt`

CLI example:

```powershell
python .\wyze_light_control.py on --device-mac "A1B2C3D4E5F6" --access-token "<token>" --phone-id "<phone-id>"
```

Environment variable example:

```powershell
$env:WYZE_DEVICE_MAC="A1B2C3D4E5F6"
$env:WYZE_ACCESS_TOKEN="<token>"
$env:WYZE_PHONE_ID="<phone-id>"
python .\wyze_light_control.py on
```

## Phase 4: Validate Against The Bulb

This sequence was validated during the investigation:

```powershell
python .\wyze_light_control.py on
python .\wyze_light_control.py brightness 15
python .\wyze_light_control.py brightness 90
python .\wyze_light_control.py off
```

Observed result:

- the bulb responded correctly
- Wyze returned `HTTP 200`
- API response message was `SUCCESS`

Readers must substitute their own `device_mac`, session token, and `phone_id`.

## What This Solves

- controlling the bulb from your own script
- avoiding the Wyze mobile app UI for normal operation
- documenting the exact request shape for automation

## What This Does Not Solve

- no-cloud operation during WAN outages
- direct LAN control to the bulb
- firmware-level ownership of the device

## Recommended Next Step

If your goal is still outage-proof control, stop spending time on the mobile app API. The next phase should be:

1. teardown the bulb
2. identify the SoC / radio module
3. inspect flash / UART options
4. determine whether alternate firmware or a direct device protocol is feasible
