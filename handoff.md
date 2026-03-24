# Wyze Bulb Local Control Handoff

## Goal

Determine whether the existing Wyze Wi-Fi bulb(s) can be controlled over the local network without depending on Wyze cloud infrastructure, and if not, shift to reverse engineering the Android app / cloud control path enough to reproduce or redirect control locally.

## Current Status

- computer control is solved through reproduced Wyze cloud API calls
- a local REST API wrapper is also solved in the standalone project
- stock-app no-cloud control is not solved
- true no-cloud work is now focused on non-destructive firmware/update-path capture from the patched Android app

Current best next action when resuming:

1. reconnect the Android phone
2. open the patched Wyze app
3. navigate to the bulb firmware/update screen
4. capture the outgoing request and response
5. determine whether `WLPA19` currently uses the legacy `upgrade-api` path or the newer `/app/v2/upgrade/...` path

## Confirmed Device Data

- Model: `Wyze Bulb`
- Example MAC: `A1B2C3D4E5F6`
- Example LAN IP: `10.0.0.50`
- Firmware: `1.2.0.382`
- Local Wi-Fi SSID: redacted in tracked docs
- Activation date: `2020-03-27`
- Plugin version noted by user: `3.10.0.1`

This information came from `Wyze Bulb Info.txt`.

## LAN Discovery Already Done

- Current machine was on the same `/24` LAN as the bulb during testing
- Router was the default gateway for that subnet
- ARP confirmed the bulb at its then-current LAN IP
- Probing common ports on the bulb LAN IP found nothing open on:
  - `80`
  - `443`
  - `554`
  - `6668`
  - `6669`
  - `8883`
  - `1883`
  - `8008`
  - `8009`

## Verification Run On 2026-03-22

- Test host still had Wi-Fi connectivity on the same `/24` LAN
- `Test-NetConnection <bulb-ip>` succeeded
  - Source: same local subnet host
  - Interface: `Wi-Fi`
  - Ping RTT: `8 ms`
- `Get-NetNeighbor` still shows:
  - IP: current bulb LAN address
  - MAC: matched the device under test
  - State: `Reachable`
- Re-checked TCP ports:
  - `80`
  - `443`
  - `554`
  - `6668`
  - `6669`
  - `8883`
  - `1883`
  - `8008`
  - `8009`
- Result: all listed TCP ports still report closed/unreachable

This keeps the prior conclusion intact: the bulb is present on the LAN, but there is still no evidence of an obvious TCP-based local control surface.

## Offline Test Result On 2026-03-22

- User blocked WAN internet access at the router while keeping local Wi-Fi/LAN up.
- Result: the Wyze app lost control of the bulb.
- Interpretation: for this bulb and current app flow, there is no observed usable local-only control path when Wyze cloud access is unavailable.

This does **not** prove the bulb has no undocumented local protocol at all, but it does prove the normal Wyze Android app control path depends on internet access in the tested setup.

## PC-Side Capture Result On 2026-03-22

- `probe_bulb.ps1` successfully produced:
  - `captures\wyze-bulb-20260322-221900.etl`
  - `captures\wyze-bulb-20260322-221900.pcapng`
- The `.pcapng` is effectively empty (`184` bytes).
- Exported `pktmon` counters for the bulb IP filter show `0` packets / `0` bytes.
- Interpretation: the laptop capture point does not see the Android phone's control traffic path to the bulb and/or Wyze cloud.

Conclusion: repeating the same Windows-side `pktmon` capture is low value unless the topology changes.

## Current Assessment

Public breadcrumbs suggest the known unofficial local API work applies to `Wyze Bulb Color` and `BR30`, not necessarily the original white `Wyze Bulb`.

Because this device identifies as plain `Wyze Bulb`, the project is now split into two stages:

1. Determine whether this bulb supports any local-only control path at all.
2. If the stock app does not work offline, move to app/cloud reverse engineering rather than assuming a LAN API exists.

Stage 1 has produced a negative result for stock-app offline control.

## Important Constraint

Do not assume there is a usable local API for this bulb model.

The next phase should be evidence-driven:
- offline behavior test first
- direct Windows-side packet capture is not sufficient for Android app traffic in this setup
- Android app analysis and Android-side traffic capture are now the highest-value next steps

