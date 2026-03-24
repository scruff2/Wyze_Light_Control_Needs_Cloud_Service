# Wyze Android Reverse Engineering Notes

## Purpose

Track the Android-specific work needed now that stock-app offline control has already failed.

## Why Android Is The Right Next Target

- The bulb is reachable on LAN but the Wyze app loses control when WAN is blocked.
- The Windows laptop capture point did not observe any bulb traffic.
- The Android phone is the likely origin of the actionable control traffic.

## Evidence So Far

- Bulb IP: `10.0.0.50`
- Bulb model: `Wyze Bulb`
- Firmware: `1.2.0.382`
- Offline test result: control fails when WAN is blocked
- Windows `pktmon` result: no packets observed for `10.0.0.50` during app actions

## Immediate Android Work Queue

1. Decompile the extracted APK with `jadx` and/or `apktool`.
2. Search for:
   - `wyze`
   - `bulb`
   - `10.0.0.50`
   - product/model identifiers
   - `mqtt`
   - `websocket`
   - `protobuf`
   - `ssl`
   - `certificatePinner`
   - `okhttp`
3. Capture Android-side traffic while toggling the bulb.
4. Compare observed destinations against code findings.

## Extracted App Build

- Device connected with `adb`: `Pixel 9a`
- Package: `com.hualai`
- VersionName: `3.10.6.753`
- VersionCode: `62453`
- FirstInstallTime: `2025-10-15 21:23:47`
- LastUpdateTime: `2026-02-25 01:52:27`

Pulled APK files:

- `android_apk\base.apk`
- `android_apk\split_config.arm64_v8a.apk`
- `android_apk\split_config.en.apk`
- `android_apk\split_config.xxhdpi.apk`
- `android_apk\package_info.txt`

Helper script added:

- `pull_wyze_apk.ps1`

## Initial APK Findings

### Cloud API Assets

The APK contains configuration assets that directly define Wyze cloud API bases and light/property endpoints.

Observed hosts from assets:

- `https://app.wyzecam.com/app/`
- `https://oauth.wyzecam.com/oauth/token`
- `https://statistics-api.wyzecam.com:8615/app/`
- `https://api.wyzecam.com:8615/app/`

Relevant asset files:

- `assets/HL_API_ADDR`
- `assets/HL_API_URL`
- `assets/PLUGIN_URL`
- `assets/PLUGIN_SV`
- `assets/RGB_LIGHT_HL_URL`
- `assets/SETUP_ADDR`
- `assets/SETUP_URL`

### Light / Property Endpoints

The extracted asset configs and dex strings reference these especially relevant endpoints:

- `v2/device/get_property_list`
- `v2/device/set_property`
- `v2/device/set_property_list`
- `v2/device_list/get_property_list`
- `v2/device_list/set_property_list`
- `v2/instance_scene/get_list`
- `v2/instance_scene/add`
- `v2/instance_scene/set`
- `v2/instance_scene/delete`

This is consistent with app-mediated cloud control of device properties rather than a simple direct-LAN command path from the stock app.

### Product / Routing Clues

The app contains many per-product route strings, including light-specific setup and open-device routes such as:

- `/hlsetup/colorlight/adddevice`
- `/hlsetup/lightstrip/adddevice`
- `/hlbr30c/opendevice`
- `/hllsl/opendevice`
- `/hllslp/opendevice`

No direct evidence has been found yet in this first pass that the original tested `Wyze Bulb` uses a stock local-only LAN path.

### Transport / Security Clues

The APK includes:

- `OkHttp`
- `Ktor`
- `org.eclipse.paho.mqttv5`
- `CertificatePinner`
- `network_security_config`

This means MITM or traffic interception may encounter TLS validation / pinning logic and may require runtime patching or instrumentation depending on the exact code path used for light control.

## Network Security Findings

Decoded from `res/xml/network_security_config.xml` and the manifest:

- Manifest sets:
  - `android:usesCleartextTraffic="false"`
  - `android:networkSecurityConfig="@0x7f17000b"`
- The network security config contains:
  - `debug-overrides` trusting `src="user"`
  - base trust anchors from `src="system"`
  - certificate pinning for multiple Wyze domains

Pinned domains include:

- `app.wyzecam.com`
- `beta-app.wyzecam.com`
- `services.wyze.com`
- `beta-services.wyze.com`
- `wyze-general-api.wyzecam.com`
- `wyze-platform-service.wyzecam.com`
- `hms.api.wyze.com`
- `auth-prod.api.wyze.com`
- `amazonaws.com`

Interpretation:

