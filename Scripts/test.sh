#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="${SUPPLIER_COMPARE_SDK:-$(xcrun --show-sdk-path)}"
mkdir -p .build/module-cache Verification
xcrun swiftc -O -parse-as-library -sdk "$SDK_PATH" -module-cache-path .build/module-cache Sources/Model.swift Sources/Engine.swift Sources/Transfer.swift Sources/Demo.swift Tests/Suite.swift -o .build/CoreTests
.build/CoreTests > Verification/tests.json
cat Verification/tests.json
