#!/bin/zsh
# Settings, sharing and store of "Corregir monitor", without the screens.
set -euo pipefail
cd "${0:A:h:h:h}"
mkdir -p build/CorrectionTest
{
  echo 'import Foundation; import CoreGraphics; struct AireError: Error { init(_ s: String) {} }'
  echo 'enum CorrectionDisplays { static func setMode(_ id: CGDirectDisplayID, width: Int, height: Int) {} }'
  echo 'enum ModeKeeper { static var isStable = true; static func restore() {} }'
  sed -n '/^struct CorrectionSettings/,/^}/p;/^enum CorrectionStore/,/^}/p;/^struct CorrectionShare/,/^}/p' Sources/Corrector.swift
} > build/CorrectionTest/Settings.swift
xcrun swiftc -module-cache-path build/ModuleCache -O build/CorrectionTest/Settings.swift Tests/Correction/main.swift -o build/CorrectionTest/run
build/CorrectionTest/run
