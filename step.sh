#!/bin/bash
set -ex
echo "uploading app apk to browserstack"
# shellcheck disable=SC2154
upload_app_response="$(curl -u "$browserstack_username":"$browserstack_access_key" -X POST https://api-cloud.browserstack.com/app-automate/upload -F file=@"$app_apk_path")"
app_url=$(echo "$upload_app_response" | jq .app_url)

echo "uploading test apk to browserstack"
# shellcheck disable=SC2154
upload_test_response="$(curl -u "$browserstack_username":"$browserstack_access_key" -X POST https://api-cloud.browserstack.com/app-automate/espresso/test-suite -F file=@"$test_apk_path")"
test_url=$(echo "$upload_test_response" | jq .test_url)

echo "starting automated tests"
# shellcheck disable=SC2154
json=$( jq -n \
                --argjson app_url "$app_url" \
                --argjson test_url "$test_url" \
                --argjson devices ["$browserstack_device_list"] \
                --argjson class ["$browserstack_class"] \
                --argjson package ["$browserstack_package"] \
                --argjson annotation ["$browserstack_annotation"] \
                --arg size "$browserstack_size" \
                --arg logs "$browserstack_device_logs" \
                --arg video "$browserstack_video" \
                --arg screenshot "$browserstack_screenshot" \
                --arg loc "$browserstack_local" \
                --arg locId "$browserstack_local_identifier" \
                --arg gpsLocation "$browserstack_gps_location" \
                --arg language "$browserstack_language" \
                --arg locale "$browserstack_locale" \
                '{app: $app_url, testSuite: $test_url, devices: $devices, class: $class, package: $package, annotation: $annotation, size: $size, logs: $logs, video: $video, enableSpoonFramework: $screenshot, local: $loc, localIdentifier: $locId, gpsLocation: $gpsLocation, language: $language, locale: $locale}')

run_test_response="$(curl -X POST https://api-cloud.browserstack.com/app-automate/espresso/build -d \ "$json" -H "Content-Type: application/json" -u "$browserstack_username:$browserstack_access_key")"
build_id=$(echo "$run_test_response" | jq .build_id | sed 's/"//g')
envman add --key BROWSERSTACK_BUILD_ID --value "$build_id"

function getBuildStatus() {
    return "$(curl -u "$browserstack_username":"$browserstack_access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .status)"
}

echo "Monitor build state"
echo getBuildStatus

echo "build id: $build_id"
echo "build status: " getBuildStatus

until [ "$(getBuildStatus)" = "running" ];
do
  echo "Automation is running......"
  sleep 30s
  if [ "$(getBuildStatus)" = "passed" ]; then
    echo "Automation Passed!"
  fi
  if [ "$(getBuildStatus)" = "failed" ]; then
    echo "Automation Failed!"
  fi
done