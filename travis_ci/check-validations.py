#! python

import logging
import os
import os.path
import yaml
import sys
import json

def checkValidations(path):
    templates = [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))]
    for template in templates:
        with open(path + "/" + template, 'r') as stream:
            try:
                template = yaml.safe_load(stream)

                if template == None: 
                    logging.info("Empty template file: %s", template)
                    continue

                logging.info("Checking " + template["metadata"]["name"])

                try:
                    json.loads(template["metadata"]["annotations"]["validations"])
                except Exception as e:
                    logging.info("Validation is not json")
                    raise e

            except yaml.YAMLError as exc:
                raise exc



if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    logging.info("Running syntax check for validations in common templates")
    
    try:
        checkValidations("dist/templates")
    except Exception as e:
        logging.error(e)
        sys.exit(1)

    

