"""Drag this file into a Maya viewport to install Driving Rig.

Adds the "Driving Rig" menu and the "DrivingRig" shelf now, and a small marked block in your
userSetup.py so the menu comes back every session. Driving Rig > Uninstall removes it again.
Re-drop after updating the project to reload the code without restarting Maya.
"""
import os
import sys


def onMayaDroppedPythonFile(*_):
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.append(here)
    for name in [m for m in sys.modules if m == "driving_rig" or m.startswith("driving_rig.")]:
        del sys.modules[name]          # pick up updated code without a restart
    from maya import cmds
    import driving_rig
    import driving_rig.menu as menu
    us = menu.install(here)
    cmds.confirmDialog(title="Driving Rig", button=["OK"], message=(
        "Driving Rig %s installed.\n\n- Menu: Driving Rig (main menu bar)\n- Shelf: DrivingRig\n"
        "- Startup block added to:\n  %s\n\nCode location:\n  %s" % (driving_rig.__version__, us, here)))
