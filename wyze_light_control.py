#!/usr/bin/env python3

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


API_URL = "https://app.wyzecam.com/app/v2/device_list/set_property_list"
DEFAULT_HOOK_LOG = Path("captures/android/logcat/wyze_hook_20260323-192300.txt")
DEFAULT_CONFIG_PATH = Path("local_config.json")
DEFAULT_DEVICE_MODEL = "WLPA19"
DEFAULT_APP_NAME = "com.hualai"
DEFAULT_APP_VERSION = "3.10.6.753"
DEFAULT_PHONE_SYSTEM_TYPE = "2"
DEFAULT_SC = "a626948714654991afd3c0dbd7cdb901"
DEFAULT_SV = "ddb9baef0d7f44379cd6bfaa8698e682"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send basic Wyze bulb control commands using the captured cloud request shape."
    )
    parser.add_argument(
        "command",
        choices=["on", "off", "brightness"],
        help="Light command to send.",
    )
    parser.add_argument(
        "value",
        nargs="?",
        type=int,
        help="Brightness level 1-100. Required when command is 'brightness'.",
    )
    parser.add_argument(
        "--hook-log",
        type=Path,
        default=DEFAULT_HOOK_LOG,
        help=f"Path to the captured WYZE_HOOK log. Default: {DEFAULT_HOOK_LOG}",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"Local JSON config file. Default: {DEFAULT_CONFIG_PATH}",
    )
    parser.add_argument("--access-token", help="Override access token.")
    parser.add_argument("--phone-id", help="Override phone_id.")
    parser.add_argument("--device-mac", help="Target device MAC without separators.")
    parser.add_argument("--device-model", help="Target device model.")
    parser.add_argument("--app-name", help="App package name.")
    parser.add_argument("--app-version", help="App version string.")
    parser.add_argument(
        "--phone-system-type",
        help="Phone system type used by the app wrapper.",
    )
    parser.add_argument("--sc", help="Wyze API sc value.")
    parser.add_argument("--sv", help="Wyze API sv value for device_list/set_property_list.")
    parser.add_argument(
        "--timeout",
        type=float,
        default=20.0,
        help="HTTP timeout in seconds.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the request body without sending it.",
    )
    return parser.parse_args()


def extract_bodies(log_path: Path) -> list[dict]:
    if not log_path.exists():
        raise FileNotFoundError(f"Hook log not found: {log_path}")

    bodies: list[dict] = []
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        marker = "E WYZE_HOOK: BODY="
        if marker not in line:
            continue
        raw_json = line.split(marker, 1)[1].strip()
        try:
            bodies.append(json.loads(raw_json))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Failed to parse JSON from hook log line: {line}") from exc
    if not bodies:
        raise ValueError(f"No WYZE_HOOK BODY lines found in: {log_path}")
    return bodies


def find_session_values(bodies: list[dict]) -> tuple[str, str]:
    for body in reversed(bodies):
        access_token = body.get("access_token")
        phone_id = body.get("phone_id")
        if access_token and phone_id:
            return access_token, phone_id
    raise ValueError("No access_token/phone_id pair found in the hook log.")


def load_local_config(config_path: Path) -> dict:
    if not config_path.exists():
        return {}
    try:
        return json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"Failed to parse config JSON: {config_path}") from exc


def resolve_setting(
    cli_value: str | None,
    env_name: str,
    config: dict,
    config_key: str,
    default: str | None = None,
) -> str | None:
    if cli_value:
        return cli_value
    env_value = os.getenv(env_name)
    if env_value:
        return env_value
    config_value = config.get(config_key)
    if isinstance(config_value, str) and config_value:
        return config_value
    return default


def build_property_list(command: str, brightness: int | None) -> list[dict[str, str]]:
    if command == "on":
        return [{"pid": "P3", "pvalue": "1"}]
    if command == "off":
        return [{"pid": "P3", "pvalue": "0"}]
    if brightness is None:
        raise ValueError("Brightness command requires a value.")
    if not 1 <= brightness <= 100:
        raise ValueError("Brightness must be between 1 and 100.")
    return [
        {"pid": "P3", "pvalue": "1"},
        {"pid": "P1501", "pvalue": str(brightness)},
    ]


