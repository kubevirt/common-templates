# This is an Ansible / Jinja2 lookup plugin
# that allows querying the libosinfo database
#
# Example usage:
# {{ lookup('osinfo', 'fedora15')["minimum_resources.architecture=x86_64|all.ram"] }}
# {% if "name=virtio-scsi2" in lookup('osinfo', 'fedora15').all_devices %} 
#
# The code is distributed under the Apache 2 license

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import six
import subprocess

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase

try:
    from builtins import int
except ImportError:
    from __builtin__ import int

import gi
gi.require_version('Libosinfo', '1.0')
from gi.repository import Libosinfo as osinfo

loader = osinfo.Loader()
#loader.process_default_path()
loader.process_path("_out/usr/share/osinfo")
loader.process_path("osinfo-db-override")
db = loader.get_db()

class OsInfoGObjectProxy(object):
    def __str__(self):
        return "<%s @ %s %s=%s>" % (self.__class__.__name__, self._root_path, str(type(self._obj)), str(self._obj))

    def __repr__(self):
        return "<%s @ %s %s=%s>" % (self.__class__.__name__, self._root_path, str(type(self._obj)), str(self._obj))

    def __init__(self, obj, root_path=""):
        self._obj = obj
        self._root_path = root_path

    def __bool__(self):
        return bool(self._obj)

    def _search(self, root, root_path, condition_string):
        """Search libosinfo `root` object (must be a list)
        for an element that matches all the field=value
        conditions. Return the first matching element.
        """
        conditions = [v.split("=", 1) for v in condition_string.split(",")]
        conditions = {v[0] : v[1] for v in conditions}

        root_path = ".".join(root_path.split(".")[:-1])

        matches = []
        # Iterate over all elements of libosinfo list
        for c_idx in range(root.get_length()):
            raw_obj = root.get_nth(c_idx)
            obj = self.__class__(raw_obj,
                    root_path + "." + str(c_idx))
            # Check the conditions
            if all([any([obj[k] == v_part
                         for v_part in v.split("|")])
                    for k,v in conditions.items()]):
                matches.append(raw_obj)

        # Return all matching elements
        return matches

    def __contains__(self, key):
        """Intercept the `key in obj` call and return True when the libosinfo
        object contains an attribute with the name `key`. In case the object
        is an list, `key` represents an index or search terms for that list.
        """
        # Check if self._obj libosinfo object contains attribute `key`
        # by checking for the presence of its getter
        if hasattr(self._obj, "get_" + str(key)):
            return True

        # Check if self._obj is a list
        elif hasattr(self._obj, "get_length") and hasattr(self._obj, "get_nth"):
            # Check if the list has the n-th element in case
            # the `key` is a number
            if isinstance(key, six.integer_types):
                return self._obj.get_length() > int(key)
            # Search the list on case the `key` is a string
            elif isinstance(key, six.string_types):
                matches = self._search(self._obj, self._root_path, key)
                return len(matches) > 0

        # Nothing found
        else:
            return False

    def _resolve(self, val, path):
        """Check if `val` is a scalar value (integer, string, bool, ...)
        and return it if it is. Otherwise wrap the value to allow
        for futher traversal.
        """
        if (isinstance(val, six.integer_types) or
                type(val) == float or type(val) == bool or
                isinstance(val, six.string_types) or
                val is None):
            return val
        else:
            return self.__class__(val, root_path = path)

    def _get(self, root, root_path, idx):
        """Retrieve a value from the libosinfo `root` object using
        a single element search path `idx` (no dots allowed!).
        """
        # Check if self._obj libosinfo object contains attribute `key`
        # by checking for the presence of its getter
        if hasattr(root, "get_" + str(idx)):
            return getattr(root, "get_" + str(idx))()
        # Check if self._obj is a list
        elif hasattr(root, "get_length") and hasattr(root, "get_nth"):
            # Search syntax used, traverse the list and search for first
            # matching element
            if "=" in idx:
                matches = self._search(root, root_path, idx)
                if matches:
                    return matches[0]
                raise AttributeError("%s[%s][%s]" % (self._obj, root_path, idx))
            # Raise an error when accessing nonexistent list element
            elif root.get_length() <= int(idx):
                raise IndexError("%s[%s]" % (self._obj, root_path))
            # Return n-th element in case the `key` is a proper number
            else:
                return root.get_nth(int(idx))
        else:
            raise AttributeError("%s[%s]" % (self._obj, root_path))

    def __getattr__(self, name):
        """This method is a primary entrypoint and is called when
        an unknown attribute is accessed.
        Intercept this call and forward it to libosinfo. Use the `name`
        as the path to the value the user is trying to access.
        Due to Python syntax rules name can't contain dots and so
        the code can assume a single element access using _get is ok.
        """
        root = self._obj
        root = self._get(root, self._root_path + "." + name, name)
        return self._resolve(root, self._root_path + "." + name)

    def __getitem__(self, idx):
        """This method is a primary entrypoint and is called when
        a dictionary access is performed.
        Intercept this call and forward it to libosinfo. Use the `idx`
        as the path to the value the user is trying to access.
        Path can be fully specified and contain dots to traverse
        into deep structures.
        """
        # Make sure idx is a string as all the futher processing
        # expects it
        if type(idx) == int:
            idx = str(idx)
        # Save the root of the search to the running reference
        root = self._obj
        root_path = [self._root_path]
        # Split the full path into path elements
        idx_parts = idx.split(".")
        # Traverse to the requested element layer by layer
        for i in idx_parts:
            root_path.append(i)
            root = self._get(root, ".".join(root_path), i)
        return self._resolve(root, ".".join(root_path))

class LookupModule(LookupBase):
    """Ansible lookup module that accesses the libosinfo database
    and searches for a given operating system record.

    The libosinfo OS object is then wrapped into a Python compatible
    wrapper that allows easy access using Python language constructs.
    """
    def run(self, terms, variables, **kwargs):
        ret = []
        for term in terms:
            filter = osinfo.Filter()
            if "=" in term:
                prop, value = term.split("=", 1)
                filter.add_constraint(prop, value)
            else:
                filter.add_constraint(osinfo.PRODUCT_PROP_SHORT_ID, term)
            oses = db.get_os_list().new_filtered(filter)
            if oses.get_length() > 0:
                for idx in range(oses.get_length()):
                    os = OsInfoGObjectProxy(oses.get_nth(idx), root_path = "[" + term + "]")
                    ret.append(os)
            else:
                print("OS {} not found".format(term))
                ret.append({"name": term})

        return ret

# vim: sw=4 sts=4 et
