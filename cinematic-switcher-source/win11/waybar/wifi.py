"""NetworkManager status and Wi-Fi controls for the Windows taskbar."""

import json
import os
import sys
import time

import gi

gi.require_version("NM", "1.0")
from gi.repository import GLib, NM


AP_FLAGS = getattr(NM, "80211ApFlags")
SECURITY = getattr(NM, "80211ApSecurityFlags")
ACTIVE = NM.ActiveConnectionState


def signal_level(strength):
    return min(4, max(1, (strength + 24) // 25))


def security(ap):
    flags = ap.get_wpa_flags() | ap.get_rsn_flags()
    if flags & SECURITY.KEY_MGMT_SAE:
        return "WPA3 Personal", "sae"
    if flags & SECURITY.KEY_MGMT_PSK:
        return "WPA Personal", "wpa-psk"
    if flags & (SECURITY.KEY_MGMT_802_1X | SECURITY.KEY_MGMT_EAP_SUITE_B_192):
        return "Enterprise", "saved-only"
    if flags & (SECURITY.KEY_MGMT_OWE | SECURITY.KEY_MGMT_OWE_TM):
        return "Enhanced Open", "owe"
    if not ap.get_flags() & AP_FLAGS.PRIVACY:
        return "Open", "open"
    return ("WEP", "none") if not flags else ("Secured", "saved-only")


def ssid(ap):
    value = ap.get_ssid() if ap else None
    return bytes(value.get_data()).decode("utf-8", errors="replace") if value else ""


def active_device(device):
    connection = device.get_active_connection()
    return connection if connection and connection.get_state() == ACTIVE.ACTIVATED else None


def taskbar_status(client):
    primary = client.get_primary_connection()
    devices = []
    for device in client.get_devices():
        if isinstance(device, (NM.DeviceWifi, NM.DeviceEthernet)):
            connection = active_device(device)
            if connection:
                devices.append((device, connection))
    if not devices:
        return {"text": " ", "class": "offline", "tooltip": "Disconnected"}
    device, connection = max(
        devices, key=lambda pair: (pair[1] == primary, pair[1].get_default(), pair[1].get_default6())
    )
    if isinstance(device, NM.DeviceEthernet):
        return {"text": " ", "class": "ethernet", "tooltip": "Ethernet connected"}
    ap = device.get_active_access_point()
    strength = ap.get_strength() if ap else 0
    return {
        "text": " ", "class": f"wifi-{signal_level(strength)}",
        "tooltip": f"{ssid(ap) or 'Wi-Fi'} · {strength}%",
    }


class WifiPanel:
    def __init__(self, client):
        self.client = client
        self.message = ""
        self.busy = False
        self.activation = None
        self.deadline = 0

    def device(self):
        adapters = [device for device in self.client.get_devices() if isinstance(device, NM.DeviceWifi)]
        return next((device for device in adapters if active_device(device)), adapters[0] if adapters else None)

    @staticmethod
    def entries(device):
        active = device.get_active_access_point()
        profiles = device.get_available_connections()
        access_points = {}
        for ap in device.get_access_points():
            name = ssid(ap)
            if not name:
                continue
            label, mode = security(ap)
            path = ap.get_path()
            saved = next((profile for profile in profiles if ap.connection_valid(profile)), None)
            entry = {
                "id": path, "name": name, "security": label, "mode": mode,
                "strength": ap.get_strength(), "connected": ap == active,
                "saved": saved is not None,
            }
            # Keep one representative AP per network and security mode.
            key = (bytes(ap.get_ssid().get_data()), mode)
            previous = access_points.get(key)
            if previous is None or (entry["connected"], entry["strength"]) > (
                previous[0]["connected"], previous[0]["strength"]
            ):
                access_points[key] = (entry, ap, saved)
        return sorted(
            access_points.values(),
            key=lambda item: (not item[0]["connected"], -item[0]["strength"], item[0]["name"].casefold()),
        )

    def snapshot(self):
        enabled = self.client.get_property("wireless-enabled")
        hardware = self.client.get_property("wireless-hardware-enabled")
        device = self.device()
        if self.activation:
            state = self.activation.get_state()
            if state == ACTIVE.ACTIVATED:
                self.activation = None
                self.busy = False
                self.message = "Connected"
            elif state == ACTIVE.DEACTIVATED or time.monotonic() > self.deadline:
                self.activation = None
                self.busy = False
                self.message = "Could not connect. Check the password or network settings."
        return {
            "available": bool(device) and hardware, "enabled": enabled,
            "networks": [item[0] for item in self.entries(device)] if device and enabled else [],
            "message": self.message, "busy": self.busy,
        }

    def finish(self, finish, failure, activating=False):
        def done(source, result, *_):
            try:
                value = finish(result)
            except GLib.Error:
                self.message = failure
            else:
                if activating:
                    self.activation = value[0] if isinstance(value, tuple) else value
                    self.deadline = time.monotonic() + 45
                    self.message = "Connecting…"
                else:
                    self.message = ""
            self.busy = bool(self.activation)
        return done

    def scan(self, device):
        if device and self.client.get_property("wireless-enabled"):
            def scanned(source, result, *_):
                try:
                    device.request_scan_finish(result)
                except GLib.Error:
                    if not self.busy:
                        self.message = "Scan unavailable. Showing cached networks."
            device.request_scan_async(None, scanned)

    def connect(self, device, message):
        network = next((item for item in self.entries(device) if item[0]["id"] == message.get("id")), None)
        if not network:
            self.message = "Network no longer in range. Scan and try again."
            return
        entry, ap, saved = network
        supplied = message.get("password")
        if saved is not None and supplied is None:
            self.busy = True
            self.message = "Connecting…"
            self.client.activate_connection_async(
                saved, device, ap.get_path(), None,
                self.finish(self.client.activate_connection_finish, "Could not activate the saved connection.", True),
            )
            return
        mode = entry["mode"]
        if mode == "saved-only":
            self.message = "This network requires a saved NetworkManager profile."
            return
        if mode in {"sae", "wpa-psk", "none"} and not supplied:
            self.message = "Enter the Wi-Fi password."
            return

        profile = NM.SimpleConnection.new()
        wireless = NM.SettingWireless.new()
        wireless.set_property("ssid", ap.get_ssid())
        profile.add_setting(wireless)
        if mode != "open":
            secret = NM.SettingWirelessSecurity.new()
            secret.set_property("key-mgmt", mode)
            if mode in {"sae", "wpa-psk"}:
                secret.set_property("psk", supplied)
            elif mode == "none":
                secret.set_property("wep-key-type", NM.WepKeyType.KEY)
                secret.set_wep_key(0, supplied)
            profile.add_setting(secret)

        self.busy = True
        self.message = "Connecting…"
        options = GLib.Variant("a{sv}", {"persist": GLib.Variant("s", "volatile")})
        self.client.add_and_activate_connection2(
            profile, device, ap.get_path(), options, None,
            self.finish(self.client.add_and_activate_connection2_finish, "Could not start the connection.", True),
        )

    def handle(self, message):
        action = message.get("action")
        if self.busy:
            return
        self.message = ""
        device = self.device()
        if action == "radio":
            self.client.wireless_set_enabled(bool(message.get("enabled")))
        elif action == "scan":
            self.scan(device)
        elif action == "connect" and device:
            self.connect(device, message)
        elif action == "disconnect" and device:
            self.busy = True
            self.message = "Disconnecting…"
            device.disconnect_async(None, self.finish(device.disconnect_finish, "Could not disconnect Wi-Fi."))


def publish(data):
    print(json.dumps(data), flush=True)


def main():
    is_panel = sys.argv[1:] == ["panel"]
    offline = {"text": " ", "class": "offline", "tooltip": "NetworkManager unavailable"}
    while True:
        try:
            client = NM.Client.new(None)
            break
        except GLib.Error:
            if is_panel:
                publish({"available": False, "enabled": False, "networks": [], "message": "NetworkManager is unavailable.", "busy": False})
                return
            publish(offline)
            time.sleep(4)

    loop = GLib.MainLoop()
    panel = WifiPanel(client) if is_panel else None
    read_buffer = b""
    previous = None

    def refresh():
        nonlocal previous
        data = panel.snapshot() if panel else taskbar_status(client)
        if data != previous:
            try:
                publish(data)
            except BrokenPipeError:
                loop.quit()
                return False
            previous = data
        return True

    def read_command(_fd, condition):
        nonlocal read_buffer
        if not condition & GLib.IO_IN:
            loop.quit()
            return False
        data = os.read(sys.stdin.fileno(), 4096)
        if not data:
            loop.quit()
            return False
        read_buffer += data
        while b"\n" in read_buffer:
            raw, read_buffer = read_buffer.split(b"\n", 1)
            try:
                panel.handle(json.loads(raw))
            except (GLib.Error, TypeError, ValueError, AttributeError):
                panel.busy = False
                panel.message = "NetworkManager could not complete that request."
            # Command payloads, including passwords, go only to libnm.
        refresh()
        return True

    if panel:
        GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP, read_command)
        panel.scan(panel.device())
    if refresh():
        GLib.timeout_add(700 if panel else 1500, refresh)
        loop.run()


if __name__ == "__main__":
    main()
