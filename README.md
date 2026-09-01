# Automated Windows Recovery WIM

A Windows PE recovery environment that automatically finds Macrium Reflect backup images (`.mrimg`) and restores the selected image to **Disk 0**. The WIM is designed to boot from [Ventoy](https://www.ventoy.net/) without relying on a particular USB label, drive letter, or folder layout.

> [!CAUTION]
> This environment overwrites **Disk 0 without a final confirmation prompt**. Boot it only when you intend to erase and restore Disk 0. Selecting an image starts the restore immediately.

## Features

- Boots as a Windows PE WIM from Ventoy.
- Searches all available drive letters except the WinPE `X:` drive.
- Searches folders recursively for `.mrimg` files.
- Automatically selects the image when exactly one is found.
- Displays actual filenames in a numbered menu when multiple images are found.
- Restores the selected image to Disk 0.
- Does not depend on USB volume labels or fixed backup drive letters.
- Leaves the existing WinPE startup configuration intact.

## Requirements

- A working Macrium Reflect rescue WIM containing:

  ```text
  X:\Program Files\Macrium\DiskRestore.exe
  ```

- A Windows computer with DISM available.
- Administrator access when mounting and servicing the WIM.
- A Ventoy USB drive for booting the finished image.
- One or more valid `.mrimg` backup images on storage visible to Windows PE.

This repository does not grant a license to redistribute Macrium Reflect, Windows PE, or other third-party binaries. Confirm that you have the necessary rights before publishing or distributing a completed WIM.

For complete step-by-step servicing instructions, see [How to Add `auto_restore.cmd` to a Windows PE `boot.wim`](MODIFY-BOOT-WIM.md).

## Restore behavior

During startup, the script:

1. Initializes Windows PE with `wpeinit`.
2. Waits 10 seconds for storage devices to become available.
3. Recursively searches drives `C:` through `Z:`, excluding `X:`.
4. Stops with an error if no `.mrimg` file is found.
5. Selects the image automatically if exactly one is found.
6. Shows a numbered filename menu if multiple images are found.
7. Immediately restores the selected image to Disk 0.
8. Reboots when the restore utility completes successfully.

## Build the WIM

Start with a known-good rescue WIM. Do not build from a previously failing or partially modified image.

Open PowerShell as Administrator and create an empty mount directory:

```powershell
New-Item -ItemType Directory -Path "C:\WimMount" -Force
```

Mount the WIM:

```powershell
dism /Mount-Wim `
    /WimFile:"C:\path\to\rescue.wim" `
    /Index:1 `
    /MountDir:"C:\WimMount"
```

Copy the automation script into the mounted image:

```powershell
Copy-Item `
    -LiteralPath ".\auto_restore.cmd" `
    -Destination "C:\WimMount\Windows\System32\auto_restore.cmd" `
    -Force
```

Confirm that the correct script is present:

```powershell
Get-Content "C:\WimMount\Windows\System32\auto_restore.cmd"
```

Commit the change and unmount the WIM:

```powershell
dism /Unmount-Wim /MountDir:"C:\WimMount" /Commit
```

Do not modify `startnet.cmd`. The known-good rescue environment is expected to launch `auto_restore.cmd` through its existing startup configuration.

### Discarding a failed edit

If you need to abandon uncommitted changes:

```powershell
dism /Unmount-Wim /MountDir:"C:\WimMount" /Discard
```

`/Discard` permanently removes changes made during that mount session.

## Boot with Ventoy

1. Install Ventoy on a USB drive.
2. Copy the completed WIM onto the Ventoy data partition.
3. Copy one or more `.mrimg` backup files onto any storage device that Windows PE can access.
4. Boot the target computer from the Ventoy USB drive.
5. Select the recovery WIM from the Ventoy menu.
6. If prompted, select the desired backup filename.

The backup image does not need to be stored beside the WIM and does not require a particular drive letter or volume label.

## Important limitations

- The destination is always physical **Disk 0**.
- There is no final restore confirmation.
- The script assumes `DiskRestore.exe` exists at the path shown above.
- Storage devices must have a drive letter and be readable by Windows PE.
- Encrypted, unsupported, or driver-dependent storage may not appear.
- When different folders contain identically named images, the menu filenames may look identical even though their stored paths differ.

## Troubleshooting

### The WIM reboots during startup

Start again from the known-good WIM and replace only `auto_restore.cmd`. Avoid changing `startnet.cmd`, `winpeshl.ini`, or the initialization section while diagnosing the problem.

### No images are found

- Confirm that the filename ends in `.mrimg`.
- Confirm that Windows PE assigned the storage device a drive letter.
- Check whether the required storage controller or USB driver is present in the rescue environment.
- Verify that the image is not stored only on the excluded `X:` RAM drive.

### Windows PE initialization fails

Inspect the initialization log from a WinPE command prompt:

```text
X:\Windows\System32\wpeinit.log
```

### DISM reports that the mount directory is already in use

Check the current mount state:

```powershell
dism /Get-MountedWimInfo
```

Commit or discard the existing mount before attempting to mount another WIM at `C:\WimMount`.
