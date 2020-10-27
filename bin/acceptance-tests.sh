#!/usr/bin/env bash
set -euo pipefail

NUM_CPUS=$(grep -c ^processor /proc/cpuinfo)
# Number of CPUs + 1 to have a hot spare.
NUM_BROWSER_NODES=$(( NUM_CPUS + 1 ))

if [ -z "${BASE_URL:-}" ];
then
    echo "No BASE_URL set, exiting"
    exit 0;
fi

if [ "${DRIVER}" = "Remote" ]; then
    docker-compose \
        -p "selenium-hub-${CI_JOB_ID}" \
        up -d selenium-hub

    docker-compose \
        -p "selenium-hub-${CI_JOB_ID}" \
        up -d --scale ${BROWSER_NAME}=${NUM_BROWSER_NODES} ${BROWSER_NAME}

    SELENIUM_HOST="grid"
    SELENIUM_PORT=4444
    DOCKER_LINKS=(--link selenium-hub-${CI_JOB_ID}_selenium-hub_1:grid --net selenium-hub-${CI_JOB_ID}_default)


    echo -n "Waiting for Selenium Grid to get ready..."
    IP=$(docker inspect selenium-hub-${CI_JOB_ID}_selenium-hub_1 | jq -r .[0].NetworkSettings.Networks[].IPAddress)
    set +e
    SELENIUM_READY=$((curl -fs  http://${IP}:4444/wd/hub/status  | jq -es 'if . == [] then null else .[] | .value.ready end' > /dev/null) || echo "false")
    while ! ${SELENIUM_READY}; do
        echo -n "."
        SELENIUM_READY=$((curl -fs  http://${IP}:4444/wd/hub/status  | jq -es 'if . == [] then null else .[] | .value.ready end' > /dev/null) || echo "false")
        sleep 1s;
    done
    set -e
    echo " done"
fi

docker pull ${TEST_IMAGE:=mozmeao/bedrock_test}
docker run \
    --name "bedrock-${CI_JOB_ID}" \
    ${DOCKER_LINKS[@]} \
    -e "DRIVER=${DRIVER}" \
    -e "BROWSERSTACK_USERNAME=${BROWSERSTACK_USERNAME}" \
    -e "BROWSERSTACK_ACCESS_KEY=${BROWSERSTACK_ACCESS_KEY}" \
    -e "SELENIUM_HOST=${SELENIUM_HOST:-}" \
    -e "SELENIUM_PORT=${SELENIUM_PORT:-}" \
    -e "BROWSER_NAME=${BROWSER_NAME:-}" \
    -e "BROWSER=${BROWSER:-}" \
    -e "BROWSER_VERSION=${BROWSER_VERSION:-}" \
    -e "PLATFORM=${PLATFORM:-}" \
    -e "OS=${OS:-}" \
    -e "OS_VERSION=${OS_VERSION:-}" \
    -e "MARK_EXPRESSION=${MARK_EXPRESSION:-}" \
    -e "BASE_URL=${BASE_URL:-}" \
    -e "PYTEST_PROCESSES=${PYTEST_PROCESSES:=4}" \
    -e "SCREEN_WIDTH=1600" \
    -e "SCREEN_HEIGHT=1200" \
    ${TEST_IMAGE} bin/run-integration-tests.sh
