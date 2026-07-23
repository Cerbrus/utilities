<#
.SYNOPSIS
    Mutes or unmutes the default audio playback device.
.DESCRIPTION
    Uses the Windows CoreAudio COM API (IAudioEndpointVolume) via inline C#,
    so it works without any external tools or modules.
.PARAMETER Mute
    1 to mute, 0 to unmute. An [int] rather than a [bool] because scheduled
    tasks invoke this via `powershell.exe -File`, which cannot pass $true.
.PARAMETER Notify
    1 to show a toast notification of the change. Default 0 (silent).
.EXAMPLE
    .\Set-Mute.ps1 -Mute 1              # mute
    .\Set-Mute.ps1 -Mute 0 -Notify 1    # unmute, with toast
#>
param(
    [int]$Mute = 1,
    [int]$Notify = 0
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume
{
    // vtable slots 1-11 are unused here, but COM interop binds by vtable
    // position, so the padding must match the real interface exactly.
    int _1(); int _2(); int _3(); int _4(); int _5(); int _6();
    int _7(); int _8(); int _9(); int _10(); int _11();
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, Guid eventContext);
    int GetMute(out bool mute);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice
{
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IAudioEndpointVolume endpointVolume);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator
{
    int _1(); // EnumAudioEndpoints, unused
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumerator { }

public static class Audio
{
    public static void SetMute(bool mute)
    {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDevice device;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device)); // eRender, eMultimedia
        var iid = typeof(IAudioEndpointVolume).GUID;
        IAudioEndpointVolume volume;
        Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out volume)); // CLSCTX_ALL
        Marshal.ThrowExceptionForHR(volume.SetMute(mute, Guid.Empty));
    }
}
"@

[Audio]::SetMute($Mute -ne 0)

if ($Notify -ne 0) {
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

    $message = if ($Mute -ne 0) { 'Sound muted' } else { 'Sound unmuted' }
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml(@"
<toast duration="short">
  <visual><binding template="ToastGeneric">
    <text>Wi-Fi mute</text>
    <text>$message</text>
  </binding></visual>
  <audio silent="true"/>
</toast>
"@)

    # Toasts require a registered AUMID; borrow Windows PowerShell's so no app registration is needed.
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
        [Windows.UI.Notifications.ToastNotification]::new($xml))
}
