# wifi-mute

Automatically mutes/unmutes the laptop when connecting to specific Wi-Fi networks.

- Connect to **WorkNetwork** → sound muted
- Connect to **HomeNetwork** → sound unmuted

## How it works

- Windows logs event **8001** to `Microsoft-Windows-WLAN-AutoConfig/Operational` on every Wi-Fi connect (including resume-from-sleep reconnects).
- One scheduled task per network triggers on that event, filtered on SSID via an XPath subscription, and runs `Set-Mute.ps1`.
- `Set-Mute.ps1` toggles the default playback device through the CoreAudio COM API (`IAudioEndpointVolume`) using inline C# — no external tools or modules.
- The tasks pass `-Notify 1`, showing a silent toast ("Sound muted" / "Sound unmuted") via the WinRT toast API. The toast appears as sent by "Windows PowerShell" (borrowed AUMID) and is suppressed while Do Not Disturb / Focus Assist is active (still lands in the Action Center).

## Files

| File | Purpose |
|------|---------|
| `Set-Mute.ps1` | Mutes (`-Mute 1`) or unmutes (`-Mute 0`) the default playback device; `-Notify 1` shows a toast |
| `Install-WifiMuteTasks.ps1` | Registers the scheduled tasks; edit the `$networks` table at the top to change SSIDs |

## Install

Run as your own user (no admin needed):

```powershell
.\Install-WifiMuteTasks.ps1
```

Re-running is idempotent — existing tasks are overwritten. After moving this repo, re-run it: tasks reference the script by absolute path.

## Test

Trigger the tasks manually without switching networks:

```powershell
Start-ScheduledTask 'WiFi Mute - WorkNetwork'     # sound should mute
Start-ScheduledTask 'WiFi Unmute - HomeNetwork'    # sound should unmute
```

Or run the script directly: `.\Set-Mute.ps1 -Mute 1`

## Uninstall

```powershell
Unregister-ScheduledTask 'WiFi Mute - WorkNetwork', 'WiFi Unmute - HomeNetwork' -Confirm:$false
```

## Notes & limitations

- Only the **default** playback device is muted. Switching output devices after the event keeps the new device's own mute state.
- Tasks run as the logged-on user, non-elevated; nothing happens when nobody is logged in.
- The tasks reference `Set-Mute.ps1` by absolute path (`C:\DEV\utilities\wifi-mute\`).
- `-ExecutionPolicy Bypass` in the task action applies to that single invocation only.
