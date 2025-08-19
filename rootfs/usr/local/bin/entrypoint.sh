#!/bin/bash
  if [ -z "${1}" ]; then
    set -- "/usr/lib/plexmediaserver/Plex Media Server"
    eleven log start
    exec "$@" &> /dev/null
  else
    exec "$@"
  fi