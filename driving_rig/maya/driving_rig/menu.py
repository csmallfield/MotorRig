"""Menu + shelf, and install / uninstall.

install(path) is what the drag-and-drop installer calls. It:
  - adds a marked block to your userSetup.py (sys.path + menu at startup) - idempotent,
    and removed again by uninstall()
  - builds the "Driving Rig" menu and the "DrivingRig" shelf right away (no restart)
"""
from __future__ import annotations

import os
import traceback

from maya import cmds, mel

MENU = "drivingRigMenu"
SHELF = "DrivingRig"
BEGIN = "# >>> driving_rig (managed block - remove via Driving Rig > Uninstall) >>>"
END = "# <<< driving_rig <<<"
HERE = os.path.dirname(os.path.abspath(__file__))
ICONS = os.path.join(os.path.dirname(HERE), "icons")


def _run(fn, *args):
    try:
        fn(*args)
    except Exception as ex:
        traceback.print_exc()
        cmds.confirmDialog(title="Driving Rig", message=str(ex), button=["OK"])


def _import_dialog(*_):
    from . import ui
    ui.show()


def _import_scene(*_):
    from . import importer

    def go():
        kw = {}
        res = cmds.fileDialog2(fileMode=1, caption="Driving Rig scene (pick scene.json)",
                               fileFilter="Driving Rig scene (scene.json);;OBJ in a scene folder (*.obj)")
        if not res:
            return
        grp = importer.import_scene(res[0])
        cmds.confirmDialog(title="Driving Rig", message=cmds.getAttr(grp + ".drvLastCheck"), button=["OK"])
    _run(go)


def _world_scale(*_):
    from . import mayautil

    def go():
        cur = mayautil.get_world_scale()
        res = cmds.promptDialog(title="Driving Rig - World Scale", button=["Set", "Cancel"],
                                message="DrivingRig_world.worldScale\n1.0 = true size (cm)   0.1 = one unit per 10 cm",
                                text=str(cur if cur is not None else 1.0), defaultButton="Set",
                                cancelButton="Cancel", dismissString="Cancel")
        if res == "Set":
            value = float(cmds.promptDialog(query=True, text=True))
            if value <= 0.0:
                raise ValueError("World scale must be greater than 0")
            mayautil.world_group(value)
            cmds.select(mayautil.WORLD)
    _run(go)


def _resolve(*_):
    from . import importer

    def go():
        importer.resolve_spin()
        root = importer.find_rig_root()
        cmds.confirmDialog(title="Driving Rig", message=cmds.getAttr(root + ".drvLastCheck"), button=["OK"])
    _run(go)


def _check(*_):
    from . import importer, bake

    def go():
        reps = importer.check_spin()
        warn = [w for w, r in reps.items() if not abs(r["radius_error_percent"]) <= bake.RADIUS_WARN_PERCENT]
        root = importer.find_rig_root()
        cmds.confirmDialog(title="Driving Rig", button=["OK"],
                           message=importer._format_report(cmds.getAttr(root + ".drvTakeName"), reps, warn, "Check"))
    _run(go)


def _bind_car(*_):
    from . import bind

    def go():
        b = bind.create_bind_car()
        cmds.select(clear=True)
        cmds.confirmDialog(title="Driving Rig", button=["OK"], message=(
            "Bind car created: %s\n\nParked at the origin at ride height, wheels straight. Line your "
            "model up with it, in groups named chassis, wheel_FL, wheel_FR, wheel_RL, wheel_RR "
            "(and optionally steering_wheel) - or use Create Model Groups. Then select the model "
            "group and the rig and Attach Model." % b))
    _run(go)


def _model_groups(*_):
    from . import bind
    _run(bind.create_model_groups)


def _split_selection():
    from . import bind, importer
    sel = cmds.ls(selection=True, long=True) or []
    rigs = [importer.find_rig_root(n) for n in sel]
    rig_root = next((r for r in rigs if r), None)
    model = next((n for n, r in zip(sel, rigs) if not r), None)
    if rig_root is None and len(importer.list_rigs()) == 1:
        rig_root = importer.list_rigs()[0]
    if model is None or rig_root is None:
        raise bind.BindError("Select the model's top group and the take rig (any node of it).")
    return model, rig_root


