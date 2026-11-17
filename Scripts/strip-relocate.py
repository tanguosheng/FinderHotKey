#!/usr/bin/env python3
"""Remove the <relocate> hint from a component package's PackageInfo.

pkgbuild adds it for app bundles; Installer then "helpfully" relocates the app
to any existing copy with the same bundle identifier instead of installing to
/Applications, which breaks the LaunchAgent path.
"""
import sys
import xml.etree.ElementTree as ElementTree

path = sys.argv[1]
tree = ElementTree.parse(path)
root = tree.getroot()

removed = False
for child in list(root):
    if child.tag == "relocate":
        root.remove(child)
        removed = True

if removed:
    tree.write(path, encoding="utf-8", xml_declaration=True)