## Next Actions

1. Acquire the Wyze Android APK that matches the installed app version if possible.
   - Preserve the APK and note the app version used during testing.
   - Decompile with `jadx` or `apktool`.

2. Search the Android app for bulb control surfaces.
   - Look for model names such as `Wyze Bulb`, `Bulb`, and any product identifiers.
   - Look for Wyze API hosts, websocket code, MQTT usage, protobuf schemas, and TLS pinning logic.
   - Determine whether bulb commands are assembled locally in app code or delegated to a generic cloud API client.

3. Capture traffic from the Android side while internet is enabled.
   - Prefer Android-side capture or a router/AP capture point.
   - Correlate app actions:
     - off
     - on
     - brightness low
     - brightness high
   - Record destination hosts, protocols, and whether any traffic targets the bulb LAN IP directly.

4. Decide the attack surface based on evidence.
   - If the phone talks only to Wyze cloud: reverse engineer the cloud API/auth flow.
   - If the phone talks to the bulb locally while internet is also present: reverse engineer that LAN protocol.
   - If certificate pinning blocks MITM: patch or instrument the Android app.

## Useful Starting Hypotheses

- This bulb may expose no local control service at all.
- If local control exists, it may use:
  - direct unicast to the bulb
  - local discovery via broadcast or multicast
  - an undocumented encrypted payload

## Android Context

- User control device: `Android`
- Android device used for extraction: `Pixel 9a`
- Wyze Android package: `com.hualai`
- Installed app version confirmed from device: `3.10.6.753`
- APK set extracted locally to `android_apk\`
- This matters because Android provides more realistic options for:
  - APK extraction / decompilation
  - device-side network capture
  - runtime instrumentation if needed

## Initial Android APK Findings

- Cloud API base assets in the APK point to:
  - `https://app.wyzecam.com/app/`
  - `https://oauth.wyzecam.com/oauth/token`
  - `https://statistics-api.wyzecam.com:8615/app/`
- Light/property API assets and dex strings reference:
  - `v2/device/get_property_list`
  - `v2/device/set_property`
  - `v2/device/set_property_list`
  - `v2/device_list/get_property_list`
  - `v2/device_list/set_property_list`
  - `v2/instance_scene/get_list`
  - `v2/instance_scene/add`
  - `v2/instance_scene/set`
  - `v2/instance_scene/delete`
- Product routing strings include multiple light-related paths such as:
  - `/hlsetup/colorlight/adddevice`
  - `/hlsetup/lightstrip/adddevice`
  - `/hlbr30c/opendevice`
  - `/hllsl/opendevice`
  - `/hllslp/opendevice`
- ARouter decompilation shows the original white bulb route is:
  - `WLPA19 -> com.wyze.commonlight.lightv1.DeviceTransferPage`
- That transfer page immediately redirects the original bulb into the newer controller path:
  - `/HLHWB2/opendevice`
  - `com.wyze.commonlight.lightv2.mvp.view.BulbV2Activity`
- Security/networking components present in the APK include:
  - `OkHttp`
  - `Ktor`
  - `org.eclipse.paho.mqttv5`
  - `CertificatePinner`
  - `network_security_config`

## Android Network Security Findings

- Manifest confirms:
  - `android:usesCleartextTraffic=false`
  - a custom `networkSecurityConfig`
- `res/xml/network_security_config.xml` shows:
  - base trust anchors from system CAs
  - `debug-overrides` trusting user CAs
  - explicit certificate pinning for relevant Wyze domains
- Pinned domains include:
  - `app.wyzecam.com`
  - `beta-app.wyzecam.com`
  - `services.wyze.com`
  - `wyze-general-api.wyzecam.com`
  - `wyze-platform-service.wyzecam.com`
  - `hms.api.wyze.com`
  - `auth-prod.api.wyze.com`
  - `amazonaws.com`
- `adb shell run-as com.hualai ls` fails because the app is not debuggable.

Practical implication:

- ordinary HTTPS proxy MITM with a user-installed CA is unlikely to expose the light-control payloads for the stock release app
- the next realistic paths are:
  - patch / repackage the APK
  - runtime instrumentation
  - alternate non-payload capture that still reveals useful endpoint behavior