- The installed release app is not debuggable.
- `debug-overrides` do not help for the stock release build.
- Plain HTTPS proxy MITM with a user-installed CA is unlikely to work against pinned Wyze domains used for light/property APIs.

## Device-Side Access Findings

- App PID observed with `adb`: running
- `adb shell run-as com.hualai ls` failed with:
  - `run-as: package not debuggable: com.hualai`

Interpretation:

- We do not currently have app-private file access through `run-as`.
- Non-root analysis will need one of:
  - APK patching / repackaging
  - runtime instrumentation
  - alternative capture that does not depend on breaking TLS payload visibility

## Decision Criteria

- If all control traffic goes to Wyze cloud endpoints:
  - focus on API/auth reverse engineering
- If local traffic to the bulb appears:
  - focus on LAN protocol reverse engineering
- If the app is pinned and MITM fails:
  - move to patching or runtime instrumentation

## Non-Invasive Capture Decision On 2026-03-23

The user chose to avoid uninstalling the stock Wyze app.

Effect on the workflow:

- do not replace `com.hualai` with a debug-signed patched build
- avoid any path that requires uninstalling the release-signed Wyze package
- prefer phone-side capture that leaves the stock app intact

Chosen capture helper:

- `PCAPdroid`
- package: `com.emanuelef.remote_capture`
- version: `1.9.1`
- launcher:
  - `com.emanuelef.remote_capture/.activities.MainActivity`
- local APK copy:
  - `tools\pcapdroid\PCAPdroid_v1.9.1.apk`

Why this is the right next step:

- it does not touch the Wyze install
- it can still reveal destination hosts, timing, connection reuse, and any local-vs-cloud split
- it may produce enough evidence to narrow the live endpoints used for `P3` and `P1501` without defeating TLS immediately

New immediate task sequence:

1. launch PCAPdroid on the phone
2. start a short capture
3. exercise only basic bulb controls:
   - off
   - on
   - brightness down
   - brightness up
4. export the capture
5. inspect whether any direct LAN traffic to `10.0.0.50` exists
6. if the capture is cloud-only and payloads remain opaque:
   - move to stronger instrumentation later
   - keep the stock app untouched unless the user explicitly changes that decision

## PCAPdroid Capture Result On 2026-03-23

Capture file pulled from the phone:

- `captures\android\PCAPdroid_23_Mar_18_51_31.pcap`

Basic result:

- packet count: `713`
- packets to or from bulb IP `10.0.0.50`: `0`
- literal occurrence of `10.0.0.50` in capture payloads: not found

Wyze-related hostnames recovered from DNS and TLS handshake metadata:

- `app.wyzecam.com`
- `wyze-platform-service.wyzecam.com`
- `wyze-re-rule-svc.wyzecam.com`
- `wyze-membership-service-v2.wyzecam.com`
- `wyze-membership-service.wyzecam.com`
- `hms.api.wyze.com`
- `wyze-upgrade-service.wyzecam.com`
- `wyze.dataplane.rudderstack.com`

Interpretation:

- the stock app clearly generated Wyze cloud traffic during the control session
- this trace did not show direct phone-to-bulb traffic on the LAN
- that aligns with the earlier offline WAN-block failure and strengthens the conclusion that the actionable control path is cloud-mediated

Updated decision:

- do not spend more time looking for a visible stock-app LAN protocol from the phone
- move the effort to identifying the exact authenticated cloud request that carries `P3` and `P1501`
- unless the user later allows app replacement, the remaining viable non-root paths are:
  - richer PCAPdroid session correlation
  - Android accessibility/UI-timed capture
  - dynamic instrumentation that leaves the stock app installed

## Live Debug Attach Attempt On 2026-03-23

Goal:

- read `com.wyze.platformkit.Center.access_token` directly from the running stock app without uninstalling it

What was tried:

- `adb shell am set-debug-app -w com.hualai`
- launch stock Wyze app
- identify live PID: `31944`
- forward JDWP:
  - `adb forward tcp:8700 jdwp:31944`
- attach with `jdb` over socket transport

Result:

- socket forward succeeded
- `jdb` attach failed with:
  - `handshake failed - connection prematurally closed`

Interpretation:

- the release app process is not exposing a usable Java debug session for external inspection
- this blocks the low-friction route of reading `Center.access_token` in memory from the stock install

What remains solidly known:

- `WpkHLService.postString(base, endpoint)` injects request metadata automatically:
  - `sc`
  - `sv`
  - `phone_system_type`
  - `phone_id`
  - `app_ver`
  - `access_token`
  - `app_name`
  - `app_version`
  - `ts`
- `ti.plutodo.plutoprivate(...)` builds the single-property light call:
  - `device_mac`
  - `device_model`
  - `pid`
  - `pvalue`
