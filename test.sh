#!/bin/bash

# -e is important to let make use the vars defined in "matrix:" above
make -e $TARGET
