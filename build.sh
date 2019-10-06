#!/bin/bash
# Copyright (c) 2019 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation

set -e
set -u

# conf
CHE_THEIA_BRANCH="CHE-13765-b"
THEIA_BRANCH="master"

CHE_THEIA_DEV_IMAGE_NAME="quay.io/codeready-workspaces/che-theia-dev:next"
#need to edit conf/theia/ubi8-brew/builder-from.dockerfile file as well for now
CHE_THEIA_IMAGE_NAME="quay.io/codeready-workspaces/che-theia:next"

base_dir=$(cd "$(dirname "$0")"; pwd)

# variables
TMP_DIR=${base_dir}/tmp
BREW_DOCKERFILE_ROOT_DIR=${base_dir}/"dockerfiles"
CHE_THEIA_DIR=${TMP_DIR}/che-theia

if [ ! -d "${TMP_DIR}" ]; then
  rm -rf "${TMP_DIR}"
  mkdir -p "${TMP_DIR}"
  # Clone che-theia with sha-1/tag/whatever
  git clone -b ${CHE_THEIA_BRANCH} --single-branch --depth 1 https://github.com/eclipse/che-theia "${TMP_DIR}"/che-theia
  
  # init yarn in che-theia
  pushd "${CHE_THEIA_DIR}" >/dev/null
  yarn
  popd >/dev/null
  
fi

mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"
DOCKERFILES_ROOT_DIR=${TMP_DIR}/che-theia/dockerfiles

handle_theia_dev() {

  TMP_BUILDER_IMAGE="che-theia-dev-builder:tmp"

  # build only ubi8 image
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-dev >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run
  docker build -f .Dockerfile -t ${TMP_BUILDER_IMAGE} .
  # For use in default
  docker tag ${TMP_BUILDER_IMAGE} eclipse/che-theia-dev:next
  popd >/dev/null
  
  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew
  # Add extra conf
  cp conf/theia-dev/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia-dev/docker/ubi8-brew/
  
  # dry-run for theia-dev:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia-dev >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run
  popd >/dev/null
  
  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  
  echo "Remove previous assets"
  rm -rf assets-*
  # copy assets
  cp "${CHE_THEIA_DIR}"/dockerfiles/theia-dev/asset-* .
  # Copy src
  rm -rf src
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia-dev/src .
  
  # Create asset with yarn cache
  # /usr/local/share/.cache/yarn/v4 = yarn cache dir
  # /home/theia-dev/.yarn-global = yarn
  # /opt/app-root/src/.npm-global = yarn symlinks
  docker run --rm --entrypoint= ${TMP_BUILDER_IMAGE} tar -pzcf - /usr/local/share/.cache/yarn/v4 /home/theia-dev/.yarn-global /opt/app-root/src/.npm-global > asset-yarn.tgz
  popd >/dev/null
  
  # Copy generate Dockerfile
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev
  cp "${DOCKERFILES_ROOT_DIR}"/theia-dev/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev/Dockerfile
  
  # build local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia-dev >/dev/null
  docker build -t ${CHE_THEIA_DEV_IMAGE_NAME} .
  popd >/dev/null
}

