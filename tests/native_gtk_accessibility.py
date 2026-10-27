"""AT-SPI acceptance for the task-owned demo, called with its process id."""
import sys
import time
import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib

TITLE = "Harding — Native GTK Counter"
PID = int(sys.argv[1])


def children(node):
    for index in range(node.get_child_count()):
        child = node.get_child_at_index(index)
        if child is not None:
            yield child


def walk(node):
    yield node
    for child in children(node):
        yield from walk(child)


def pump():
    context = GLib.MainContext.default()
    while context.pending():
        context.iteration(False)


def find_window():
    for application in children(Atspi.get_desktop(0)):
        if application.get_process_id() != PID:
            continue
        for candidate in children(application):
            if candidate.get_name() == TITLE:
                return candidate
    return None


window = None
for attempt in range(80):
    pump()
    window = find_window()
    if window is not None:
        break
    time.sleep(0.1)
assert window is not None, "Owned demo window not found"


def click(name):
    pump()
    matches = [node for node in walk(window)
               if node.get_role_name() == "push button" and node.get_name() == name]
    assert len(matches) == 1, (name, len(matches))
    action = matches[0].get_action_iface()
    assert action is not None and action.do_action(0), name


def check_label(expected):
    labels = []
    for attempt in range(50):
        pump()
        labels = []
        for node in walk(window):
            node.clear_cache()
            if node.get_role_name() == "label":
                labels.append(node.get_name())
        if expected in labels:
            print("Observed label:", expected, flush=True)
            return
        time.sleep(0.1)
    raise AssertionError((expected, labels))


check_label("Count: 0")
click("Increment")
check_label("Count: 1")
click("Increment")
check_label("Count: 2")
click("Test callback error")
click("Increment")
check_label("Count: 3")
click("Reset")
check_label("Count: 0")
click("Close")
print("Accessibility acceptance passed", flush=True)
