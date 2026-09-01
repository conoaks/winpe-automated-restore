# Build an Automated Restore WIM from Macrium Reflect Rescue Media

This guide starts with a default Macrium Reflect Windows PE or Windows RE rescue image and modifies its `boot.wim` so it automatically finds `.mrimg` backups and restores the selected image to Disk 0.

The finished WIM is intended to boot from Ventoy and makes no assumptions about USB labels, backup-drive letters, or folder layouts.

> [!CAUTION]
> This environment overwrites **Disk 0**. One image is restored automatically. When several images exist, restoration begins immediately after a filename is selected. There is no final confirmation prompt.

## What changes

The customization installs:

```text
Windows\System32\auto_restore.cmd
Windows\System32\Winpeshl.ini
```

`Winpeshl.ini` replaces the normal rescue-interface startup with this command:

```ini
[LaunchApps]
%SYSTEMDRIVE%\Windows\System32\cmd.exe, /c %SYSTEMDRIVE%\Windows\System32\auto_restore.cmd
```

Leave the existing `startnet.cmd` unchanged. It normally contains:

```bat
wpeinit
```

## Requirements

- A licensed Macrium Reflect installation.
- Default Macrium rescue media built with Windows PE or Windows RE.
- This repository's `auto_restore.cmd`.
- Administrator access and DISM.
- At least 2 GB of temporary free space.
- Ventoy or another supported WIM boot method.

The rescue image must contain:

```text
X:\Program Files\Macrium\DiskRestore.exe
```

This project does not provide or license Macrium Reflect, Windows PE, or Windows RE binaries.

## Generic working paths

```text
C:\RecoveryWim\source-boot.wim
C:\RecoveryWim\custom-boot.wim
C:\RecoveryWim\auto_restore.cmd
C:\RecoveryWim\Winpeshl.ini
C:\WimMount
```

You can use different paths, but update every command consistently.

## Automated method

The repository includes `Build-AutomatedRestoreWim.ps1`, which performs the mounting, validation, file installation, verification, commit, and cleanup steps automatically.

Place these three files together:

```text
Build-AutomatedRestoreWim.ps1
auto_restore.cmd
Winpeshl.ini
```

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\Build-AutomatedRestoreWim.ps1 `
    -SourceWim "C:\RecoveryWim\source-boot.wim" `
    -OutputWim "C:\RecoveryWim\custom-boot.wim"
```

If the output file already exists and you intentionally want to replace it, add `-Force`.

The script never modifies the source WIM in place. It also refuses a non-empty mount directory, verifies `DiskRestore.exe`, leaves `startnet.cmd` unchanged, checks both installed file hashes, and discards its mounted changes if an error occurs.

The remaining sections document the equivalent manual process and are useful for auditing or troubleshooting.

## 1. Build default Macrium rescue media

In Macrium Reflect:

1. Open **Other Tasks**.
2. Select **Create Rescue Media**.
3. Select a Windows PE or Windows RE base suitable for the target computer.
4. Include required storage, USB, RAID, and network drivers.
5. Build an ISO or USB rescue drive.
6. Boot it normally and verify that it detects Disk 0 and the storage containing your backups.

Do not automate rescue media until its default version boots successfully and detects all required storage.

## 2. Copy `boot.wim`

The rescue image is normally located at:

```text
sources\boot.wim
```

For rescue USB media, copy `sources\boot.wim` from the USB drive.

For an ISO:

1. Right-click the ISO and select **Mount**.
2. Open the virtual DVD drive.
3. Copy `sources\boot.wim`.
4. Eject the ISO afterward.

Place the file at:

```text
C:\RecoveryWim\source-boot.wim
```

Never modify your only known-good copy.

## 3. Prepare the launcher file

Place the repository script at:

```text
C:\RecoveryWim\auto_restore.cmd
```

Create `C:\RecoveryWim\Winpeshl.ini` containing exactly:

```ini
[LaunchApps]
%SYSTEMDRIVE%\Windows\System32\cmd.exe, /c %SYSTEMDRIVE%\Windows\System32\auto_restore.cmd
```

Ensure the filename is `Winpeshl.ini`, not `Winpeshl.ini.txt`.

## 4. Open PowerShell as Administrator

Right-click PowerShell or Windows Terminal and select **Run as administrator**. DISM error `740` means the terminal is not elevated.

## 5. Create a clean working copy

```powershell
New-Item -ItemType Directory -Path "C:\RecoveryWim" -Force

