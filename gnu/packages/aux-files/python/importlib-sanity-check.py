# GNU Guix --- Functional package management for GNU
# Copyright © 2025 Nicolas Graves <ngraves@ngraves.fr>
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

import importlib
import os
import sys
import traceback
from importlib import metadata
from importlib.machinery import PathFinder

def find_distributions_in_path(path):
    """
    Find all distributions and top-level modules in the given path.

    This function assumes path is already in `sys.path`.
    Return a list of tuples (distribution, top-level modules).

    This is an 'inefficient' fallback to a seemingly simple issue, but there
    doesn't seem to be a robust way to get modules from
    `metadata.distributions` (see PEP794 https://peps.python.org/pep-0794).

    An alternative could be to iterate on all `metadata.distributions(path)`
    metadata, checking for PEP794 Import-Name or an equivalent guess
    (gives the module name to get with importlib), and only fallback on this
    more costly approach if this first try fails.
    Is it worth the additional complexity though, given the fallback would
    still be necessary?
    """
    module_to_dists = metadata.packages_distributions()

    def dist_with_modules(dist):
        return (dist, [
            module for module, dists in module_to_dists.items()
            if dist.name in dists
        ])

    return list(map(dist_with_modules, metadata.distributions(path=[path])))


# https://packaging.python.org/en/latest/specifications/core-metadata/#requires-dist-multiple-use
def check_requirements(requires):
    """Check if distribution requirements are satisfied."""
    if not requires:
        print("No requirements to verify.")
        return True
    else:
        print(f"Found requirements {requires} to check.")
        # This is a way to avoid injecting python-packaging everywhere,
        # especially for bootstrap packages.  It only runs if the distribution
        # actually has requirements to check.
        try:
            from packaging.requirements import Requirement
        except ImportError:
            print(
                "The 'python-packaging' package is required but not available.\n"
                "Please add it in your profile or native-inputs of the package."
            )
            return False

        print("...checking requirements: ", end="")
        return all(map(check_requirement, map(Requirement, requires)))


def check_requirement(req):
    """Check if a single requirement is correct."""
    from packaging.version import Version
    # Skip conditional dependencies
    # TODO Implement conditional dependencies checking.
    # Note: setuptools uses the extra == "core" flag.
    if req.marker:
        print(
            f"Skipping '{req.name}' package to avoid checking "
            "conditional dependencies."
        )
        return True
    try:
        # Get the installed package
        installed_dist = metadata.distribution(req.name)
        installed_version = Version(installed_dist.version)

        # Check if version satisfies the requirement
        if not req.specifier.contains(installed_version):
            print(
                f"ERROR: Package '{req.name}' version {installed_version} "
                f"does not satisfy {req.specifier}"
            )
            return False
        print("OK")
        return True
    except metadata.PackageNotFoundError:
        print(f"ERROR: Required package '{req.name}' not found")
        return False


def try_load_module(module_name):
    """Attempt to load a module, returns True if successful"""
    if PathFinder.find_spec(module_name) is None:
        # Ignore unavailable modules, often C modules, which were not
        # installed at the top-level. Cannot use ModuleNotFoundError,
        # because it is raised by failed imports too.
        print(f"...skipping unavailable module {module_name}")
        return True

    try:
        print(f"...trying to load module {module_name}: ", end="")
        importlib.import_module(module_name)
        print("OK")
        return True
    except Exception:
        print("ERROR: ")
        traceback.print_exc(file=sys.stdout)
        return False


def try_load_script_endpoint(ep):
    """Attempt to load a script endpoint, returns True if successful"""
    try:
        print(f"...trying to load endpoint {ep.group} {ep.name}: ", end="")
        ep.load()
        print("OK")
        return True
    except Exception:
        print("ERROR:")
        traceback.print_exc(file=sys.stdout)
        return False


def find_top_level_modules(modules):
    """Check the presence of at least a top-level module."""
    if modules is None:
        print("ERROR: cannot determine top-level modules")
        return False
    return True


def check_distribution(pair):
    """
    Validate the current distribution.

    The distribution is a pair of (distribution, list of top level modules).
    """
    dist, top_level_modules = pair
    print(f"validating {dist.name}")
    status = all((
        check_requirements(dist.requires),
        find_top_level_modules(top_level_modules),
        all(map(try_load_module, top_level_modules)),
        all(try_load_script_endpoint(ep) for ep in dist.entry_points
            if ep.group in ("console_scripts", "gui_scripts"))
    ))
    print(f"{'PASSED' if status else 'FAILED'}: {dist.name}\n")
    return status


def main():
    if len(sys.argv) != 2:
        print(f"Usage: python {__file__} <site-packages-path>")
        sys.exit(1)

    path = sys.argv[1]

    if os.path.exists(path):
        # Add the path to sys.path if not already there
        if path not in sys.path:
            sys.path.insert(0, path)

        distributions = find_distributions_in_path(path)
        if distributions:
            print(f"Found distributions in {path}.")
        else:
            print(f"ERROR: No distributions found in {path}")
            print("Make sure the path contains .dist-info or .egg-info directories.")
            sys.exit(1)
        sys.exit(not all(map(check_distribution, distributions)))
    else:
        print("ERROR: No site-packages found for this package!")
        sys.exit(1)


if __name__ == '__main__':
    main()
