# Local checks for airo_on_device_llm. Run `just` to see recipes.
# Replaces the GitHub Actions workflow, which this org cannot run.

default:
    @just --list

# Fetch dependencies for the package and the example app.
get:
    flutter pub get
    cd example && flutter pub get

# Static analysis, warnings fail the run.
analyze: get
    flutter analyze --fatal-infos --fatal-warnings

# Unit tests.
test: get
    flutter test

# Everything to run before pushing.
check: analyze test

# Debug APK of the example app, to try the plugin on a device.
example-apk: get
    cd example && flutter build apk --debug
