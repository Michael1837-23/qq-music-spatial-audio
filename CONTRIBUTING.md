# Contributing

Issues and pull requests are welcome.

## Before opening a pull request

- Keep changes focused and explain the user-visible effect.
- Add or update tests for logic changes.
- Do not commit build products, signing credentials, Xcode user data, or captured audio.
- Preserve the rule that QQ Music is unmuted on every stop and failure path.
- For audio-routing changes, describe any real-device testing you performed.

Run the test suite:

```sh
xcodebuild \
  -project SpatialRelay.xcodeproj \
  -scheme SpatialRelay \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Run static analysis:

```sh
xcodebuild \
  -project SpatialRelay.xcodeproj \
  -scheme SpatialRelay \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  analyze
```

By contributing, you agree that your contribution is licensed under the repository's MIT License.