Current interpretation:

- The stock Android app clearly knows about cloud property-setting endpoints for lighting products.
- No first-pass evidence yet shows that the tested original `Wyze Bulb` uses a stock local-only command path in the app.
- The next meaningful evidence will come from APK patching / instrumentation or deeper class decompilation rather than more Windows LAN probing.

## Non-Invasive Android Capture Path On 2026-03-23

The user chose to avoid uninstalling or replacing the stock Wyze app.

That rules out the fastest patch-and-repackage path for now because:

- `com.hualai` is installed as a release-signed app
- a debug-signed patched APK cannot be installed over the stock package
- replacing it would require uninstalling the live app first

The current least-invasive capture approach is:

- keep the stock Wyze app installed
- use a separate Android capture app to observe Wyze network destinations and timing
- only move to APK replacement if non-invasive capture proves insufficient

Chosen helper tool:

- `PCAPdroid`
- package: `com.emanuelef.remote_capture`
- version installed: `1.9.1`
- APK saved locally at:
  - `tools\pcapdroid\PCAPdroid_v1.9.1.apk`

Android package details:

- launcher activity:
  - `com.emanuelef.remote_capture/.activities.MainActivity`

Immediate next step:

1. Start a PCAPdroid capture on the phone.
2. Limit the session to Wyze app activity if practical.
3. Toggle only:
   - off
   - on
   - brightness low
   - brightness high
4. Export the capture from the phone and inspect:
   - Wyze hostnames
   - destination IPs
   - HTTP/HTTPS metadata that survives without MITM
   - any direct traffic to the bulb LAN IP

This path is lower risk than uninstalling the Wyze app and may still give enough evidence to identify the live cloud endpoints and request cadence used for `P3` and `P1501`.

## Android PCAPdroid Capture Result On 2026-03-23

Non-invasive phone-side capture was completed with:

## Instrumented Android Capture Result On 2026-03-23

The Wyze Android app was patched to log the final request URL and JSON body immediately before network dispatch. The stock release install was replaced with a debug-signed split-package rebuild so the live request wrapper could be captured without TLS MITM.

Raw capture saved at:

- `captures\android\logcat\wyze_hook_20260323-192300.txt`

Confirmed control endpoint used for the tested original bulb:

- `https://app.wyzecam.com/app/v2/device_list/set_property_list`

Confirmed wrapper fields included on live requests:

- `access_token`
- `app_name`
- `app_ver`
- `app_version`
- `phone_id`
- `phone_system_type`
- `sc`
- `sv`
- `ts`

Confirmed device target in live requests:

- `device_mac`: `A1B2C3D4E5F6`
- `device_model`: `WLPA19`

Confirmed live property payloads:

- Power on:
  - `{"device_list":[{"device_mac":"A1B2C3D4E5F6","device_model":"WLPA19","property_list":[{"pid":"P3","pvalue":"1"}]}]}`
- Power off:
  - `{"device_list":[{"device_mac":"A1B2C3D4E5F6","device_model":"WLPA19","property_list":[{"pid":"P3","pvalue":"0"}]}]}`
- Brightness low:
  - `{"device_list":[{"device_mac":"A1B2C3D4E5F6","device_model":"WLPA19","property_list":[{"pid":"P3","pvalue":"1"},{"pid":"P1501","pvalue":"2"}]}]}`
- Brightness high:
  - `{"device_list":[{"device_mac":"A1B2C3D4E5F6","device_model":"WLPA19","property_list":[{"pid":"P3","pvalue":"1"},{"pid":"P1501","pvalue":"92"}]}]}`

Important interpretation:

- The stock control path for this bulb is a Wyze cloud API call, not a direct LAN command from the app to the bulb.
- Basic control only needs a small property payload once valid session fields are present.
- A local replacement will need to reproduce this authenticated command path or replace the bulb/app firmware path entirely.

Practical next step:

1. Build a small local client that can send the same request shape when given valid Wyze session credentials.
2. Then decide whether to:
   - refresh Wyze auth normally and proxy commands through a local service, or
   - pursue deeper firmware work to bypass Wyze cloud entirely.

## Minimal Control Client Added On 2026-03-23

Local helper script:

- `wyze_light_control.py`

Purpose:

