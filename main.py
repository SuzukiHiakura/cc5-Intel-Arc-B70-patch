"""Open Explorer avatar requests with the Character Creator Python API."""
# SPDX-License-Identifier: GPL-3.0-only
import ctypes
import json
import os
from pathlib import Path
import time

import RLPy


folder = Path(os.environ["LOCALAPPDATA"]) / "CC5 Startup Patch"
timer = None
pending = None
callback = None


def write_result(result):
    temporary = folder / "last-open.tmp"
    temporary.write_text(json.dumps(result, indent=2), encoding="utf-8")
    temporary.replace(folder / "last-open.json")


def open_request(request):
    global pending
    if time.time() - request.stat().st_mtime > 600:
        request.unlink()
        return
    # Claim once. A crashed import must never replay on the next startup.
    active = request.with_suffix(".opening")
    request.rename(active)
    result = {"status": "failed"}
    deferred = False
    try:
        if active.stat().st_size > 131072:
            raise ValueError("Invalid file request.")
        file = Path(active.read_text(encoding="utf-8"))
        if (not file.is_absolute() or len(file.drive) != 2 or file.drive[1] != ":"
                or file.suffix.lower() != ".ccavatar" or not file.is_file()):
            raise ValueError("Choose an existing local .ccAvatar file.")
        result["file"] = str(file)
        if not request.name.endswith(".fresh.avatar") and (RLPy.RScene.GetAvatars() or RLPy.RScene.GetProps()):
            # Win32 Yes/No, question icon, No selected by default. IDYES is 6.
            answer = ctypes.windll.user32.MessageBoxW(
                None, f"Load {file.name} into the current scene? This can replace the current character.",
                "Open CC5 avatar", 0x00000124)
            if answer != 6:
                result["status"] = "cancelled"
                return
        status = RLPy.RFileIO.LoadFile(str(file))
        if status is None or status.IsError():
            raise RuntimeError("CC5's character loader could not read this file.")
        # Scene objects can appear on a later event-loop turn during cold startup.
        pending = (active, result, time.monotonic() + 60)
        deferred = True
    except Exception as error:
        result["error"] = str(error)
        write_result(result)
        RLPy.RUi.ShowMessageBox("CC5 avatar", str(error), RLPy.EMsgButton_Ok)
    finally:
        if not deferred:
            write_result(result)
            active.unlink(missing_ok=True)


def finish_request():
    global pending
    active, result, deadline = pending
    avatars = list(RLPy.RScene.GetAvatars() or [])
    if not avatars and time.monotonic() < deadline:
        return
    pending = None
    try:
        if not avatars:
            raise RuntimeError("No character appeared within 60 seconds of the CC5 load.")
        result.update(status="opened", avatars=[avatar.GetName() for avatar in avatars])
        # Optional local round-trip test. Normal opens do not enumerate morphs.
        if (folder / "measure-morphs.flag").is_file() and len(avatars) == 1:
            shape = avatars[0].GetAvatarShapingComponent()
            ids = {i for c in shape.GetShapingMorphCatergoryNames() for i in shape.GetShapingMorphIDs(c)}
            result["morphs"] = {i: shape.GetShapingMorphWeight(i) for i in sorted(ids)}
    except Exception as error:
        result["error"] = str(error)
        write_result(result)
        RLPy.RUi.ShowMessageBox("CC5 avatar", str(error), RLPy.EMsgButton_Ok)
    finally:
        write_result(result)
        active.unlink(missing_ok=True)


def check_requests():
    if pending:
        finish_request()
        return
    requests = sorted(folder.glob("*.avatar"), key=lambda p: p.name)
    if requests:
        timer.Stop()
        try:
            open_request(requests[0])
        finally:
            timer.Start()


class AvatarRequests(RLPy.RPyTimerCallback):
    def Timeout(self):
        check_requests()


def initialize_plugin():
    global timer, callback
    if timer is not None or ctypes.windll.shell32.IsUserAnAdmin():
        return
    folder.mkdir(exist_ok=True)
    callback = AvatarRequests()
    timer = RLPy.RPyTimer()
    timer.SetInterval(1000)
    timer.SetSingleShot(False)
    timer.RegisterPyTimerCallback(callback)
    timer.Start()


def run_script():
    initialize_plugin()
