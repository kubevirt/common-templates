#!/usr/bin/env bash

OFFENSIVE_WORDS="black[ -]?list|white[ -]?list|master|slave"
ALLOW_LIST=".+[:/=]master[a-zA-Z]*/?"

if git grep -inE "${OFFENSIVE_WORDS}" -- ":!${BASH_SOURCE[0]}" ':!.github/workflows/' | grep -viE "${ALLOW_LIST}"; then
  echo "Validation failed. Found offensive language"
  exit 1
fi
