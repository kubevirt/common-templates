#! python

import logging
import os
import os.path
import yaml
import sys
import json
import importlib.util

sys.path.insert(1, 'lookup_plugins/')
import osinfo

def minMemoryReqForOs(os_label):
    latest_os_info = osinfo.LookupModule().run([os_label],[])[0]
    return latest_os_info["minimum_resources.architecture=x86_64|all.ram"]

def newestOsLabel(template):
    labels = template["metadata"]["labels"]
    osl_pref_str = "os.template.kubevirt.io"
    os_labels = [label for label in labels if osl_pref_str in label]
    return max(os_labels).split('/')[-1]

def minMemoryReqInTemplate(template):
    object = template["objects"][0]
    min_str = object["spec"]["template"]["spec"]["domain"]["resources"]["requests"]["memory"]
    min_gi_float = float(min_str.replace("Gi",""))
    return int(min_gi_float * (1024**3))

def templateHasOsLabels(template):
    labels = template["metadata"]["labels"]
    osl_pref_str = "os.template.kubevirt.io"
    os_labels = [label for label in labels if osl_pref_str in label]

    return len(os_labels) > 0


def memoryReqErrorMessage(newest_os_label, template_name):
    return "Memory requirements for OS: {} are not compatible with the requirements set in: {}".format(newest_os_label, template_name)

FAILED_INFO_MESSAGE = "Minimum memory requirements validation failed"

def checkMemoryReqs(path):
    templates = [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))]
    errors = []
    for template_name in templates:
        with open(os.path.join(path, template_name), 'r') as stream:
            try:
                template = yaml.safe_load(stream)

                if template == None:
                    logging.info("Empty template file: %s", template)
                    continue

                logging.info("Checking memory requirements consistency for: {}".format(template["metadata"]["name"]))
                
                if not templateHasOsLabels(template):
                    logging.info("Template {} has no OS labels (might be a deprecated template), skipping.".format(template["metadata"]["name"]))
                else:
                    try:
                        newest_os_label = newestOsLabel(template)
                        actual_min_req = minMemoryReqForOs(newest_os_label)
                        min_req_in_template = minMemoryReqInTemplate(template)
                        if min_req_in_template < actual_min_req:
                            errors.append([newest_os_label, template_name])
                    except Exception as e:
                        logging.info(FAILED_INFO_MESSAGE)
                        raise e

            except yaml.YAMLError as exc:
                raise exc
    if len(errors) > 0:
        error_messages = [memoryReqErrorMessage(e[0], e[1]) for e in errors]
        error_message = "\n".join(error_messages)
        logging.info(FAILED_INFO_MESSAGE)
        raise Exception(error_message)

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    logging.info("Running minimum memory requirements validation in common templates")

    try:
        checkMemoryReqs("dist/templates")
    except Exception as e:
        logging.error(e)
        sys.exit(1)
