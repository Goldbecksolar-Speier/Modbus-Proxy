#!/bin/sh
REG=\
VALUE=\

echo "Content-Type: text/plain"
echo ""
if [ -z "\" ]; then
  echo NOT_FOUND
else
  echo "\"
fi
