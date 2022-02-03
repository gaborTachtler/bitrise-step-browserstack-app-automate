#!/bin/bash
set -e

printf "\n---Uploading app apk to browserstack---\n"
# shellcheck disable=SC2154
upload_app_response="$(curl -u "$username:$access_key" -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/app" -F "file=@$app_apk_path")"
app_url=$(echo "$upload_app_response" | jq .app_url)
echo "---App uploading done---"

printf "\n---Uploading test apk to browserstack---\n"
# shellcheck disable=SC2154
upload_test_response="$(curl -u "$username:$access_key" -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/test-suite" -F "file=@$test_apk_path")"
test_url=$(echo "$upload_test_response" | jq .test_suite_url)
echo "---Test uploading done---"

printf "\n---Starting automated tests---\n"
# shellcheck disable=SC2154
json=$(jq -n \
  --argjson app_url "$app_url" \
  --argjson test_url "$test_url" \
  --argjson devices ["$bs_device_list"] \
  --argjson class ["$bs_class"] \
  --argjson package ["$bs_package"] \
  --argjson annotation ["$bs_annotation"] \
  --arg size "$bs_size" \
  --arg logs "$bs_logs" \
  --arg video "$bs_video" \
  --arg screenshot "$bs_screenshot" \
  --arg loc "$bs_local" \
  --arg locId "$bs_local_identifier" \
  --arg gpsLocation "$bs_gps_location" \
  --arg language "$bs_language" \
  --arg locale "$bs_locale" \
  '{app: $app_url, testSuite: $test_url, devices: $devices, class: $class, package: $package, annotation: $annotation, size: $size, deviceLogs: $logs, networkLogs: $logs, video: $video, enableSpoonFramework: $screenshot, local: $loc, localIdentifier: $locId, gpsLocation: $gpsLocation, language: $language, locale: $locale}')

run_test_response="$(curl -s -u "$username:$access_key" -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/build" -d "$json" -H "Content-Type: application/json")"
build_id=$(echo "$run_test_response" | jq .build_id | sed 's/"//g')

getBuildStatus() {
  curl -s -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .status | sed 's/"//g'
}

getSessionStatus() {
  curl -s -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .devices[].sessions[].status | sed 's/"//g'
}

while [[ "$(getSessionStatus)" != "running" ]]; do
  echo "Waiting for session ID..."
  sleep 5s
done

session_id="$(curl -s -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id" | jq .devices[].sessions[].id | sed 's/"//g')"

echo "Build id: $build_id"
echo "Session id: $session_id"
envman add --key BROWSERSTACK_BUILD_ID --value "$build_id"
envman add --key BROWSERSTACK_SESSION_ID --value "$session_id"

getSessionResponse() {
  curl -s -u "$username:$access_key" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id/sessions/$session_id"
}

getNumberOfTests() {
  (getSessionResponse) | jq .testcases.count
}

getTestStatus() {
  (getSessionResponse) | jq .testcases.status."$1" | sed 's/"//g'
}

getTestCaseData() {
  (getSessionResponse) | jq .testcases.data[].testcases[$1]
}

saveLogs() {
  local test_case_data=$*
  local test_name=$(echo "$test_case_data" | jq .name | sed 's/"//g')
  curl -s -u "$username:$access_key" -o "${BITRISE_DEPLOY_DIR}/${test_name}_instrumentation.log" "$(echo "$test_case_data" | jq .instrumentation_log | sed 's/"//g')"
  curl -s -u "$username:$access_key" -o "${BITRISE_DEPLOY_DIR}/${test_name}_device.log" "$(echo "$test_case_data" | jq .device_log | sed 's/"//g')"
  curl -s -u "$username:$access_key" -o "${BITRISE_DEPLOY_DIR}/${test_name}_network.log" "$(echo "$test_case_data" | jq .network_log | sed 's/"//g')"
}

printf "\n---Monitor build state---\n"
echo "Number of tests: $test_all"

while [[ "$(getBuildStatus)" == "running" || $(getBuildStatus) == 0 ]]; do
  echo "Automation is running..."
  sleep 30s
done

test_all=$(getNumberOfTests)

printf "\n---Print states and save logs---\n"
echo "Number of tests: $test_all"
for ((i = 0; i < test_all; i++)); do
  test_case_data=$(getTestCaseData "$i")
  test_status=$(echo "$test_case_data" | jq .status | sed 's/"//g')

  while [[ $test_status == "queued" || $test_status == "running" ]]; do
    sleep 5s
    test_case_data=$(getTestCaseData "$i")
    test_status=$(echo "$test_case_data" | jq .status | sed 's/"//g')
  done

  test_name=$(echo "$test_case_data" | jq .name | sed 's/"//g')
  test_duration=$(echo "$test_case_data" | jq .duration | sed 's/"//g')
  padding="..............................................."

  if [[ $test_duration != null ]]; then
    saveLogs "$(getTestCaseData "$i")"
    printf "%s%s %s\n" "${i+1}. ${test_name}" "${padding:${#test_name}}" "$test_status! ($test_duration s)"
  else
    printf "%s%s %s\n" "${i+1}. ${test_name}" "${padding:${#test_name}}" "$test_status!"
  fi
done

printf "\n---Automation %s!---\n" "$(getBuildStatus)"

echo "---Save report---"
curl -s -u "$username:$access_key" -o "$BITRISE_DEPLOY_DIR/report.xml" -X GET "https://api-cloud.browserstack.com/app-automate/espresso/v2/builds/$build_id/sessions/$session_id/report"

echo "---Save video---"
curl -s -o "$BITRISE_DEPLOY_DIR/video.mp4" "https://www.browserstack.com/s3-upload/bs-video-logs-use/s3/$session_id/video-$session_id.mp4"

echo "---Save env vars---"
test_failed=$( (getSessionResponse) | jq .testcases.status.failed)
echo "Test all: $test_all"
echo "Test failed: $test_failed"
envman add --key BS_TEST_ALL --value "$test_all"
envman add --key BS_TEST_FAILED --value "$test_failed"
envman add --key BS_VIDEO_URL --value "$BITRISE_DEPLOY_DIR/video.mp4"
envman add --key BS_EXECUTION_URL --value "https://app-automate.browserstack.com/dashboard/v2/builds/$build_id"