def _attach(*_):
    from . import bind

    def go():
        model, rig_root = _split_selection()
        done = bind.attach_model(model, rig_root)
        cmds.confirmDialog(title="Driving Rig", button=["OK"], message="Attached to %s:\n  %s" % (
            rig_root.split("|")[-1], "\n  ".join("%s -> %s" % (p, n.split("|")[-1]) for p, n in done.items())))
    _run(go)


def _detach(*_):
    from . import bind

    def go():
        back = bind.detach_model()
        cmds.confirmDialog(title="Driving Rig", button=["OK"],
                           message="Detached %d groups; they're back where you placed them." % len(back))
    _run(go)


def _toggle_proxy(*_):
    from . import importer

    def go():
        root = importer.find_rig_root()
        if not root:
            raise RuntimeError("Select a Driving Rig first.")
        cmds.setAttr(root + ".proxyVisibility", not cmds.getAttr(root + ".proxyVisibility"))
    _run(go)


def _select_root(*_):
    from . import importer
    root = importer.find_rig_root()
    if root:
        cmds.select(root)


def _delete(*_):
    from . import importer
    root = importer.find_rig_root() or importer._find_scene_root()
    if not root:
        cmds.warning("Select a Driving Rig or imported scene first.")
        return
    if cmds.confirmDialog(title="Driving Rig", message="Delete %s and everything in its namespace?" % root,
                          button=["Delete", "Cancel"], cancelButton="Cancel") == "Delete":
        importer.delete_rig(root)


def _about(*_):
    from . import __version__
    cmds.confirmDialog(title="Driving Rig", button=["OK"], message=(
        "Driving Rig %s - Godot take importer\n\n%s\n\nSee README.md and docs/SCHEMA.md in the project."
        % (__version__, os.path.dirname(HERE))))


def create_menu():
    if cmds.about(batch=True):
        return
    if cmds.menu(MENU, exists=True):
        cmds.deleteUI(MENU)
    main = mel.eval("$tmp = $gMainWindow")
    cmds.menu(MENU, label="Driving Rig", parent=main, tearOff=True)
    cmds.menuItem(label="Import Take...", command=_import_dialog, image=_icon("import"))
    cmds.menuItem(label="Import Scene Geo...", command=_import_scene, image=_icon("scene"),
                  annotation="Terrain + props exported from the Godot take browser, in the takes' space")
    cmds.menuItem(divider=True)
    cmds.menuItem(label="Re-solve Spin (selected rig)", command=_resolve, image=_icon("resolve"),
                  annotation="Rebuild wheel spin from the car's travel in the scene - after retimes/offsets")
    cmds.menuItem(label="Check Spin (selected rig)", command=_check,
                  annotation="Effective wheel radius vs the take - catches radius / scale / contact errors")
    cmds.menuItem(label="World Scale...", command=_world_scale,
                  annotation="Scale every Driving Rig import at once (DrivingRig_world.worldScale)")
    cmds.menuItem(label="Car Model", subMenu=True, tearOff=True)
    cmds.menuItem(label="1  Create Bind Car (selected rig)", command=_bind_car,
                  annotation="Static copy of the rig at rest, to line your model up against")
    cmds.menuItem(label="2  Create Model Groups (optional)", command=_model_groups,
                  annotation="Empty, correctly named groups at the bind car's parts")
    cmds.menuItem(label="3  Attach Model (select model group + rig)", command=_attach)
    cmds.menuItem(label="Detach Model (selected rig)", command=_detach)
    cmds.menuItem(label="Toggle Proxy Geometry (selected rig)", command=_toggle_proxy)
    cmds.setParent("..", menu=True)
    cmds.menuItem(label="Select Rig Root", command=_select_root)
    cmds.menuItem(label="Delete Rig / Scene...", command=_delete)
    cmds.menuItem(divider=True)
    cmds.menuItem(label="Rebuild Shelf", command=lambda *_: create_shelf())
    cmds.menuItem(label="About", command=_about)
    cmds.menuItem(label="Uninstall...", command=lambda *_: _run(_confirm_uninstall))


def _icon(name):
    p = os.path.join(ICONS, "driving_rig_%s.png" % name)
    return p if os.path.isfile(p) else ""


