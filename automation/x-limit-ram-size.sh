#!/bin/bash
# Due to travis restrictions, travis job instances have only 7.5 GB of memory.
# This script updates ram size in all large templates 
for filename in dist/templates/*-large.yaml; do
    sed -i -e 's/8G/6G/g' $filename
done