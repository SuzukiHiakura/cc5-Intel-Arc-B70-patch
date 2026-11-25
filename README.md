# Intel Arc Pro B70 launch patch for Character Creator 5

Made with GPT Astra 6.2.

On the tested Intel Arc Pro B70 PC, Character Creator 5 exited before opening a window. Its installer had written five startup fields to the 32-bit Windows registry view. The 64-bit application looked for them in the native view. This patch copies those five fields from the installed product. You can then launch CC5 using its ordinary Windows shortcut.

## Tested on

| Component | Test configuration |
| --- | --- |
| Graphics | Intel Arc Pro B70, driver 32.0.101.8976. Intel UHD 630 also present. |
| System | MSI Z390-A Pro, Intel Core i7-8700K, 64 GB RAM (2 × 32 GB) |
| Windows | Windows 10 Education 22H2, build 19045, x64 |
| Character Creator | CC5 5.2.2310.1, executable file version 5.20.2310.1, default installation directory |

The installer checks the local product registration and the CC5 executable SHA-256 before applying the repair. The diagnosed failure was in startup registration. Graphics-driver behavior on other cards, other CC5 releases and individual rendering features need separate testing.

## Install or remove

1. Save your work and close CC5. Extract the ZIP into a folder. If Windows marks the downloaded ZIP as blocked, verify the source before using **Properties → Unblock** on that archive and extracting it.
2. Right-click **CC5 Repair.cmd**, select **Run as administrator**, and choose **2** to install. Option **1** checks the installation and works without elevation.
3. Start Character Creator normally, under your regular Windows account.

To uninstall, close CC5 and choose **3** from the same administrator menu. The installer records which settings and files it added. It checks ownership before removing values. A conflicting setting or an edited plug-in file produces an error so you can inspect the change. The signed Reallusion executable stays intact. The package contains only the repair source, test and license.

## Opening characters from Explorer

On the test installation, Windows already associated `.ccProject` with CC5. Its `.ccAvatar` registration supplied an icon but lacked an Open command. An Open command pointing straight to CC5 brought up an empty default project.

The patch adds an Explorer handler for local `.ccAvatar` files. It waits for a responsive project window, then passes the selected path to a plug-in in CC5's OpenPlugin directory. The plug-in calls Reallusion's own `RLPy.RFileIO.LoadFile` API. Opening a file from a closed app loads it into the fresh default project. When loading into an existing scene that contains an avatar or prop, the plug-in asks first. Run CC5 as your regular Windows user. The plug-in declines file requests in an elevated CC5 process.

The local result is recorded in `%LOCALAPPDATA%\CC5 Startup Patch\last-open.json`. Startup, a successful character load and fidelity to the original reference are separate checks. See [Reallusion’s OpenPlugin documentation](https://wiki.reallusion.com/IC_Python_API:Your_First_iClone_Python_Plugin).

## Validation

The original CC5 executable reached the default workspace through the repaired registration on the B70. The source executable SHA-256 was `0e5a23bdb0abf04efcc14218a272e3659e16e09c64702b531af8546a23dec3df`.

With CC5 closed, Windows Explorer's Open action loaded a 264,599,250-byte native avatar in about 55 seconds. CC5 showed the avatar filename in its title bar, returned the expected character, and all eight fitted body morphs matched the saved values exactly. A separate test in an already running CC5 session also matched all eight sliders. The cold-start test used this release's host-timer implementation. The readiness check recognizes both project and avatar window titles. Other CC5 builds, multi-user installations, and rendering performance have not been qualified.

`Test-Repair.ps1` uses a temporary registry key belonging to the current user. It checks install, repeat install, protection of changed values, rollback and repeat rollback.

## Credits and license

Created November 25, 2026. Astra 6.2 contributed the engineering plan and review. Codex implemented and tested the Windows repair. The deployment and verification pass took about 29 minutes (15:39–16:08 UTC), building on earlier startup diagnostics. The recorded session delta for that pass was about 36,000 output tokens and 141,000 uncached input tokens. Including repeated cached context, total input was about 16.7 million tokens. These figures cover this pass through the verified cold open.

GPL-3.0-only applies to the patch. Reallusion distributes Character Creator separately.
