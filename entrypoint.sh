#!/bin/bash -e

if test -z "$1"; then
    exec /bin/bash
fi

exec "$@"