Copy-Item `
    -LiteralPath "C:\RecoveryWim\source-boot.wim" `
    -Destination "C:\RecoveryWim\custom-boot.wim" `
    -Force
```

Optionally confirm that both files initially have the same hash:

```powershell
Get-FileHash -Algorithm SHA256 `
    "C:\RecoveryWim\source-boot.wim", `
    "C:\RecoveryWim\custom-boot.wim"
```

## 6. Identify the bootable WIM index

```powershell
dism /Get-WimInfo /WimFile:"C:\RecoveryWim\custom-boot.wim"
```

Most Macrium rescue WIMs contain one image at index 1. The commands below use `/Index:1`. If yours contains several indexes, modify the Windows PE or recovery index that actually boots.

## 7. Check for existing mounts

```powershell
dism /Get-MountedWimInfo
```

If `C:\WimMount` is already in use, save that mount with:

```powershell
dism /Unmount-Wim /MountDir:"C:\WimMount" /Commit
```

Or intentionally discard it with:

```powershell
dism /Unmount-Wim /MountDir:"C:\WimMount" /Discard
```

`/Discard` permanently removes all uncommitted changes from that mount session.

## 8. Mount the working WIM

The mount directory must exist and be empty:

```powershell
New-Item -ItemType Directory -Path "C:\WimMount" -Force
Get-ChildItem -Force "C:\WimMount"
```

Mount index 1:

```powershell
dism /Mount-Wim `
    /WimFile:"C:\RecoveryWim\custom-boot.wim" `
    /Index:1 `
    /MountDir:"C:\WimMount" `
    /CheckIntegrity
```

Wait for DISM to report that the operation completed successfully.

## 9. Verify the required restore utility

```powershell
Test-Path "C:\WimMount\Program Files\Macrium\DiskRestore.exe"
```

The result must be `True`. If it is `False`, discard the mount and use a compatible Macrium rescue build.

## 10. Inspect and preserve `startnet.cmd`

```powershell
Get-Content "C:\WimMount\Windows\System32\startnet.cmd"
```

It will normally contain `wpeinit`. Do not add `auto_restore.cmd` to this file, and do not remove `wpeinit`.

## 11. Back up the original startup files

```powershell
New-Item -ItemType Directory -Path "C:\RecoveryWim\original-files" -Force

Copy-Item `
    -LiteralPath "C:\WimMount\Windows\System32\startnet.cmd" `
    -Destination "C:\RecoveryWim\original-files\startnet.cmd" `
    -Force