- reproduce the captured Wyze cloud light-control call for the tested bulb
- default to using the saved instrumented hook log to recover:
  - `access_token`
  - `phone_id`

Supported commands:

- `on`
- `off`
- `brightness <1-100>`

Examples:

- Dry-run:
  - `python .\wyze_light_control.py on --dry-run`
  - `python .\wyze_light_control.py brightness 25 --dry-run`
- Live request:
  - `python .\wyze_light_control.py on`
  - `python .\wyze_light_control.py off`
  - `python .\wyze_light_control.py brightness 40`

Important constraint:

- this script reproduces the Wyze cloud API call shape
- it does not make the bulb independent of Wyze service availability
- when the captured `access_token` expires, either:
  - capture a fresh hook log from the patched app, or
  - pass a fresh `--access-token` and `--phone-id`

## Live Client Validation On 2026-03-23

The local helper script was exercised successfully against the live Wyze session.

Commands tested:

- `python .\wyze_light_control.py on`
- `python .\wyze_light_control.py off`
- `python .\wyze_light_control.py brightness 40`

Result for all three:

- HTTP status: `200`
- Wyze response `msg`: `SUCCESS`
- target device in result: the expected device under test

Meaning:

- the reverse-engineered request shape is correct
- local automation from this machine now works while Wyze cloud service is reachable
- this validates the API/client side of the project

Remaining gap for the original outage-resilience goal:

- this still fails if Wyze cloud or WAN access is unavailable
- cloud-independent control will require a different layer of attack:
  - firmware/device protocol reverse engineering
  - hardware access such as UART/JTAG/flash extraction
  - or replacing the bulb firmware entirely if feasible

## Local REST API Added On 2026-03-23

New helper:

- `wyze_light_api.py`

Purpose:

- expose a stable local HTTP interface for computer-side automation
- keep the existing Wyze cloud-backed control logic behind a small localhost API

Default bind:

- `127.0.0.1:8787`

Endpoints:

- `GET /status`
- `POST /on`
- `POST /off`
- `POST /brightness`

Example brightness request body:

```json
{
  "brightness": 40
}
```

Verified:

- `/status` responded correctly during local smoke test

Important limitation:

- this is a local automation surface, not a no-cloud breakthrough
- it improves usability and integration now while preserving the longer-term no-cloud branch

## Hardware Recon Pivot On 2026-03-23

The next branch is now hardware / firmware recon rather than more app API work.

Best current lead:

- multiple Wyze forum posts about the original white bulb teardown report an `ESP-WROOM-02` module inside the bulb

Why this matters:

- `ESP-WROOM-02` is an Espressif `ESP8266EX`-based Wi-Fi module with onboard SPI flash
- that makes the bulb materially more approachable than a fully unknown radio platform
- it raises the odds that UART boot logs, `esptool` flash dumping, or alternate firmware work may be realistic

Current working hypothesis:

- if the teardown claim is accurate for this bulb revision, the most promising no-cloud path is:
  - physically open a bulb
  - verify the module marking
  - identify UART / boot / flash pads
  - dump stock firmware
  - map GPIO and LED-driver behavior

Dedicated next-phase notes:

- `hardware_firmware_recon.md`

- source app: stock Wyze Android app `com.hualai`
- helper app: `PCAPdroid 1.9.1`
- pulled capture:
  - `captures\android\PCAPdroid_23_Mar_18_51_31.pcap`

User actions during the short trace:

- bulb off
- bulb on
- brightness low
- brightness high

Observed result:

- no packets to or from the bulb LAN IP
- no occurrence of the bulb LAN IP in the capture payloads
- Wyze-related DNS and TLS handshakes were observed instead

Observed Wyze service names in the capture:

- `app.wyzecam.com`
- `wyze-platform-service.wyzecam.com`
- `wyze-re-rule-svc.wyzecam.com`
- `wyze-membership-service-v2.wyzecam.com`
- `wyze-membership-service.wyzecam.com`
- `hms.api.wyze.com`
- `wyze-upgrade-service.wyzecam.com`
- `wyze.dataplane.rudderstack.com`

Interpretation:

