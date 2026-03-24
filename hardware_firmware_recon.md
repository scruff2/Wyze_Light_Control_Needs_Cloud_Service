# Hardware And Firmware Recon

## Goal

Determine whether the original white Wyze Bulb `WLPA19` can be controlled without Wyze cloud by attacking the bulb hardware / firmware layer directly.

## Why This Branch Matters

The app/API side is no longer the blocker.

What is already proven:

- the stock Wyze app loses control when WAN is blocked
- the app drives the bulb through Wyze cloud property APIs
- a local computer script can reproduce those cloud API calls while Wyze service is available

What remains unsolved:

- controlling the bulb when Wyze cloud or WAN internet is unavailable

That means the next serious path is bulb-level reverse engineering.

The physical path is now constrained:

- physical teardown is not currently an option

So the practical no-cloud branch must prioritize non-destructive discovery first:

- app-side firmware/update path analysis
- live capture of firmware-check requests from the patched Android app
- identification of any downloadable firmware metadata, images, or downgrade packages
- only then reconsider hardware access if the software path dead-ends

## Non-Destructive Firmware Recon Status

Static APK analysis now shows two distinct Wyze firmware stacks relevant to `WLPA19`:

1. Legacy light/commonlight update stack
   - base host:
     - `https://upgrade-api.wyzecam.com:8605/`
   - asset endpoints:
     - `get_upgrade_version_list.ashx`
     - `get_downgrade_version_list.ashx`
     - `getnewst.ashx`
   - asset keys recovered from:
     - `android_apk_decoded\assets\HL_API_ADDR`
     - `android_apk_decoded\assets\HL_API_URL`
     - `android_apk_decoded\assets\HL_API_SV`

2. Newer Wyze platform firmware stack
   - base path in app code:
     - `ServiceConfig.BASE_UPDATE_URL + /app/v2/upgrade/...`
   - observed endpoints in `WpkUpdatePlatform`:
     - `/app/v2/upgrade/firmware_version`
     - `/app/v2/upgrade/get_firmware_by_version`
     - `/app/v2/upgrade/get_firmware_detail`
     - `/app/v2/upgrade/get_revert_firmware`
     - `/app/v2/upgrade/get_upgrade_status`
     - `/app/v2/upgrade/get_upgrade_firmware_ex`

The newer stack is important because it suggests Wyze now exposes firmware metadata through normal app API infrastructure, not only the older `upgrade-api` `.ashx` endpoints.

## Live Cloud Device Metadata Already Confirmed

Using the same authenticated session already proven for cloud light control, `v2/device/get_device_Info` returned the bulb's current cloud metadata:

- `product_model`: `WLPA19`
- `product_type`: `Light`
- `hardware_ver`: `0.0.0.0`
- `firmware_ver`: `1.2.0.382`
- `ip`: present in the live response but redacted from tracked docs

This matters because these are exactly the fields fed into the legacy update query builder.

## What Static Analysis Now Proves

For the legacy light update path, `ti.plutodo.plutosuper(DeviceInfo)` builds:

- `sc`
- `sv`
- `hardwareversion`
- `productmodel`
- `productnum`
- `testcode`
- `version`

Known values for the bulb under test are now:

- `sc = a626948714654991afd3c0dbd7cdb901`
- `sv = 30c6cfdefea54b1cba5b85123ba412cb`
- `hardwareversion = 0.0.0.0`
- `productmodel = WLPA19`
- `productnum = Light`
- `version = 1.2.0.382`
- `testcode = Official Version` under normal production config

Probing the legacy endpoint with those values reached the live Wyze update host but returned HTTP `500`, which means:

- the endpoint is alive
- at least one field or request assumption is still incomplete
- a live app-side capture of the firmware check is more reliable than further guessing

## Best Next Step

The next useful move is not more LAN probing and not more speculation about old `.ashx` parameters.

It is:

1. use the patched Android app
2. navigate to the bulb firmware/update screen
3. capture the exact outgoing update-check request and response
4. determine which of these the app actually uses for `WLPA19` today:
   - the legacy `upgrade-api.wyzecam.com:8605/*.ashx` path
   - the newer `/app/v2/upgrade/...` path
5. if firmware metadata or a binary URL appears, archive it locally for offline analysis

## Current Best Hardware Lead

Two Wyze forum teardown references point to the original white bulb using:

- `ESP-WROOM-02`

Source trail:

- Wyze forum teardown thread says:
  - "It’s using a ESP-WROOM-02 controller from Espressif and 24 LEDs with common anode power."
- Wyze forum follow-up thread repeats:
  - the bulb uses an `Espressif ESP-WROOM-02 controller`

Implication from Espressif documentation:

- `ESP-WROOM-02` is an `ESP8266EX`-based Wi-Fi module
- it includes onboard SPI flash

This is the first strong evidence that the original bulb may be physically approachable with normal ESP8266 tooling rather than requiring a completely unknown radio/SoC path.

## What This Does And Does Not Mean

What it suggests:

- there may be UART flashing or flash dumping paths
- the firmware is likely stored in accessible SPI flash associated with the module
- alternate firmware or direct firmware analysis may be feasible

What it does not prove:

- that the Wyze bulb is pin-compatible with an easy in-circuit programmer setup
- that flash is unlocked or easy to dump without desoldering
- that Tasmota or ESPHome can be dropped in without first understanding the LED driver and power hardware

## Most Likely Technical Paths

### Path A: Non-destructive serial access

Open the bulb and locate:

- module pads
- UART TX/RX
- `GPIO0`
- `EN`
- `3V3`
- `GND`

Best case:

- boot log is readable over UART
- module can be forced into ROM bootloader mode
- flash can be read with `esptool.py`

### Path B: External SPI flash read

If the module or flash pads are not easy to use in-circuit:

- identify the flash package
- clip or desolder as needed
- dump firmware externally

### Path C: Alternate firmware feasibility

If the module really is ESP8266-class and flash access is obtained:

- map the GPIOs used for warm/cool LED channels and any power / current control hardware
- determine whether Tasmota, ESPHome, or a minimal custom firmware is realistic

## Practical Next Hands-On Tasks

1. Sacrifice or open one bulb.
2. Photograph:
   - main PCB top
   - main PCB bottom
   - module markings
   - any test pads near the module
   - LED board and connectors
3. Confirm whether the radio module marking actually reads `ESP-WROOM-02`.
4. Identify:
   - UART candidate pads
   - flash package marking
   - LED driver IC marking
5. Decide whether first extraction should be:
   - UART / ROM bootloader
   - direct SPI flash read

## Working Hypothesis

The original white Wyze bulb is probably much closer to an ESP8266-based IoT light than to a fully opaque custom platform.

If that holds under physical inspection, the most promising medium-term objective is:

- dump stock firmware
- identify GPIO / LED driver mapping
- evaluate replacement firmware or a stripped local-only firmware

## Evidence Links

- Wyze forum teardown thread:
  - https://forums.wyze.com/t/wyze-bulb-teardown/45384
- Wyze forum follow-up thread:
  - https://forums.wyze.com/t/wyze-bulb-additional-specs/50038
- Espressif `ESP-WROOM-02` module page / datasheet:
  - https://www.espressif.com/en/producttype/esp-wroom-02
  - https://www.espressif.com/sites/default/files/documentation/0c-esp-wroom-02_datasheet_en.pdf
