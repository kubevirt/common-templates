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
loader.process_path("osinfo-db/data")
loader.process_path("osinfo-db-override")
db = loader.get_db()

class OsInfoGObjectProxy(object):
    def __str__(self):
        return "<%s @ %s obj=%s>" % (self.__class__.__name__, self._root_path, str(self._obj))

    def __init__(self, obj, root_path=""):
        self._obj = obj
        self._root_path = root_path

    def __bool__(self):
        return bool(self._obj)

    def _search(self, root, root_path, condition_string):
        conditions = [v.split("=", 1) for v in condition_string.split(",")]
        conditions = {v[0] : v[1] for v in conditions}

        root_path = ".".join(root_path.split(".")[:-1])

        matches = []
        for c_idx in range(root.get_length()):
            raw_obj = root.get_nth(c_idx)
            obj = self.__class__(raw_obj,
                    root_path + "." + str(c_idx))
            if all([any([obj[k] == v_part
                         for v_part in v.split("|")])
                    for k,v in conditions.items()]):
                matches.append(raw_obj)

        return matches

    def __contains__(self, key):
        if hasattr(self._obj, "get_" + str(key)):
            return True
        elif hasattr(self._obj, "get_length") and hasattr(self._obj, "get_nth"):
            if isinstance(key, six.integer_types):
                return self._obj.get_length() > int(key)
            elif isinstance(key, six.string_types):
                matches = self._search(self._obj, self._root_path, key)
                return len(matches) > 0
        else:
            return False

    def _resolve(self, val, path):
        if (isinstance(val, six.integer_types) or
                type(val) == float or type(val) == bool or
                isinstance(val, six.string_types)):
            return val
        else:
            return self.__class__(val, root_path = path)

    def _get(self, root, root_path, idx):
        if hasattr(root, "get_" + str(idx)):
            return getattr(root, "get_" + str(idx))()
        elif hasattr(root, "get_length") and hasattr(root, "get_nth"):
            if "=" in idx:
                matches = self._search(root, root_path, idx)
                if matches:
                    return matches[0]
                raise AttributeError("%s[%s][%s]" % (self._obj, root_path, idx))
            elif root.get_length() <= int(idx):
                raise IndexError("%s[%s]" % (self._obj, root_path))
            else:
                return root.get_nth(int(idx))
        else:
            raise AttributeError("%s[%s]" % (self._obj, root_path))

    def __getattr__(self, name):
        root = self._obj
        root = self._get(root, self._root_path + "." + name, name)
        return self._resolve(root, self._root_path + "." + name)

    def __getitem__(self, idx):
        if type(idx) == int:
            idx = str(idx)
        root = self._obj
        root_path = [self._root_path]
        idx_parts = idx.split(".")
        for i in idx_parts:
            root_path.append(i)
            root = self._get(root, ".".join(root_path), i)
        return self._resolve(root, ".".join(root_path))

class LookupModule(LookupBase):
    def run(self, terms, variables, **kwargs):
        ret = []
        for term in terms:
            filter = osinfo.Filter()
            filter.add_constraint(osinfo.PRODUCT_PROP_SHORT_ID, term)
            oses = db.get_os_list().new_filtered(filter)
            if oses.get_length() > 0:
                os = OsInfoGObjectProxy(oses.get_nth(0), root_path = "[" + term + "]")
                ret.append(os)
            else:
                print("OS {} not found".format(term))
                ret.append({"name": term})

        return ret

# vim: sw=4 sts=4 et