- during this real light-control session, the stock Android app talked to Wyze cloud services over TLS
- this capture produced no evidence of direct LAN control traffic to the bulb
- the reverse-engineering target is therefore the app/cloud control path, not a visible phone-to-bulb LAN protocol

Practical consequence:

- a second capture from the same stock-app / non-invasive setup is unlikely to reveal a hidden local protocol
- the next higher-value step is to instrument the live Android app enough to identify which cloud request carries `P3` and `P1501`

## Runtime Attach Attempt On 2026-03-23

A non-invasive live-debug attempt was made against the stock app while keeping the installed package intact.

Observed runtime state:

- package: `com.hualai`
- live PID during attach attempt: `31944`
- `adb forward tcp:8700 jdwp:31944` succeeded
- direct JDWP attach from `jdb` failed with:
  - `handshake failed - connection prematurally closed`

Interpretation:

- the process can be reached through `adb`
- the Android VM is not exposing a usable Java debug session for this release build
- this blocks the simple in-memory read of `com.wyze.platformkit.Center.access_token`

What is still confirmed from static analysis:

- light control calls are built through `ti.plutodo`
- single-property request:
  - `URL_SET_PROPERTY`
  - params: `device_mac`, `device_model`, `pid`, `pvalue`
- bulk-property request:
  - `URL_DEVICE_LIST_SET_PROPERTY_LIST`
  - param: `device_list`
- `WpkHLService` automatically injects:
  - `sc`
  - `sv`
  - `phone_system_type`
  - `phone_id`
  - `app_ver`
  - `access_token`
  - `app_name`
  - `app_version`
  - `ts`

Current blocker:

- the remaining missing value for direct request reproduction is live authenticated session state, especially `access_token`

## Concrete Light-Control Findings

Decompilation now ties the tested original `WLPA19` bulb into the same `HLHWB2` light controller used by `BulbV2Activity` and `FragmentLightV2`.

Confirmed light property IDs used by that controller:

- Power on/off: `P3`
  - app sends `"0"` for off
  - app sends `"1"` for on
- Brightness: `P1501`
  - app sends decimal strings such as `"1"` through `"100"`
- White temperature: `P1502`
- Color value: `P1507`
- Light control mode/state: `P1508`

This mapping comes from:

- `ei.plutocase`
  - property ID constants
- `FragmentLightV2`
  - brightness callback uses `P1501`
  - power toggle uses `P3`
- `oi.plutodo`
  - bulk property JSON assembly

## Concrete Payload Shape

Single-property control ultimately uses the Wyze cloud `v2/device/set_property` path already identified earlier.

Bulk control uses a JSON structure of the form:

```json
[
  {
    "device_mac": "MAC",
    "device_model": "MODEL",
    "property_list": [
      { "pid": "P3", "pvalue": "1" },
      { "pid": "P1501", "pvalue": "50" }
    ]
  }
]
```

Important behavior seen in the app code:

- if `P3 = "0"` is present, the bulk builder short-circuits and sends only the off command
- the app resolves `device_model` from current home device data before submitting the request

This is now enough evidence to stop guessing about bulb power and brightness identifiers.

## Resume Point

Resume from Android-side reverse engineering, not from more Windows-only LAN probing.

Immediate next step:

1. extract live Wyze auth context from the Android app or patch the app to log the outgoing request headers/body
2. confirm the exact `device_model` string submitted for the device under test
3. build a minimal standalone client that reproduces:
   - power off via `P3 = "0"`
   - power on via `P3 = "1"`
   - brightness via `P1501 = "<percent>"`

## Local Tooling Added

- `probe_bulb.ps1`
  - Repeatable local verification of ping, ARP/neighbor state, and the known TCP port list
  - Optional `pktmon` capture setup for the bulb IP
- `pull_wyze_apk.ps1`
  - Pulls the installed Wyze APK set from the connected Android device
