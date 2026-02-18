#!/bin/bash
set -e

echo "Starting Flint Studio..."

if [ -f "./flint_studio" ]; then
  chmod +x ./flint_studio
  ./flint_studio
elif [ -f "./flint_studio.exe" ]; then
  ./flint_studio.exe
else
  echo "Binary not found (flint_studio / flint_studio.exe)."
  exit 1
fi
