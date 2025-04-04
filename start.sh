#!/bin/sh
ruby /app/update.rb &
crond -f -d 8
