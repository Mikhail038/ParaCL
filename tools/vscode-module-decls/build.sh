#!/usr/bin/env sh
# Packs this folder into a .vsix that VS Code can install:
#   ./build.sh && code --install-extension cpp-module-decls-0.0.1.vsix
set -eu
cd "$(dirname "$0")"
rm -f cpp-module-decls-0.0.1.vsix
zip -q -r cpp-module-decls-0.0.1.vsix '[Content_Types].xml' extension.vsixmanifest extension
echo "built $(pwd)/cpp-module-decls-0.0.1.vsix"
