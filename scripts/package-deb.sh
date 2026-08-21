#!/usr/bin/env bash
# Build Chef Infra Client under $PREFIX and emit a release-specific Ubuntu .deb.
#
# Expected container mounts:
#   /src            Chef source tree (read-only)
#   /out            Output directory for the .deb
#   /work           Writable workspace
#   $PREFIX         Persistent volume for embedded Ruby + gems (optional cache)
#
# Required environment variables are validated below.
set -euo pipefail

: "${UBUNTU_RELEASE:?}"
: "${UBUNTU_CODENAME:?}"
: "${CHEF_VERSION:?}"
: "${RUBY_VERSION:?}"
: "${PACKAGE_NAME:?}"
: "${PACKAGE_ARCH:?}"
: "${CHEF_LICENSE:?}"
: "${RUNTIME_DEPENDS:?}"

PREFIX="${PREFIX:-/opt/chef-infra-client}"
SRC_DIR="${SRC_DIR:-/src}"
OUT_DIR="${OUT_DIR:-/out}"
WORK_DIR="${WORK_DIR:-/work}"
PACKAGE_VERSION="${CHEF_VERSION}~ubuntu${UBUNTU_RELEASE}"
DEB_FILENAME="${PACKAGE_NAME}_${PACKAGE_VERSION}_${PACKAGE_ARCH}.deb"

export DEBIAN_FRONTEND=noninteractive
export CHEF_LICENSE
export PATH="${PREFIX}/embedded/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "==> Packaging Chef ${CHEF_VERSION} for Ubuntu ${UBUNTU_RELEASE} (${UBUNTU_CODENAME})"
echo "    prefix=${PREFIX}"
echo "    output=${OUT_DIR}/${DEB_FILENAME}"

apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  wget \
  git \
  gnupg \
  pkg-config \
  autoconf \
  bison \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  libyaml-dev \
  libffi-dev \
  libxml2-dev \
  libxslt1-dev \
  libarchive-dev \
  libncurses-dev \
  libgdbm-dev \
  libdb-dev \
  xz-utils \
  unzip \
  rsync \
  ruby \
  ruby-dev \
  rubygems

gem install fpm --no-document

mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${PREFIX}"

if [[ ! -x "${PREFIX}/embedded/bin/ruby" ]]; then
  echo "==> Building Ruby ${RUBY_VERSION} into ${PREFIX}/embedded"
  rm -rf "${WORK_DIR}/ruby-build"
  git clone --depth 1 https://github.com/rbenv/ruby-build.git "${WORK_DIR}/ruby-build"
  RUBY_CONFIGURE_OPTS="--disable-install-doc" \
    "${WORK_DIR}/ruby-build/bin/ruby-build" "${RUBY_VERSION}" "${PREFIX}/embedded"
else
  echo "==> Reusing cached Ruby at ${PREFIX}/embedded"
fi

EMBEDDED="${PREFIX}/embedded"
export PATH="${EMBEDDED}/bin:${PATH}"

"${EMBEDDED}/bin/gem" install bundler --version 2.6.9 --no-document

BUILD_SRC="${WORK_DIR}/build-src"
rm -rf "${BUILD_SRC}"
mkdir -p "${BUILD_SRC}"
rsync -a --delete \
  --exclude '.bundle/' \
  --exclude 'vendor/package-bundle/' \
  --exclude 'results/' \
  "${SRC_DIR}/" "${BUILD_SRC}/"

cd "${BUILD_SRC}"
bundle config set --local path "vendor/package-bundle"
bundle config set --local jobs "$(nproc)"
bundle config set --local retry 5
bundle config set --local without "server:docgen:maintenance:pry:travis:integration:ci"
bundle config set --local force_ruby_platform true
bundle install --jobs="$(nproc)" --retry=3
if [[ -f ./post-bundle-install.rb ]]; then
  ruby ./post-bundle-install.rb
fi

build_gem() {
  local dir="$1"
  local gemspec="$2"
  mkdir -p "${dir}/pkg"
  (
    cd "${dir}"
    rm -f pkg/*.gem
    gem build "${gemspec}"
    mv -f ./*.gem pkg/
  )
}

build_gem chef-utils chef-utils.gemspec
build_gem chef-config chef-config.gemspec
build_gem . chef.gemspec
build_gem chef-bin chef-bin.gemspec

gem install --no-document \
  "${BUILD_SRC}/chef-utils/pkg/chef-utils-${CHEF_VERSION}.gem" \
  "${BUILD_SRC}/chef-config/pkg/chef-config-${CHEF_VERSION}.gem" \
  "${BUILD_SRC}/pkg/chef-${CHEF_VERSION}.gem" \
  "${BUILD_SRC}/chef-bin/pkg/chef-bin-${CHEF_VERSION}.gem"

test -x "${EMBEDDED}/bin/chef-client"
"${EMBEDDED}/bin/chef-client" --version

STAGE="${WORK_DIR}/stage"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/opt" "${STAGE}/usr/bin"
cp -a "${PREFIX}" "${STAGE}/opt/$(basename "${PREFIX}")"

for bin in chef-client chef-solo chef-shell chef-apply knife ohai; do
  if [[ -x "${EMBEDDED}/bin/${bin}" ]]; then
    cat >"${STAGE}/usr/bin/${bin}" <<EOF
#!/bin/sh
export CHEF_LICENSE="\${CHEF_LICENSE:-${CHEF_LICENSE}}"
exec ${PREFIX}/embedded/bin/${bin} "\$@"
EOF
    chmod 0755 "${STAGE}/usr/bin/${bin}"
  fi
done

FPM_DEPS=()
IFS=',' read -r -a dep_list <<<"${RUNTIME_DEPENDS}"
for dep in "${dep_list[@]}"; do
  dep_trimmed="$(echo "${dep}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -n "${dep_trimmed}" ]] || continue
  FPM_DEPS+=(-d "${dep_trimmed}")
done

cd "${OUT_DIR}"
rm -f "${DEB_FILENAME}"
fpm \
  -s dir \
  -t deb \
  -n "${PACKAGE_NAME}" \
  -v "${PACKAGE_VERSION}" \
  -a "${PACKAGE_ARCH}" \
  --maintainer "local-build" \
  --description "Chef Infra Client ${CHEF_VERSION} for Ubuntu ${UBUNTU_RELEASE} (${UBUNTU_CODENAME}), built from source" \
  --url "https://github.com/chef/chef" \
  --license "Apache-2.0" \
  --deb-user root \
  --deb-group root \
  --deb-dist "${UBUNTU_CODENAME}" \
  -C "${STAGE}" \
  "${FPM_DEPS[@]}" \
  opt \
  usr/bin

echo "==> Built ${OUT_DIR}/${DEB_FILENAME}"
ls -lh "${OUT_DIR}/${DEB_FILENAME}"