- `ti.plutodo.plutoextends(...)` builds the bulk-property list call:
  - `device_list`

Current blocker:

- the control payload shape is known
- the live authenticated session value is not yet extracted from the stock app

## Current Best Hypothesis For Light Control

For the original tested Wyze bulb, the stock Android app likely drives light state through Wyze cloud property endpoints such as:

- `v2/device/get_property_list`
- `v2/device/set_property`
- `v2/device/set_property_list`

The most likely next breakthrough will come from patching or instrumenting the Android app enough to observe or alter those property calls.

## Decompiled Routing Result

The app does not keep the original white bulb on a separate legacy control stack.

Confirmed route chain:

## Instrumented Request Capture On 2026-03-23

The patched APK successfully logged final outbound request URLs and bodies from the live app session.

Raw log saved at:

- `captures\android\logcat\wyze_hook_20260323-192300.txt`

Confirmed pre-dispatch light control endpoint:

- `https://app.wyzecam.com/app/v2/device_list/set_property_list`

Confirmed request wrapper fields added by `WpkHLService` in the live session:

- `access_token`
- `app_name`
- `app_ver`
- `app_version`
- `phone_id`
- `phone_system_type`
- `sc`
- `sv`
- `ts`

Observed stable values in this session:

- `device_mac`: `A1B2C3D4E5F6`
- `device_model`: `WLPA19`
- `phone_id`: present and required
- `sc`: `a626948714654991afd3c0dbd7cdb901`
- `sv` for `device_list/set_property_list`: `ddb9baef0d7f44379cd6bfaa8698e682`

Observed live command bodies:

- Power on:
  - property list contained `{"pid":"P3","pvalue":"1"}`
- Power off:
  - property list contained `{"pid":"P3","pvalue":"0"}`
- Brightness low:
  - property list contained `{"pid":"P3","pvalue":"1"},{"pid":"P1501","pvalue":"2"}`
- Brightness high:
  - property list contained `{"pid":"P3","pvalue":"1"},{"pid":"P1501","pvalue":"92"}`

Important behavioral detail:

- Brightness writes were sent as a combined property update that explicitly included `P3=1` together with `P1501=<level>`.
- This suggests a standalone brightness write may not be the app's preferred shape; mirroring the combined payload is safer.

Immediate conclusion:

- For this bulb, the stock Android app uses authenticated Wyze cloud property writes for basic light control.
- No direct LAN payload from the app to the bulb was observed, even after instrumenting the final app-layer request.

Most useful next implementation target:

- a minimal client that reproduces `POST /app/v2/device_list/set_property_list` with the captured wrapper shape and fresh session values
- first commands to implement:
  - off: `P3=0`
  - on: `P3=1`
  - brightness: `P3=1`, `P1501=<1-100>`

## Minimal Client Added On 2026-03-23

New local helper:

- `wyze_light_control.py`

Behavior:

- uses the captured endpoint:
  - `https://app.wyzecam.com/app/v2/device_list/set_property_list`
- builds the same wrapper fields observed from the patched Android app
- by default reads `access_token` and `phone_id` from:
  - `captures\android\logcat\wyze_hook_20260323-192300.txt`

Implemented commands:

- `on`
- `off`
- `brightness <1-100>`

Verified locally in dry-run mode:

- `python .\wyze_light_control.py on --dry-run`
- `python .\wyze_light_control.py brightness 25 --dry-run`

Current limitation:

- it still depends on valid Wyze cloud session state
- it is a protocol reproduction tool, not a cloud-independence solution

## Live Client Validation On 2026-03-23

The reproduced client call was tested successfully against Wyze cloud:

- `python .\wyze_light_control.py on`
- `python .\wyze_light_control.py off`
- `python .\wyze_light_control.py brightness 40`

Observed result for each:

- `HTTP 200`
- response message: `SUCCESS`
- returned device: the expected device under test

This establishes:

- the cloud control endpoint and wrapper fields are correct
- `P3` and `P1501` values identified earlier are sufficient for practical light control
- the remaining unsolved problem is no longer API syntax; it is cloud dependency

Cloud-independent control path from here:

- stop spending time on stock-app API discovery
- move to bulb-level reverse engineering
- likely first tasks:
  - identify SoC / radio module inside the bulb
  - locate teardown, FCC photos, or existing firmware images
  - inspect for UART pads / flash package / known Tuya- or ESP-class hardware lineage

- `WLPA19 -> com.wyze.commonlight.lightv1.DeviceTransferPage`
- `DeviceTransferPage` immediately forwards into:
  - `/HLHWB2/opendevice`
  - `com.wyze.commonlight.lightv2.mvp.view.BulbV2Activity`

