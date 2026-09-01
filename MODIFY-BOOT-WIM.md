# How to Add `auto_restore.cmd` to a Windows PE `boot.wim`

This guide explains how to take a known-good Windows PE or rescue `boot.wim`, replace its `auto_restore.cmd` file, save the modified image, and boot it with Ventoy.

> [!CAUTION]
> The supplied restore script writes the selected backup image directly to **Disk 0**. If one image is found, restoration begins automatically. If multiple images are found, restoration begins immediately after a filename is selected. There is no final confirmation prompt.

## What you need

- A Windows computer.
- An administrator account.
- A known-good bootable Windows PE or rescue WIM.
- The provided `auto_restore-v4.cmd` file.
- At least 2 GB of free temporary disk space.
- Ventoy or another supported method of booting the finished WIM.

The rescue environment must already contain:

```text
X:\Program Files\Macrium\DiskRestore.exe
```

The script does not install or redistribute the restore program.

## Important terminology

- **Source WIM:** The known-good WIM used as the starting point.
- **Working WIM:** A copy of the source WIM that you will modify.
- **Mount directory:** An empty folder where DISM exposes the contents of the WIM.
- **CMD file:** The `auto_restore.cmd` batch script copied into the mounted image.

Never modify your only known-good WIM. Always work on a copy.

## Example paths

This guide uses the following paths:

```text
Known-good WIM:
C:\Users\LabUser\Documents\codex-projects\Macrium-Automated-Rescue.wim

Working WIM:
C:\Users\LabUser\Documents\codex-projects\automated-restore.wim

Replacement script:
C:\Users\LabUser\Documents\codex-projects\auto_restore-v4.cmd

Mount directory:
C:\Mount
```

Change these paths if your files are stored elsewhere.

## Step 1: Open PowerShell as Administrator

1. Open the Start menu.
2. Search for **PowerShell** or **Terminal**.
3. Right-click it and select **Run as administrator**.
4. Accept the User Account Control prompt.

DISM cannot mount or modify a WIM without administrator privileges. Error `740` means the terminal was not elevated.

## Step 2: Check for an existing mounted image

Run:

```powershell
dism /Get-MountedWimInfo
```

If no image is mounted at `C:\Mount`, continue to Step 3.

If an image is already mounted there, decide whether to save or discard its changes.

To save the existing changes:

```powershell
dism /Unmount-Wim /MountDir:"C:\Mount" /Commit
```

To discard the existing changes:

```powershell
dism /Unmount-Wim /MountDir:"C:\Mount" /Discard
```

> [!WARNING]
> `/Discard` permanently removes every uncommitted change from that mount session.

## Step 3: Create a fresh working copy

Copy the known-good WIM to a new filename:

```powershell
Copy-Item `
    -LiteralPath "C:\Users\LabUser\Documents\codex-projects\Macrium-Automated-Rescue.wim" `
    -Destination "C:\Users\LabUser\Documents\codex-projects\automated-restore.wim" `
    -Force
```

This is the most important reliability step. If an earlier experimental WIM failed to boot, do not continue modifying it.

### Optional: verify that the copy is exact

```powershell
Get-FileHash -Algorithm SHA256 `
    "C:\Users\LabUser\Documents\codex-projects\Macrium-Automated-Rescue.wim", `
    "C:\Users\LabUser\Documents\codex-projects\automated-restore.wim"
```

The two SHA-256 hashes should be identical before the working WIM is modified.

## Step 4: Inspect the WIM indexes

A WIM can contain more than one image. List the available indexes:

```powershell
dism /Get-WimInfo /WimFile:"C:\Users\LabUser\Documents\codex-projects\automated-restore.wim"
```

Locate the bootable Windows PE or recovery image. The example rescue WIM contains one image, so this guide uses `/Index:1`.

If your WIM contains multiple indexes, make sure you modify the index that actually boots. Editing the wrong index will produce a WIM that boots without your changes.

## Step 5: Prepare an empty mount directory

Create `C:\Mount` if it does not exist:

```powershell
New-Item -ItemType Directory -Path "C:\Mount" -Force
```

The directory must be empty before mounting. Check it with:

```powershell
Get-ChildItem -Force "C:\Mount"
```

If the command displays files but DISM reports that no WIM is mounted there, do not blindly delete them. Confirm that `C:\Mount` is the intended temporary directory first.

## Step 6: Mount the working WIM

Run:

```powershell
dism /Mount-Wim `
    /WimFile:"C:\Users\LabUser\Documents\codex-projects\automated-restore.wim" `
    /Index:1 `
    /MountDir:"C:\Mount" `
    /CheckIntegrity
```

Wait for DISM to report:

```text
The operation completed successfully.
```

Do not unplug the storage device, move the WIM, or close Windows while DISM is mounting or committing it.

## Step 7: Back up the original script

Before replacing it, copy the original script out of the mounted WIM:

```powershell
Copy-Item `
    -LiteralPath "C:\Mount\Windows\System32\auto_restore.cmd" `
    -Destination "C:\Users\LabUser\Documents\codex-projects\auto_restore-original.cmd" `
    -Force
```

This backup makes it easy to compare or restore the original behavior later.

## Step 8: Install the new CMD file

Copy `auto_restore-v4.cmd` into the mounted WIM and rename it to `auto_restore.cmd`:

```powershell
Copy-Item `
    -LiteralPath "C:\Users\LabUser\Documents\codex-projects\auto_restore-v4.cmd" `
    -Destination "C:\Mount\Windows\System32\auto_restore.cmd" `
    -Force
