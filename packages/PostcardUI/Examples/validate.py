#!/usr/bin/env python3
"""Create an isolated Xcode UI validation app; never install fixture modules into production paths."""
from pathlib import Path
import argparse, shutil, subprocess, tempfile
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path)
args = parser.parse_args()
example = Path(__file__).resolve().parent
package = example.parent
root = args.output or Path(tempfile.mkdtemp(prefix='postcard-ui-validation-'))
root.mkdir(parents=True, exist_ok=True)
shutil.copytree(package / 'Sources', root / 'UI', dirs_exist_ok=True)
shutil.copytree(package / 'Tests/PostcardUITests', root / 'UnitTests', dirs_exist_ok=True)
for name in ['ContractFixtures', 'PreviewApp', 'UITests']:
    shutil.copytree(example / name, root / name, dirs_exist_ok=True)
(root / 'project.yml').write_text('''name: PostcardUIValidation
options:
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    SUPPORTS_MACCATALYST: YES
    GENERATE_INFOPLIST_FILE: YES
    CODE_SIGNING_ALLOWED: NO
    DEVELOPMENT_TEAM: ""
targets:
  PostcardCore:
    type: framework
    platform: iOS
    sources: [ContractFixtures/PostcardCore]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.postcard.validation.core
  PostcardMotion:
    type: framework
    platform: iOS
    sources: [ContractFixtures/PostcardMotion]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.postcard.validation.motion
  PostcardUI:
    type: framework
    platform: iOS
    sources: [UI]
    dependencies:
      - target: PostcardCore
      - target: PostcardMotion
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.postcard.validation.ui
  PostcardUIValidation:
    type: application
    platform: iOS
    sources: [PreviewApp]
    dependencies:
      - target: PostcardUI
      - target: PostcardCore
      - target: PostcardMotion
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.postcard.validation
      INFOPLIST_KEY_UILaunchScreen_Generation: YES
      INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
      INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
      TARGETED_DEVICE_FAMILY: "1,2"
  FormRulesTests:
    type: bundle.unit-test
    platform: iOS
    sources: [UnitTests]
    dependencies:
      - target: PostcardUI
      - target: PostcardCore
      - target: PostcardMotion
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.postcard.validation.unit-tests
  InteractionTests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: PostcardUIValidation
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.postcard.validation.ui-tests
schemes:
  PostcardUIValidation:
    build:
      targets:
        PostcardUIValidation: all
    test:
      targets:
        - FormRulesTests
        - InteractionTests
''')
subprocess.run(['xcodegen', 'generate'], cwd=root, check=True)
print(root)