# now do che-theia
handle_theia() {

  TMP_BUILDER_IMAGE="che-theia-builder:tmp"
  TMP_RUNTIME_IMAGE="che-theia-runtime:tmp"
  # build only ubi8 image and for target builder first, so we can extract data
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  # first generate the Dockerfile
  bash ./build.sh --dockerfile:Dockerfile.ubi8 --skip-tests --dry-run --build-args:THEIA_VERSION=${THEIA_BRANCH},DO_REMOTE_CHECK=false,DO_CLEANUP=false --tag:next --branch:${THEIA_BRANCH} --target:builder
  cp .Dockerfile .ubi8-dockerfile
  # Create one image for builder
  pwd
  docker build -f .ubi8-dockerfile -t ${TMP_BUILDER_IMAGE} --target builder .
  # and create runtime image as well
  docker build -f .ubi8-dockerfile -t ${TMP_RUNTIME_IMAGE} .
  popd >/dev/null
  
  # Create image theia-dev:ubi8-brew
  rm -rf "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8 "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew
  # Add extra conf
  cp conf/theia/ubi8-brew/* "${DOCKERFILES_ROOT_DIR}"/theia/docker/ubi8-brew/
  
  # dry-run for theia:ubi8-brew to only generate Dockerfile
  pushd "${DOCKERFILES_ROOT_DIR}"/theia >/dev/null
  bash ./build.sh --dockerfile:Dockerfile.ubi8-brew --skip-tests --dry-run --build-args:THEIA_VERSION=${THEIA_BRANCH},DO_REMOTE_CHECK=false --tag:next --branch:${THEIA_BRANCH} --target:builder
  popd >/dev/null
  
  # Copy assets from ubi8 to local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null

  # copy assets
  cp "${CHE_THEIA_DIR}"/dockerfiles/theia/asset-* .

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v4 = yarn cache dir
  # /home/theia-dev/.yarn-global = yarn
  # /opt/app-root/src/.npm-global = yarn symlinks
  docker run --rm --entrypoint= ${TMP_BUILDER_IMAGE} tar -pzcf - /usr/local/share/.cache/yarn/v4 /home/theia-dev/.yarn-global /opt/app-root/src/.npm-global > asset-yarn.tar.gz
  
  # post-install dependencies
  # /home/theia-dev/theia-source-code/packages/java/download = jdt ls binary
  # /home/theia-dev/theia-source-code/packages/debug-nodejs/download = node debug vscode binary
  # /home/theia-dev/theia-source-code/packages/java-debug/download = java debug vscode binary
  # /tmp/vscode-ripgrep-cache-1.2.4 /tmp/vscode-ripgrep-cache-1.5.7 = rigrep binaries
  # /home/theia-dev/.cache = include electron/node-gyp cache
  docker run --rm --entrypoint= ${TMP_BUILDER_IMAGE} tar -pzcf - /home/theia-dev/theia-source-code/packages/java/download /home/theia-dev/theia-source-code/packages/java-debug/download /home/theia-dev/theia-source-code/packages/debug-nodejs/download  /tmp/vscode-ripgrep-cache-1.2.4 /tmp/vscode-ripgrep-cache-1.5.7 /home/theia-dev/.cache > asset-post-download-dependencies.tar.gz
  
  # node-headers
  docker run --rm --entrypoint= ${TMP_BUILDER_IMAGE} sh -c 'nodeVersion=$(node --version); download_url="https://nodejs.org/download/release/${nodeVersion}/node-${nodeVersion}-headers.tar.gz" && curl ${download_url}' > asset-node-headers.tar.gz
  
  # moxios is used with a github URL, not a npmjs dependency, need to provide the dependency
  git clone https://github.com/stoplightio/moxios.git "${BREW_DOCKERFILE_ROOT_DIR}"/moxios
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/moxios >/dev/null
  tar zcf "${BREW_DOCKERFILE_ROOT_DIR}/theia/asset-moxios.tgz" -- *
  rm -rf "${BREW_DOCKERFILE_ROOT_DIR}"/moxios
  popd >/dev/null

  # Add yarn.lock after compilation
  docker run --rm --entrypoint= ${TMP_BUILDER_IMAGE} sh -c 'cat /home/theia-dev/theia-source-code/yarn.lock' > asset-yarn.lock

  # Theia source code
  docker run --rm --entrypoint= ${TMP_BUILDER_IMAGE} sh -c 'cat /home/theia-dev/theia-source-code.tgz' > asset-theia-source-code.tar.gz

  # npm/yarn cache
  # /usr/local/share/.cache/yarn/v4/ = yarn cache dir
  # /opt/app-root/src/.npm-global = npm global
  docker run --rm --entrypoint= ${TMP_RUNTIME_IMAGE} tar -pzcf - /usr/local/share/.cache/yarn/v4/ /opt/app-root/src/.npm-global > asset-yarn-runtime-image.tar.gz

  rm -rf src
  cp -r "${DOCKERFILES_ROOT_DIR}"/theia/src .
  
  # Copy generate Dockerfile
  mkdir -p "${BREW_DOCKERFILE_ROOT_DIR}"/theia
  cp "${DOCKERFILES_ROOT_DIR}"/theia/.Dockerfile "${BREW_DOCKERFILE_ROOT_DIR}"/theia/Dockerfile
  
  # build local
  pushd "${BREW_DOCKERFILE_ROOT_DIR}"/theia >/dev/null
  docker build -t ${CHE_THEIA_IMAGE_NAME} .
  popd >/dev/null
}

handle_theia_dev
handle_theia