def create_shelf():
    if cmds.about(batch=True):
        return
    top = mel.eval("$tmp = $gShelfTopLevel")
    if cmds.shelfLayout(SHELF, exists=True):
        for b in cmds.shelfLayout(SHELF, query=True, childArray=True) or []:
            cmds.deleteUI(b)
    else:
        cmds.shelfLayout(SHELF, parent=top)
    for label, icon, cmd, ann in (
            ("Import", "import", "import driving_rig.ui as _u; _u.show()", "Driving Rig: import a take"),
            ("Scene", "scene", "import driving_rig.menu as _m; _m._import_scene()",
             "Driving Rig: import scene geometry exported from Godot"),
            ("Solve", "resolve", "import driving_rig.menu as _m; _m._resolve()",
             "Driving Rig: re-solve wheel spin on the selected rig")):
        cmds.shelfButton(parent=SHELF, label=label, annotation=ann, image=_icon(icon) or "commandButton.png",
                         imageOverlayLabel="" if _icon(icon) else label, command=cmd, sourceType="python")
    cmds.saveAllShelves(top)


def _read_user_setup(path):
    """Your userSetup.py, decoded byte-for-byte (latin-1 maps every byte to one character),
    so whatever its real encoding, writing it back reproduces it exactly. Never rely on the
    locale default here: on Windows that's cp1252, and it was the cause of a truncated file."""
    if not os.path.isfile(path):
        return ""
    with open(path, "rb") as f:
        return f.read().decode("latin-1")


def _write_user_setup(path, text):
    data = text.encode("latin-1")          # our block is pure ASCII; the rest round-trips
    tmp = path + ".driving_rig.tmp"        # write aside, then swap: never leave it half-written
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def _user_setup_path():
    return os.path.join(cmds.internalVar(userScriptDir=True), "userSetup.py")


def _block(pkg_parent):
    return "\n".join([
        BEGIN,
        "def _driving_rig_startup():",
        "    import sys",
        "    p = %s" % ascii(pkg_parent),   # ascii(): non-ASCII path chars become escapes
        "    if p not in sys.path:",
        "        sys.path.append(p)",
        "    try:",
        "        import driving_rig.menu",
        "        driving_rig.menu.create_menu()",
        "    except Exception as e:",
        "        print('driving_rig: menu failed: %s' % e)",
        "import maya.utils",
        "maya.utils.executeDeferred(_driving_rig_startup)",
        END, ""])


def _strip_block(text):
    if BEGIN not in text:
        return text
    a = text.index(BEGIN)
    b = text.index(END, a) + len(END)
    return (text[:a] + text[b:]).strip("\n") + ("\n" if text[:a].strip() or text[b:].strip() else "")


def install(pkg_parent):
    """pkg_parent = the folder that contains the driving_rig package (.../driving_rig/maya)."""
    us = _user_setup_path()
    block = _block(pkg_parent)
    assert block.isascii()
    new = _strip_block(_read_user_setup(us))
    new = new + ("\n" if new and not new.endswith("\n") else "") + block
    os.makedirs(os.path.dirname(us), exist_ok=True)
    _write_user_setup(us, new)
    create_menu()
    create_shelf()
    return us


def uninstall():
    us = _user_setup_path()
    if os.path.isfile(us):
        _write_user_setup(us, _strip_block(_read_user_setup(us)))
    if not cmds.about(batch=True):
        if cmds.menu(MENU, exists=True):
            cmds.deleteUI(MENU)
        if cmds.shelfLayout(SHELF, exists=True):
            cmds.deleteUI(SHELF, layout=True)
        shelf_file = os.path.join(cmds.internalVar(userShelfDir=True), "shelf_%s.mel" % SHELF)
        if os.path.isfile(shelf_file):
            os.remove(shelf_file)
    return us


def _confirm_uninstall():
    if cmds.confirmDialog(title="Driving Rig", button=["Uninstall", "Cancel"], cancelButton="Cancel",
                          message="Remove the Driving Rig menu, shelf and startup block?\n"
                                  "(Rigs already in scenes are not touched.)") == "Uninstall":
        us = uninstall()
        cmds.confirmDialog(title="Driving Rig", button=["OK"],
                           message="Uninstalled. Startup block removed from:\n%s" % us)
