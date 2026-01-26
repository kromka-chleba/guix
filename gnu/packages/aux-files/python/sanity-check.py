# -*- coding: utf-8 -*-
# GNU Guix --- Functional package management for GNU
# Copyright © 2021, 2022 Lars-Dominik Braun <lars@6xq.net>
#
# This file is part of GNU Guix.
#
# GNU Guix is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or (at
# your option) any later version.
#
# GNU Guix is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

from __future__ import print_function  # Python 2 support.
import importlib
import sys
import traceback
from importlib.metadata import (
    Distribution,
    distribution,
    _top_level_declared,
)
from packaging.requirements import Requirement

try:
    from importlib.machinery import PathFinder
except ImportError:
    PathFinder = None

ret = 0
# this is the site-packages path of the guix python package:
# (string-append #$output "/lib/python" (python-version python) "/site-packages")
distribution_path = sys.argv[1]
dist_to_check = list(Distribution.discover(path=[distribution_path]))[0]

# Only check site-packages installed by this package, but not dependencies
# we need to convert the name to a Requirement object to get rid of
# extras information
ws = [distribution(Requirement(name).name) for name in dist_to_check.requires]

for dist in ws:
    print("validating", dist.name, dist._path)
    try:
        print("...checking requirements: ", end="")
        # we have to import the distribution to check if it works
        importlib.import_module(dist.name)
        print("OK")
    except Exception as e:
        print(
            f'ERROR: could not import distribution "{dist.name}"'
            f'failed with exception "{e}"'
        )
        ret = 1
        continue

    # Try to load top level modules. This should not have any side-effects.
    try:
        top_level_module_names = _top_level_declared(dist)
    except (KeyError, EnvironmentError):
        # distutils (i.e. #:use-setuptools? #f) will not install any metadata.
        # This file is also missing for packages built using a PEP 517 builder
        # such as poetry.
        print("WARNING: cannot determine top-level modules")
        continue
    for name in top_level_module_names:
        # Only available on Python 3.
        if PathFinder and PathFinder.find_spec(name) is None:
            # Ignore unavailable modules, often C modules, which were not
            # installed at the top-level. Cannot use ModuleNotFoundError,
            # because it is raised by failed imports too.
            continue
        try:
            print("...trying to load module", name, end=": ")
            importlib.import_module(name)
            print("OK")
        except Exception:
            print("ERROR:")
            traceback.print_exc(file=sys.stdout)
            ret = 1

    # Try to load entry points of console scripts too, making sure they
    # work. They should be removed if they don't. Other groups may not be
    # safe, as they can depend on optional packages.
    for entry_point in dist.entry_points:
        if entry_point.group not in {"console_scripts", "gui_scripts"}:
            continue
        try:
            print(
                "...trying to load endpoint",
                entry_point.group,
                entry_point.name,
                end=": ",
            )
            entry_point.load()
            print("OK")
        except Exception:
            print("ERROR:")
            traceback.print_exc(file=sys.stdout)
            ret = 1

sys.exit(ret)