```

The destination filename must remain exactly:

```text
auto_restore.cmd
```

Do not name the in-image copy `auto_restore-v4.cmd` unless you also change the existing launcher. This project intentionally leaves the launcher unchanged.

Do not modify:

```text
C:\Mount\Windows\System32\startnet.cmd
C:\Mount\Windows\System32\Winpeshl.ini
```

## Step 9: Verify the installed script

Display the installed file:

```powershell
Get-Content "C:\Mount\Windows\System32\auto_restore.cmd"
```

Confirm that it includes the expected filename-menu line:

```text
for /L %%I in (1,1,%IMAGECOUNT%) do call :show_image %%I
```

Confirm that delayed expansion is absent:

```powershell
Select-String `
    -Path "C:\Mount\Windows\System32\auto_restore.cmd" `
    -Pattern "setlocal|EnableDelayedExpansion"
```

No output is expected.

Compare the source and installed file hashes:

```powershell
Get-FileHash -Algorithm SHA256 `
    "C:\Users\LabUser\Documents\codex-projects\auto_restore-v4.cmd", `
    "C:\Mount\Windows\System32\auto_restore.cmd"
```

The hashes should match.

## Step 10: Commit and unmount

Save the change back into the WIM:

```powershell
dism /Unmount-Wim `
    /MountDir:"C:\Mount" `
    /Commit `
    /CheckIntegrity
```

Wait for both the save and unmount operations to complete successfully.

Verify that nothing remains mounted:

```powershell
dism /Get-MountedWimInfo
```

Do not copy or boot the WIM while it is still mounted.

## Step 11: Rename the finished WIM if desired

The internal filename does not control the script. You can give the completed WIM a descriptive name:

```powershell
Rename-Item `
    -LiteralPath "C:\Users\LabUser\Documents\codex-projects\automated-restore.wim" `
    -NewName "automated-windows-restore.wim"
```

## Step 12: Copy the WIM to Ventoy

Copy the completed WIM to the large data partition on the Ventoy USB drive. For example, if Ventoy is mounted as `V:`:

```powershell
Copy-Item `
    -LiteralPath "C:\Users\LabUser\Documents\codex-projects\automated-windows-restore.wim" `
    -Destination "V:\automated-windows-restore.wim"
```

Do not assume that Ventoy will always receive drive letter `V:`. Check File Explorer or `Get-Volume` first.

Place one or more `.mrimg` backup files anywhere on storage that the rescue environment can read. They do not need to be beside the WIM, and the storage volume does not need a specific label.

## Step 13: Test safely

Test on non-production hardware or in a controlled environment.

Expected behavior:

- With no images, the script reports that no `.mrimg` image was found and pauses.
- With one image, the script selects it automatically and starts restoring Disk 0.
- With multiple images, the script displays their filenames and asks for a number.
- After a valid selection, restoration begins immediately with no final confirmation.

Because the script targets Disk 0, do not perform a full test on a machine whose Disk 0 contains data you need.

## Command Prompt equivalents

The instructions above use PowerShell. If you use an elevated Command Prompt instead, use `copy /y` rather than PowerShell's `Copy-Item`:

```bat
copy /y "C:\Users\LabUser\Documents\codex-projects\auto_restore-v4.cmd" "C:\Mount\Windows\System32\auto_restore.cmd"
```

Do not use this CMD syntax in PowerShell:

```text
copy /y ...
```

In PowerShell, `copy` is an alias for `Copy-Item`, and `/y` causes a parameter error.

Also use literal underscores in filenames:

```text
auto_restore-v4.cmd
```

Do not type Markdown escape characters such as:

```text
auto\_restore-v4.cmd
```

## Updating the script later

To install a newer CMD file:

1. Make a backup copy of the last working WIM.
2. Mount the working copy.
3. Replace only `Windows\System32\auto_restore.cmd`.
4. Verify the source and installed hashes.
5. Commit and unmount.
6. Test before deleting the previous working WIM.

Change one component at a time. This makes regressions much easier to identify.

## Troubleshooting

### Error 740: elevated permissions are required

Close the terminal and reopen PowerShell or Command Prompt with **Run as administrator**.

### Error 0xc1420117 or a mount directory already in use

Inspect mounted images:

```powershell
dism /Get-MountedWimInfo
```

Unmount the existing image with `/Commit` or `/Discard` as appropriate.

### DISM says the mount directory is not empty

Use a new empty directory, such as:

```powershell
New-Item -ItemType Directory -Path "C:\WimMount" -Force
```

Then substitute `C:\WimMount` for `C:\Mount` in every command.

### The WIM boots but runs the old script

- Confirm that you modified the booted WIM, not another copy.
- Confirm that you used the correct WIM index.
- Confirm that the destination was `Windows\System32\auto_restore.cmd`.
- Confirm that DISM was unmounted with `/Commit`, not `/Discard`.
- Delete the old WIM from Ventoy before copying the new one.
- Compare hashes to make sure the Ventoy copy changed.

### The WIM reboots immediately

Return to the known-good WIM and replace only `auto_restore.cmd`. Do not change `startnet.cmd` or `Winpeshl.ini` while isolating the failure.

### DISM was interrupted

First inspect the mount state:

```powershell
dism /Get-MountedWimInfo
```

If DISM reports a recoverable mounted image, try:

```powershell
dism /Remount-Wim /MountDir:"C:\Mount"
```

If there is no work worth preserving and the mount is abandoned, use DISM cleanup only after confirming that no valid image remains mounted:

```powershell
dism /Cleanup-Mountpoints
```

## Reference

Microsoft documents that the mount directory must already exist and be empty, a WIM index or name is required, and unmounting requires either `/Commit` or `/Discard`: [DISM image-management options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-image-management-command-line-options-s14?view=windows-10).

See also [Modify a Windows image using DISM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/mount-and-modify-a-windows-image-using-dism?view=windows-11).
