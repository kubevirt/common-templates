#!/usr/bin/env python

import logging
import os
import os.path
import yaml
import sys

from kubernetes import config
from openshift.dynamic import DynamicClient


def validatePVCNames(path, liveTemplates):
    templates = [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))]
    errors = []
    for templateFilename in templates:
        with open(os.path.join(path, templateFilename), 'r') as stream:
            template = yaml.safe_load(stream)

            if template is None:
                errors.append("Empty template file: {}".format(templateFilename))
                continue

            templateName = template["metadata"]["name"]
            logging.info("Checking PVC name stability for: {}".format(templateName))

            ds_name = getDataSourceOrPvcNameFrom(template)
            ds_namespace = getDataSourceOrPvcNamespaceFrom(template)

            matchingLiveTemplate = liveTemplates.get(templateName)
            if matchingLiveTemplate is None:
                logging.info("Missing liveTemplate for {}".format(templateName))
                continue

            live_template_ds_name = getDataSourceOrPvcNameFrom(matchingLiveTemplate)
            live_template_ds_namespace = getDataSourceOrPvcNamespaceFrom(matchingLiveTemplate)

            if ds_name != live_template_ds_name:
                errors.append("PVC name: {} was modified in: {}".format(ds_name, templateName))
            if ds_namespace != live_template_ds_namespace:
                errors.append("PVC namespace: {} was modified in: {}".format(ds_namespace, templateName))

    if errors:
        error_message = "\n".join(errors)
        logging.info("PVC stability vaidation failed")
        raise Exception(error_message)


def getParamFrom(template, paramName):
    for param in template["parameters"]:
        if param["name"] == paramName:
            return param["value"]
    return None


def getDataSourceOrPvcNameFrom(template):
    ds_name = getParamFrom(template, "DATA_SOURCE_NAME")
    if ds_name is None:
        return getParamFrom(template, "SRC_PVC_NAME")

    return ds_name


def getDataSourceOrPvcNamespaceFrom(template):
    ds_namespace = getParamFrom(template, "DATA_SOURCE_NAMESPACE")
    if ds_namespace is None:
        return getParamFrom(template, "SRC_PVC_NAMESPACE")

    return ds_namespace


def fetchLiveTemplates():
    k8s_client = config.new_client_from_config()
    dyn_client = DynamicClient(k8s_client)

    template_v1 = dyn_client.resources.get(api_version='template.openshift.io/v1', kind='Template')
    templates = template_v1.get()

    if not templates:
        return {}

    liveTemplates = {}
    for template in templates.items:
        liveTemplates[template["metadata"]["name"]] = template

    return liveTemplates


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    logging.info("Running PVC name stability validation")

    try:
        liveTemplates = fetchLiveTemplates()
        validatePVCNames("dist/templates", liveTemplates)
    except Exception as e:
        logging.error(e)
        sys.exit(1)