Interpretation:

- the tested original bulb is handled by the shared `lightv2` control flow
- reversing `BulbV2Activity` and `FragmentLightV2` is directly relevant to this bulb

## Decompiled Property ID Map

`ei.plutocase` exposes the property IDs used by the light controller.

Confirmed IDs relevant to basic light control:

- `P3`
  - on/off state
  - app sends `"0"` for off and `"1"` for on
- `P1501`
  - brightness percentage
- `P1502`
  - white temperature
- `P1507`
  - color value
- `P1508`
  - control mode / light state selector used by the UI logic

Code evidence:

- `FragmentLightV2.e(int brightness, String content)`
  - resolves `plutocase.plutodo().plutoif()` -> `P1501`
  - sends `M0("P1501", String.valueOf(brightness), true, true)`
- `FragmentLightV2.m1()`
  - resolves `plutocase.plutodo().plutothrows()` -> `P3`
  - sends `M0("P3", "1", false, true)`
- `FragmentLightV2` off path:
  - sends `M0("P3", "0", false, true)`

## Decompiled Payload Assembly

`oi.plutodo` builds the bulk property payload that is eventually submitted to the cloud layer.

Observed structure:

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

Behavior worth keeping:

- when the property map contains `P3 = "0"`, the bulk builder emits only the off property and stops adding others
- `device_model` is looked up from `WpkHomeManager.INSTANCE.getCurrentHomeDeviceBean(mac)`

This is consistent with the already decompiled cloud layer:

- single property:
  - `v2/device/set_property`
- bulk property list:
  - `v2/device_list/set_property_list`

## Practical Meaning

At this point, the unknowns for basic light control are no longer the property IDs.

The remaining unknowns are:

- the exact authenticated request headers / tokens used by the live app session
- whether any additional per-request values must be present beyond the already identified `sv`, `sc`, timestamp, and auth-related fields
- the exact `device_model` string submitted for the original bulb in the current account context

## Best Next Step

The highest-value next move is no longer general APK discovery.

It is:

1. instrument or patch the Android app to log the final outgoing request for `P3` and `P1501`
2. capture:
   - request path
   - headers
   - JSON body
3. build a minimal standalone replay client for:
   - off: `P3 = "0"`
   - on: `P3 = "1"`
   - brightness: `P1501 = "<percent>"`

## Local Patch Toolchain Ready

Verified on `2026-03-23`:

- official `apktool` downloaded:
  - `tools\apktool_3.0.1.jar`
- Android SDK tooling already present locally:
  - `C:\Users\mark\AppData\Local\Android\Sdk\platform-tools\adb.exe`
  - build-tools `zipalign.exe`
  - build-tools `apksigner.bat`
- local debug keystore exists:
  - `%USERPROFILE%\.android\debug.keystore`

Helper scripts added:

- `decompile_wyze_apk.ps1`
  - decodes `android_apk\base.apk` into `android_apk_decoded\`
- `rebuild_sign_wyze_apk.ps1`
  - rebuilds a decoded APK
  - aligns it
  - signs it with the debug keystore

Working result:

- `decompile_wyze_apk.ps1` completed successfully against the extracted Wyze `base.apk`
- decoded project now exists at:
  - `android_apk_decoded\`

## Additional Static Findings From Final Transport Layer

`ti.plutodo` confirms the concrete cloud calls used by the light controller:

- single property:
  - `plutoprivate(mac, model, pid, pvalue, callback)`
  - maps to `URL_SET_PROPERTY`
- bulk property list:
  - `plutoextends(deviceListJson, callback)`
  - maps to `URL_DEVICE_LIST_SET_PROPERTY_LIST`
- property fetch:
  - `plutoshort(mac, model, targetPidList, callback)`
  - maps to `URL_GET_PROPERTY_LIST`
- bulk property fetch:
  - `plutoconst(deviceList, targetPidList, callback)`
  - maps to `URL_DEVICE_LIST_GET_PROPERTY_LIST`

`ti.plutoif` confirms response parsing behavior:

- response `data` is logged internally with:
  - `WpkLogUtil.i("commonlight", "data json *********" + dataJson)`
- property responses are interpreted using the same IDs already mapped:
  - `P3` power
  - `P1501` brightness
  - `P1502` white temperature
  - `P1507` color

Interpretation:

- stock code gives us enough to reproduce request body structure
- request bodies are still not visibly logged in the static networking layer
- runtime capture still needs either:
  - attached-device log review if hidden logs exist elsewhere
  - APK patching
  - runtime instrumentation