def build_payload(args: argparse.Namespace, access_token: str, phone_id: str) -> dict:
    property_list = build_property_list(args.command, args.value)
    if not args.device_mac:
        raise ValueError("device_mac is required via --device-mac, environment, or local config")
    return {
        "access_token": access_token,
        "app_name": args.app_name,
        "app_ver": f"{args.app_name}___{args.app_version}",
        "app_version": args.app_version,
        "device_list": [
            {
                "device_mac": args.device_mac,
                "device_model": args.device_model,
                "property_list": property_list,
            }
        ],
        "phone_id": phone_id,
        "phone_system_type": args.phone_system_type,
        "sc": args.sc,
        "sv": args.sv,
        "ts": int(time.time() * 1000),
    }


def send_request(payload: dict, timeout: float) -> tuple[int, str]:
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        API_URL,
        data=data,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            "User-Agent": "WyzeLightControl/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.getcode(), response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return exc.code, body


def redact_payload(payload: dict) -> dict:
    redacted = json.loads(json.dumps(payload))
    token = redacted.get("access_token")
    if isinstance(token, str) and token:
        redacted["access_token"] = f"{token[:12]}...{token[-8:]}"
    return redacted


def main() -> int:
    args = parse_args()

    if args.command == "brightness" and args.value is None:
        print("brightness requires a numeric value between 1 and 100", file=sys.stderr)
        return 2
    if args.command != "brightness" and args.value is not None:
        print(f"{args.command} does not accept a numeric value", file=sys.stderr)
        return 2

    try:
        config = load_local_config(args.config)

        args.device_mac = resolve_setting(args.device_mac, "WYZE_DEVICE_MAC", config, "device_mac")
        args.device_model = resolve_setting(
            args.device_model,
            "WYZE_DEVICE_MODEL",
            config,
            "device_model",
            DEFAULT_DEVICE_MODEL,
        )
        args.app_name = resolve_setting(
            args.app_name,
            "WYZE_APP_NAME",
            config,
            "app_name",
            DEFAULT_APP_NAME,
        )
        args.app_version = resolve_setting(
            args.app_version,
            "WYZE_APP_VERSION",
            config,
            "app_version",
            DEFAULT_APP_VERSION,
        )
        args.phone_system_type = resolve_setting(
            args.phone_system_type,
            "WYZE_PHONE_SYSTEM_TYPE",
            config,
            "phone_system_type",
            DEFAULT_PHONE_SYSTEM_TYPE,
        )
        args.sc = resolve_setting(args.sc, "WYZE_SC", config, "sc", DEFAULT_SC)
        args.sv = resolve_setting(args.sv, "WYZE_SV", config, "sv", DEFAULT_SV)

        access_token = resolve_setting(args.access_token, "WYZE_ACCESS_TOKEN", config, "access_token")
        phone_id = resolve_setting(args.phone_id, "WYZE_PHONE_ID", config, "phone_id")
        if not access_token or not phone_id:
            bodies = extract_bodies(args.hook_log)
            logged_token, logged_phone_id = find_session_values(bodies)
            access_token = access_token or logged_token
            phone_id = phone_id or logged_phone_id

        payload = build_payload(args, access_token, phone_id)
    except (FileNotFoundError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.dry_run:
        print(json.dumps(redact_payload(payload), indent=2))
        return 0

    try:
        status_code, response_text = send_request(payload, args.timeout)
    except urllib.error.URLError as exc:
        print(f"request failed: {exc}", file=sys.stderr)
        return 1

    print(f"HTTP {status_code}")
    try:
        parsed = json.loads(response_text)
        print(json.dumps(parsed, indent=2))
    except json.JSONDecodeError:
        print(response_text)

    return 0 if 200 <= status_code < 300 else 1


if __name__ == "__main__":
    raise SystemExit(main())
