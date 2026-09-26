#!/usr/bin/env python3
"""Run the unchanged form-rule source/tests with plain `swift test` (macOS or Linux) without a simulator.
The rules are compiled against the real PostcardCore models, not the preview-only contract fixture.
"""
from pathlib import Path
import shutil, subprocess, tempfile
example = Path(__file__).resolve().parent
root = Path(tempfile.mkdtemp(prefix='postcard-form-rules-'))
for directory in ['Sources/PostcardCore', 'Sources/PostcardUI', 'Tests/PostcardUITests']:
    (root / directory).mkdir(parents=True)
shutil.copy2(example.parent.parent / 'PostcardCore/Sources/PostcardCore/Models.swift', root / 'Sources/PostcardCore/Models.swift')
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
