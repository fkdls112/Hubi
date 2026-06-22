fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app (Debug)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Archive and upload to TestFlight

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Upload existing archive to TestFlight

### ios latest_build

```sh
[bundle exec] fastlane ios latest_build
```

Show latest TestFlight build number

### ios sync_profiles

```sh
[bundle exec] fastlane ios sync_profiles
```

Sync provisioning profiles

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
