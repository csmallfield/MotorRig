"""Import dialog. Settings are remembered between sessions (optionVars)."""
from __future__ import annotations

import os
import traceback

from maya import cmds

from . import importer, take_io
from .mayautil import FPS_CHOICES, get_world_scale

WINDOW = "drivingRigImportWin"
OPT = "drivingRig_"


def _opt(name, default):
    key = OPT + name
    return cmds.optionVar(query=key) if cmds.optionVar(exists=key) else default


def _set_opt(name, value):
    key = OPT + name
    if isinstance(value, bool) or isinstance(value, int):
        cmds.optionVar(intValue=(key, int(value)))
    elif isinstance(value, float):
        cmds.optionVar(floatValue=(key, value))
    else:
        cmds.optionVar(stringValue=(key, str(value)))


def _fps_label(f):
    return ("%g" % f)


class ImportDialog(object):
    def __init__(self):
        if cmds.window(WINDOW, exists=True):
            cmds.deleteUI(WINDOW)
        self.win = cmds.window(WINDOW, title="Driving Rig - Import Take", widthHeight=(540, 420),
                               sizeable=True)
        cmds.columnLayout(adjustableColumn=True, rowSpacing=6, columnOffset=("both", 10))
        cmds.separator(style="none", height=6)
        self.file = cmds.textFieldButtonGrp(label="Take", buttonLabel="Browse...", adjustableColumn=2,
                                            columnWidth3=(80, 330, 70), text=_opt("last_file", ""),
                                            buttonCommand=self.browse,
                                            changeCommand=lambda *_: self.describe())
        self.info = cmds.text(label="", align="left", height=46, wordWrap=True)
        self.name = cmds.textFieldGrp(label="Name", adjustableColumn=2, columnWidth2=(80, 330))
        self.fps = cmds.optionMenuGrp(label="Frame rate", columnWidth2=(80, 120))
        for f in FPS_CHOICES:
            cmds.menuItem(label=_fps_label(f))
        cmds.optionMenuGrp(self.fps, edit=True, value=_fps_label(_opt("fps", 24.0)))
        self.in_frame = cmds.intFieldGrp(label="IN frame", value1=int(_opt("in_frame", 1001)),
                                         columnWidth2=(80, 120))
        current = get_world_scale()   # an existing world group wins: never reset it silently
        self.world_scale = cmds.floatFieldGrp(
            label="World scale", precision=4, columnWidth2=(80, 120),
            value1=current if current is not None else float(_opt("world_scale", 0.1)),
            annotation="DrivingRig_world.worldScale - 1.0 = true size in cm, 0.1 = one unit per 10 cm. "
                       "Change it any time in the channel box or Driving Rig > World Scale...")
        cmds.separator(height=8)
        self.cb = {}
        for key, label, default in (("set_fps", "Set scene frame rate", 1),
                                    ("set_range", "Set playback range to the take (with handles)", 1),
                                    ("camera", "Import the take's camera (switches like the take)", 1),
                                    ("all_cameras", "Import every recorded camera (9 angles)", 1),
                                    ("steering_wheel", "Steering wheel", 1),
                                    ("contacts", "Contact locators (grounded / slip - FX triggers)", 1),
                                    ("solve", "Solve wheel spin from travel (else: recorded spin)", 1)):
            self.cb[key] = cmds.checkBox(label=label, value=bool(_opt(key, default)))
        cmds.separator(height=8)
        cmds.rowLayout(numberOfColumns=2, adjustableColumn=1, columnAttach2=("both", "both"))
        cmds.button(label="Import", height=32, command=lambda *_: self.run())
        cmds.button(label="Close", height=32, width=90, command=lambda *_: cmds.deleteUI(WINDOW))
        cmds.setParent("..")
        cmds.showWindow(self.win)
        self.describe()

    def browse(self, *_):
        start = os.path.dirname(cmds.textFieldButtonGrp(self.file, query=True, text=True)) or ""
        kw = {"startingDirectory": start} if start and os.path.isdir(start) else {}
        res = cmds.fileDialog2(fileMode=1, caption="Driving Rig take",
                               fileFilter="Driving Rig takes (*.json.gz *.json);;All files (*.*)", **kw)
        if res:
            cmds.textFieldButtonGrp(self.file, edit=True, text=res[0])
            self.describe()

    def describe(self):
        path = cmds.textFieldButtonGrp(self.file, query=True, text=True)
        if not path or not os.path.isfile(path):
            cmds.text(self.info, edit=True, label="Choose a take exported from the Godot take browser.")
            return
        try:
            t = take_io.load(path)
        except Exception as ex:   # show the reason (v1 guidance, validation errors) inline
            cmds.text(self.info, edit=True, label=str(ex).splitlines()[0][:200])
            return
        s = t.summary
        cmds.text(self.info, edit=True, label="%.2f s | %.0f m | peak %.0f km/h | %.2f g lat | %s" % (
            t.duration, s.get("distance_m", 0), s.get("peak_speed_kmh", 0), s.get("max_lateral_g", 0),
            t.meta.get("collision_source", "")))
        cmds.textFieldGrp(self.name, edit=True, text=importer.take_stem(path))

    def run(self):
        path = cmds.textFieldButtonGrp(self.file, query=True, text=True)
        fps = float(cmds.optionMenuGrp(self.fps, query=True, value=True))
        in_frame = cmds.intFieldGrp(self.in_frame, query=True, value1=True)
        opts = {k: cmds.checkBox(c, query=True, value=True) for k, c in self.cb.items()}
        name = cmds.textFieldGrp(self.name, query=True, text=True).strip() or None
        world_scale = cmds.floatFieldGrp(self.world_scale, query=True, value1=True)
        _set_opt("world_scale", world_scale)
        _set_opt("last_file", path)
        _set_opt("fps", fps)
        _set_opt("in_frame", in_frame)
        for k, v in opts.items():
            _set_opt(k, bool(v))
        try:
            root = importer.import_take(path, fps=fps, in_frame=in_frame, name=name,
                                        world_scale=world_scale, **opts)
        except Exception as ex:
            traceback.print_exc()
            cmds.confirmDialog(title="Driving Rig", message="Import failed:\n\n%s" % ex, button=["OK"])
            return
        cmds.confirmDialog(title="Driving Rig", button=["OK"],
                           message=cmds.getAttr(root + ".drvLastCheck"))


def show():
    return ImportDialog()
