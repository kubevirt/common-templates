from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import subprocess

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase

class LookupModule(LookupBase):
    def run(self, terms, variables, **kwargs):
        ret = []
        for term in terms:
            ret.append({
                "shortid": term,
            })
        return ret

