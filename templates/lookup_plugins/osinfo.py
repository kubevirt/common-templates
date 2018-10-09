from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import subprocess

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase

import gi
gi.require_version('Libosinfo', '1.0')
from gi.repository import Libosinfo as osinfo

loader = osinfo.Loader()
#loader.process_default_path()
loader.process_path("../osinfo-db/data")
db = loader.get_db()

class OsInfoGObjectProxy(object):
    def __str__(self):
        return "<%s @ %s obj=%s>" % (self.__class__.__name__, self._root_path, str(self._obj))

    def __init__(self, obj, root_path=""):
        self._obj = obj
        self._root_path = root_path

    def __bool__(self):
        return bool(self._obj)

    def __contains__(self, key):
        if hasattr(self._obj, "get_" + str(key)):
            return True
        elif hasattr(self._obj, "get_length") and hasattr(self._obj, "get_nth"):
            if type(key) == int or type(key) == long:
                return self._obj.get_length() > int(key)
            elif type(key) == str or type(key) == unicode:
                conditions = [v.split("=", 1) for v in key.split(",")]
                conditions = {v[0] : v[1] for v in conditions}
                matches = 0
                for idx in range(self._obj.get_length()):
                    obj = self.__class__(self._obj.get_nth(idx),
                            self._root_path + "." + str(idx))
                    if all([obj[k] == v for k,v in conditions.items()]):
                        matches += 1
                return matches > 0
        else:
            return False

    def _resolve(self, val, path):
        if (type(val) == int or type(val) == long or type(val) == float or
                type(val) == str or type(val) == unicode or type(val) == bool):
            return val
        else:
            return self.__class__(val, root_path = path)

    def _get(self, root, root_path, idx):
        if hasattr(root, "get_" + str(idx)):
            return getattr(root, "get_" + str(idx))()
        elif hasattr(root, "get_length") and hasattr(root, "get_nth"):
            if root.get_length() <= int(idx):
                raise IndexError("%s[%s]" % (self._obj, root_path + "." + idx))
            else:
                return root.get_nth(int(idx))
        else:
            raise AttributeError("%s[%s]" % (self._obj, root_path + "." + idx))

    def __getattr__(self, name):
        root = self._obj
        root = self._get(root, self._root_path + "." + name, name)
        return self._resolve(root, self._root_path + "." + name)

    def __getitem__(self, idx):
        if type(idx) == int or type(idx) == long:
            idx = str(idx)
        root = self._obj
        root_path = [self._root_path]
        for i in idx.split("."):
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
                ret.append({"name": term})

        return ret

# vim: sw=4 sts=4 et
