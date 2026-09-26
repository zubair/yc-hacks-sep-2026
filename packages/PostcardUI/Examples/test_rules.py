#!/usr/bin/env python3
"""Run the unchanged form-rule source/tests on macOS without starting a simulator.
This checks UI validation logic against the example model fixture, not the real backend/Core package.
"""
from pathlib import Path
import shutil, subprocess, tempfile
example = Path(__file__).resolve().parent
root = Path(tempfile.mkdtemp(prefix='postcard-form-rules-'))
for directory in ['Sources/PostcardCore', 'Sources/PostcardUI', 'Tests/PostcardUITests']:
    (root / directory).mkdir(parents=True)
shutil.copy2(example / 'ContractFixtures/PostcardCore/Models.swift', root / 'Sources/PostcardCore/Models.swift')
shutil.copy2(example.parent / 'Sources/PostcardUI/PostcardFormRules.swift', root / 'Sources/PostcardUI/PostcardFormRules.swift')
shutil.copy2(example.parent / 'Tests/PostcardUITests/FormRulesTests.swift', root / 'Tests/PostcardUITests/FormRulesTests.swift')
(root / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PostcardFormRuleValidation", targets: [
    .target(name: "PostcardCore"),
    .target(name: "PostcardUI", dependencies: ["PostcardCore"]),
    .testTarget(name: "PostcardUITests", dependencies: ["PostcardUI", "PostcardCore"])
])
''')
print(root, flush=True)
subprocess.run(['swift', 'test', '--package-path', str(root)], check=True)
