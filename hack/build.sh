#!/bin/sh

set -ex

mkdir -p ../cluster-api/providers # hack to speed up build

# zOS USS compile specific var&parm
export __ZOS_TRACE=1
export __GOZ_EXTRA_ARGS='-v'
export COMPATH_PATH="/global/cnw/v2r2/openxl/bin/ibm-clang"
eval $(/global/golang/1.24/etc/goz-env)

# Source the Cluster API build script.
# shellcheck source=hack/build-cluster-api.sh
. "$(dirname "$0")/build-cluster-api.sh"

# shellcheck disable=SC2068
version() { IFS="."; printf "%03d%03d%03d\\n" $@; unset IFS;}

minimum_go_version=1.23
current_go_version=$(go version | cut -d " " -f 3)

if [ "$(version "${current_go_version#go}")" -lt "$(version "$minimum_go_version")" ]; then
     echo "Go version should be greater or equal to $minimum_go_version"
     exit 1
fi

# export CGO_ENABLED=1
MODE="${MODE:-release}"

# build cluster-api binaries
gmake -C cluster-api all
copy_cluster_api_to_mirror

GIT_COMMIT="${SOURCE_GIT_COMMIT:-$(git rev-parse --verify 'HEAD^{commit}')}"
GIT_TAG="${BUILD_VERSION:-$(git describe --always --abbrev=40 --dirty)}"
DEFAULT_ARCH="${DEFAULT_ARCH:-amd64}"
GOFLAGS="${GOFLAGS:--mod=vendor}"
GCFLAGS=""
LDFLAGS="${LDFLAGS} -X github.com/openshift/installer/pkg/version.Raw=${GIT_TAG} -X github.com/openshift/installer/pkg/version.Commit=${GIT_COMMIT} -X github.com/openshift/installer/pkg/version.defaultArch=${DEFAULT_ARCH}"
TAGS="${TAGS:-}"
OUTPUT="${OUTPUT:-bin/openshift-install}"

case "${MODE}" in
release)
	LDFLAGS="${LDFLAGS} -s -w"
	TAGS="${TAGS} release"
	;;
dev)
    GCFLAGS="${GCFLAGS} all=-N -l"
	;;
*)
	echo "unrecognized mode: ${MODE}" >&2
	exit 1
esac

if test "${SKIP_GENERATION}" != y
then
	# this step has to be run natively, even when cross-compiling
	GOOS='' GOARCH='' go generate ./data
fi

if (echo "${TAGS}" | grep -q '\bfipscapable\b')
then
	export CGO_ENABLED=1
fi

echo "building openshift-install"

# shellcheck disable=SC2086
go build ${GOFLAGS} -gcflags "${GCFLAGS}" -ldflags "${LDFLAGS}" -tags "${TAGS}" -o "${OUTPUT}" ./cmd/openshift-install