- `decompile_wyze_apk.ps1`
  - Uses local `apktool` to decode `android_apk\base.apk` into `android_apk_decoded\`
- `rebuild_sign_wyze_apk.ps1`
  - Rebuilds a decoded APK with `apktool`
  - aligns with Android `zipalign`
  - signs with the local Android debug keystore using `apksigner`

## Local Android Patch Toolchain Status

- Java toolchain available:
  - `java`
  - `javac`
  - `keytool`
- Android SDK tools available locally:
  - `adb`
  - `zipalign`
  - `apksigner`
- Official `apktool` downloaded locally:
  - `tools\apktool_3.0.1.jar`
- Verified on `2026-03-23`:
  - `decompile_wyze_apk.ps1` successfully decoded `android_apk\base.apk` into `android_apk_decoded\`

Current blocker is not the local build chain.
Current blocker is runtime access to a connected Android device and then choosing between:

- logcat-only observation if sufficient
- APK patching to inject request logging
- runtime instrumentation

## No-Cloud Recon Update: Firmware Path

Physical teardown is not currently available, so the no-cloud branch has shifted to non-destructive firmware/update-channel recon.

### What Is Now Confirmed

Static APK analysis shows two firmware/update stacks relevant to the original `WLPA19` bulb.

Legacy light/commonlight stack:

- base host:
  - `https://upgrade-api.wyzecam.com:8605/`
- endpoints from decoded assets:
  - `get_upgrade_version_list.ashx`
  - `get_downgrade_version_list.ashx`
  - `getnewst.ashx`
- recovered from:
  - `android_apk_decoded\assets\HL_API_ADDR`
  - `android_apk_decoded\assets\HL_API_URL`
  - `android_apk_decoded\assets\HL_API_SV`

Newer Wyze platform stack:

- base path:
  - `ServiceConfig.BASE_UPDATE_URL + /app/v2/upgrade/...`
- endpoints observed in `WpkUpdatePlatform`:
  - `/app/v2/upgrade/firmware_version`
  - `/app/v2/upgrade/get_firmware_by_version`
  - `/app/v2/upgrade/get_firmware_detail`
  - `/app/v2/upgrade/get_revert_firmware`
  - `/app/v2/upgrade/get_upgrade_status`
  - `/app/v2/upgrade/get_upgrade_firmware_ex`

### Live Cloud Metadata Recovered For The Bulb

Using the already captured Wyze session, `POST /app/v2/device/get_device_Info` returned:

- `product_model = WLPA19`
- `product_type = Light`
- `hardware_ver = 0.0.0.0`
- `firmware_ver = 1.2.0.382`
- `ip = <current bulb LAN IP>`

### Legacy OTA Request Shape Now Known

`ti.plutodo.plutosuper(DeviceInfo)` builds:

- `sc`
- `sv`
- `hardwareversion`
- `productmodel`
- `productnum`
- `testcode`
- `version`

Known values for the bulb under test:

- `sc = a626948714654991afd3c0dbd7cdb901`
- `sv = 30c6cfdefea54b1cba5b85123ba412cb`
- `hardwareversion = 0.0.0.0`
- `productmodel = WLPA19`
- `productnum = Light`
- `version = 1.2.0.382`
- `testcode = Official Version`

### Probe Result

Replaying the legacy request against:

- `https://upgrade-api.wyzecam.com:8605/get_upgrade_version_list.ashx`

reached the live server but returned:

- HTTP `500`

Meaning:

- the host and path are valid
- the request is still missing at least one detail or uses a path the modern app no longer prefers for `WLPA19`
- the next reliable step is to capture the firmware-update screen request from the patched Android app instead of guessing fields

### Current Best Next Step

1. reconnect the Android phone
2. open the patched Wyze app
3. navigate to the bulb firmware/update screen
4. capture hook/log output for the update check
5. determine whether the live app uses:
   - the legacy `upgrade-api` `.ashx` path
   - the newer signed `/app/v2/upgrade/...` path
6. if firmware metadata or a download URL appears:
   - save it locally
   - inspect whether it is an ESP-style image or other directly usable artifact

### Example Commands

```powershell
.\probe_bulb.ps1
.\probe_bulb.ps1 -StartCapture
.\probe_bulb.ps1 -StopCapture
.\probe_bulb.ps1 -StartCapture -CaptureDir .\captures
```

### `pktmon` Capture Notes

When capture is started, the script:

- removes old `pktmon` filters
- adds an IP filter for the bulb LAN IP
- starts packet capture to an `.etl` file

When capture is stopped, the script:

- stops `pktmon`
- converts the `.etl` file to `.pcapng`

Use the generated `.pcapng` for analysis in Wireshark if offline control succeeds.
