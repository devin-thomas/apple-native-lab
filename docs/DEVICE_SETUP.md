# Device setup

Run the lab on your own Mac, iPhone, and Apple Watch. Simulator builds need none of this.

## One-time: local signing

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Set `DEVELOPMENT_TEAM` to your team ID (Xcode > Settings > Accounts) and `LAB_BUNDLE_PREFIX` to a reverse-DNS prefix you control. `Config/Local.xcconfig` is ignored by Git. Choose the prefix once: each new prefix registers new app IDs, and free Personal Teams have a weekly app ID limit.

## Mac

```sh
script/build_and_run.sh        # Debug build, opened from build/
script/install_mac.sh          # Release build installed to ~/Applications/Native Lab.app
```

The Mac host signs to run locally by default and runs in the App Sandbox. It needs no team.

## iPhone or iPad

1. Connect the device by USB or on the same network, unlock it, and trust this Mac.
2. Turn on Developer Mode: **Settings > Privacy & Security > Developer Mode**, restart, then confirm **Turn On**.
3. List destinations, then install:

```sh
script/install_phone.sh
script/install_phone.sh <device-id>
```

With a free Personal Team, the first launch may require trusting your developer certificate in **Settings > General > VPN & Device Management**. Reinstall at least every seven days, because free provisioning profiles expire.

## Apple Watch

The Watch host (`LabWatch`) installs directly to a paired Watch. It is not embedded in the iPhone app, so an iPhone install never depends on Watch provisioning.

1. Pair the Watch with an iPhone that Xcode already sees. Keep the Watch unlocked, charged, and near both the iPhone and the Mac. Put the Mac and iPhone on the same network.
2. Open Xcode's **Window > Devices and Simulators** while the iPhone is connected. Xcode discovers the paired Watch through the iPhone and begins preparing it. This can take several minutes the first time.
3. On the Watch, open **Settings > Privacy & Security > Developer Mode** and turn it on. The option can stay hidden until Xcode has seen the Watch. The Watch restarts; confirm **Turn On** and enter the passcode.
4. Check that Xcode reports a usable destination. A destination is usable only when it shows no `error:` field:

```sh
script/install_watch.sh
```

5. Install and launch:

```sh
script/install_watch.sh <device-id>
```

### When the Watch does not appear

| Symptom | Next step |
|---|---|
| No physical watchOS destination at all | Unlock the Watch and iPhone, open Devices and Simulators, and wait for preparation. Confirm the Watch is paired to the connected iPhone. |
| `Developer Mode disabled` | Enable Developer Mode on the Watch, restart, and confirm. |
| A preparation error asking to unlock the Watch | Unlock it, keep it near the Mac, and list destinations again. If CoreDevice seems stale, quit Xcode, run `killall -9 CoreDeviceService`, and reopen Xcode. |
| `devicectl` does not list the Watch | Treat the `xcodebuild -showdestinations` output as authoritative, or run the `LabWatch` scheme from Xcode with the Watch selected. |

A Watch that runs the smoke host proves installation only. Watch experiments still need their own device evidence.