if (Test-Path "C:\WimMount\Windows\System32\Winpeshl.ini") {
    Copy-Item `
        -LiteralPath "C:\WimMount\Windows\System32\Winpeshl.ini" `
        -Destination "C:\RecoveryWim\original-files\Winpeshl.ini" `
        -Force
}
```

Replacing the default `Winpeshl.ini` changes startup behavior, so keep this backup with the original WIM.

## 12. Install the automation script

```powershell
Copy-Item `
    -LiteralPath "C:\RecoveryWim\auto_restore.cmd" `
    -Destination "C:\WimMount\Windows\System32\auto_restore.cmd" `
    -Force
```

The in-image filename must be exactly `auto_restore.cmd`.

## 13. Install the automatic launcher

```powershell
Copy-Item `
    -LiteralPath "C:\RecoveryWim\Winpeshl.ini" `
    -Destination "C:\WimMount\Windows\System32\Winpeshl.ini" `
    -Force
```

This is the required edit that makes the default Macrium image call `auto_restore.cmd` instead of opening the normal rescue interface.

## 14. Verify the startup files

```powershell
Get-Content "C:\WimMount\Windows\System32\startnet.cmd"
Get-Content "C:\WimMount\Windows\System32\Winpeshl.ini"
Get-Content "C:\WimMount\Windows\System32\auto_restore.cmd"
```

Verify that the script copied correctly:

```powershell
Get-FileHash -Algorithm SHA256 `
    "C:\RecoveryWim\auto_restore.cmd", `
    "C:\WimMount\Windows\System32\auto_restore.cmd"
```

Both hashes should match.

Confirm that the stable script does not use delayed expansion:

```powershell
Select-String `
    -Path "C:\WimMount\Windows\System32\auto_restore.cmd" `
    -Pattern "setlocal|EnableDelayedExpansion"
```

No output is expected.

## 15. Commit and unmount

```powershell
dism /Unmount-Wim `
    /MountDir:"C:\WimMount" `
    /Commit `
    /CheckIntegrity
```

Confirm that nothing remains mounted:

```powershell
dism /Get-MountedWimInfo
```

Do not copy or boot the WIM while it is mounted.

## 16. Optional read-only verification

```powershell
dism /Mount-Wim `
    /WimFile:"C:\RecoveryWim\custom-boot.wim" `
    /Index:1 `
    /MountDir:"C:\WimMount" `
    /ReadOnly

Get-Content "C:\WimMount\Windows\System32\Winpeshl.ini"
Get-Content "C:\WimMount\Windows\System32\auto_restore.cmd"

dism /Unmount-Wim /MountDir:"C:\WimMount" /Discard
```

## 17. Copy the WIM to Ventoy

Determine the Ventoy data-partition drive letter using File Explorer or:

```powershell
Get-Volume
```

If the data partition is `V:`, copy the WIM with:

```powershell
Copy-Item `
    -LiteralPath "C:\RecoveryWim\custom-boot.wim" `
    -Destination "V:\custom-boot.wim" `
    -Force
```

Do not assume Ventoy will always use `V:`.

Place one or more `.mrimg` files anywhere on storage visible to Windows PE. They do not need to be beside the WIM or on a specially named volume.

## 18. Test safely

Test on non-production hardware or in a controlled environment.

Expected behavior:

- No images: an error is shown and the script pauses.
- One image: it is selected automatically and restored to Disk 0.
- Multiple images: their filenames appear in a numbered menu.
- Valid selection: restoration starts immediately without another confirmation.

Do not test on a computer whose Disk 0 contains data you need.

## Command Prompt equivalents

The guide uses PowerShell. From an elevated Command Prompt, the two file-copy operations are:

```bat
copy /y "C:\RecoveryWim\auto_restore.cmd" "C:\WimMount\Windows\System32\auto_restore.cmd"
copy /y "C:\RecoveryWim\Winpeshl.ini" "C:\WimMount\Windows\System32\Winpeshl.ini"
```

Do not use `copy /y` in PowerShell; PowerShell's `copy` alias does not accept `/y`.

## Troubleshooting

### The normal Macrium interface still opens

- Confirm that `Winpeshl.ini` is in `Windows\System32` inside the WIM.
- Confirm that it was not saved as `Winpeshl.ini.txt`.
- Confirm that its command names `auto_restore.cmd`.
- Confirm that you modified the index that boots.
- Confirm that DISM was unmounted with `/Commit`.
- Remove the older WIM from Ventoy before copying the rebuilt file.

### The WIM reboots immediately

- Start over from a fresh copy of the default, working Macrium `boot.wim`.
- Add only `auto_restore.cmd` and `Winpeshl.ini`.
- Leave `startnet.cmd` unchanged.
- Confirm that the script does not contain delayed expansion.

### No backup images are found

- Confirm that filenames end in `.mrimg`.
- Confirm that Windows PE assigned the storage device a drive letter.
- Include the necessary storage or USB drivers when building Macrium rescue media.
- The WinPE `X:` RAM drive is intentionally excluded.

### A mount is stuck

Inspect it:

```powershell
dism /Get-MountedWimInfo
```

Try remounting a recoverable image:

```powershell
dism /Remount-Wim /MountDir:"C:\WimMount"
```

Use cleanup only when no mounted changes need to be preserved:

```powershell
dism /Cleanup-Mountpoints
```

## References

- [Macrium Reflect KnowledgeBase](https://knowledgebase.macrium.com/)
- [Microsoft DISM image-management options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-image-management-command-line-options-s14?view=windows-10)
- [Modify a Windows image using DISM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/mount-and-modify-a-windows-image-using-dism?view=windows-11)
