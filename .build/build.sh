#!/usr/bin/env bash

set -x
NAME=$(echo $ghprbGhRepository | awk -F'/' '{ print $2}')

if [[ $(grep -ci '\[python3\]' <<<$ghprbPullTitle) -gt 0 ]] ; then
  cacheKey="$(cat requirements.txt test-requirements.txt setup.py | sha256sum | awk '{print $1}')"
  REGISTRY="registry.postgun.com:5000/mailgun"
  REPO="${REGISTRY}/${NAME}"
  TAG="PR${ghprbPullId}"
  CACHE_DIR="/var/cache/jenkins/${NAME}/${cacheKey}"
  docker build \
    --target deps \
    -f .build/Dockerfile \
    -t $REPO:$TAG \
    .

  docker run \
    --name $cacheKey \
    --network host \
    --rm \
    -v "$(pwd):/source" \
    -v "/var/lib/jenkins/.ssh:/root/.ssh:ro" \
    -v "${CACHE_DIR}:/wheel" \
    -v "$(pwd)/reports:/reports" \
    -v "$(pwd):/data" \
    --entrypoint=/bin/bash \
    $REPO:$TAG \
    -exc "cd /source; \
         ( curl https://bootstrap.pypa.io/get-pip.py | python - -U pip ply ); \
         pip wheel -f /wheel -w /wheel -r requirements.txt -r test-requirements.txt; \
         rm -rfv ./build python/*.egg-info"

  cp -rv $CACHE_DIR/ ./wheel

  docker build \
    --target testable \
    --build-arg REPORT_PATH=/reports \
    -f .build/Dockerfile \
    -t $REPO:$TAG-test \
    .

  testexit=$(docker run \
    --rm \
    --net host \
    --name $NAME-$TAG-test \
    -e "REPORT_PATH=/reports" \
    -v "/etc/mailgun/ssl:/etc/mailgun/ssl" \
    -v "$(pwd)/reports:/reports" \
    -v "$(pwd):/data" \
    $REPO:$TAG-test; echo $?)

  docker run \
    --rm \
    -v "$(pwd):/data" \
    --entrypoint /bin/sh \
    $REPO:$TAG \
    -exc "chown -Rv $(id -u jenkins):$(id -g jenkins) /data/reports; "

  docker rmi -f $REPO:$TAG-test

  if [[ $testexit -eq 1 ]]; then
    exit $testexit;
  fi
else
  export PYENV_ROOT="/var/lib/jenkins/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
  buildc --svc argus --push-as PR${ghprbPullId} --cleanup --py-image xenial
fi
