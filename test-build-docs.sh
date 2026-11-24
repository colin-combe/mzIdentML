#!/bin/bash
# Build the specification PDF/DOCX of this checkout into build/spec/.
./build-spec-docs.sh -o "$PWD/build/spec" \
  -c "$(git rev-parse --short HEAD)" \
  -d "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" \
  mzidentml crosslinking_ext
