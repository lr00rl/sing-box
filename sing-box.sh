#!/bin/bash

# Keep the caller's arguments as an array. Assigning "$@" to a plain string
# and expanding it unquoted made the shell re-split on whitespace, so any
# argument containing a space was destroyed: `sb --json user add <line>
# '{"name":"a b",...}'` reached jq truncated at the space and was rejected as
# invalid JSON, which made it impossible to add a user whose name has a space.
args=("$@")
is_sh_ver=v1.24.3-alpha.4

. /etc/sing-box/sh/src/init.sh
