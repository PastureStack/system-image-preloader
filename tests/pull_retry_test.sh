#!/usr/bin/env bash
# Created by PastureStack contributors for offline retry-policy testing.

set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SYSTEM_IMAGE_PRELOADER_SOURCE_ONLY=true
# shellcheck source=../system-image-preloader
source "${TEST_ROOT}/system-image-preloader"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "${expected}" != "${actual}" ]]; then
        fail "${message}: expected ${expected@Q}, got ${actual@Q}"
    fi
}

test_present_image_skips_pull() {
    local pull_calls=0

    docker_cli() {
        if [[ "$1" == "image" && "$2" == "inspect" ]]; then
            return 0
        fi
        if [[ "$1" == "pull" ]]; then
            ((pull_calls += 1))
            return 0
        fi
        return 1
    }

    retry_sleep() {
        fail 'sleep must not be called for a present image'
    }

    IMAGE_PULL_MAX_ATTEMPTS=3 IMAGE_PULL_RETRY_DELAY_SECONDS=0 \
        pull_image_with_retry 'registry.invalid/present:test' >/dev/null
    assert_equal 0 "${pull_calls}" 'present image pull count'
}

test_pull_succeeds_after_bounded_retries() {
    local pull_calls=0
    local sleep_calls=0

    docker_cli() {
        if [[ "$1" == "image" && "$2" == "inspect" ]]; then
            return 1
        fi
        if [[ "$1" == "pull" ]]; then
            ((pull_calls += 1))
            ((pull_calls >= 3))
            return
        fi
        return 1
    }

    retry_sleep() {
        assert_equal 7 "$1" 'retry delay'
        ((sleep_calls += 1))
    }

    IMAGE_PULL_MAX_ATTEMPTS=4 IMAGE_PULL_RETRY_DELAY_SECONDS=7 \
        pull_image_with_retry 'registry.invalid/eventual:test' >/dev/null
    assert_equal 3 "${pull_calls}" 'eventual-success pull count'
    assert_equal 2 "${sleep_calls}" 'eventual-success sleep count'
}

test_pull_exhausts_exact_attempt_limit() {
    local pull_calls=0
    local sleep_calls=0

    docker_cli() {
        if [[ "$1" == "image" && "$2" == "inspect" ]]; then
            return 1
        fi
        if [[ "$1" == "pull" ]]; then
            ((pull_calls += 1))
            return 1
        fi
        return 1
    }

    retry_sleep() {
        ((sleep_calls += 1))
    }

    if IMAGE_PULL_MAX_ATTEMPTS=3 IMAGE_PULL_RETRY_DELAY_SECONDS=0 \
        pull_image_with_retry 'registry.invalid/exhausted:test' >/dev/null 2>&1; then
        fail 'exhausted pull unexpectedly succeeded'
    fi

    assert_equal 3 "${pull_calls}" 'exhausted pull count'
    assert_equal 2 "${sleep_calls}" 'exhausted sleep count'
}

test_invalid_attempt_limit_is_rejected_before_docker() {
    local docker_calls=0

    docker_cli() {
        ((docker_calls += 1))
        return 0
    }

    if IMAGE_PULL_MAX_ATTEMPTS=0 IMAGE_PULL_RETRY_DELAY_SECONDS=0 \
        pull_image_with_retry 'registry.invalid/invalid:test' >/dev/null 2>&1; then
        fail 'zero attempt limit unexpectedly succeeded'
    fi

    assert_equal 0 "${docker_calls}" 'invalid-policy Docker call count'
}

test_registry_resolution() {
    assert_equal 'example.test/team/image:tag' \
        "$(resolve_image_reference 'example.test/' 'team/image:tag')" \
        'custom registry reference'
    assert_equal 'team/image:tag' \
        "$(resolve_image_reference '' 'team/image:tag')" \
        'default registry reference'
    assert_equal 'team/image:tag' \
        "$(resolve_image_reference 'null' 'team/image:tag')" \
        'null registry reference'
}

test_metadata_paths_do_not_repeat_latest() {
    METADATA_URL='http://metadata.test/latest/'
    assert_equal 'http://metadata.test/latest/self/stack/environment_name' \
        "$(metadata_url self/stack/environment_name)" \
        'environment metadata URL'
    assert_equal 'http://metadata.test/latest/hosts' \
        "$(metadata_url hosts)" \
        'host metadata URL'
}

test_api_url_and_version_link_resolution() {
    CATTLE_URL='https://platform.test/v1'
    derive_api_urls
    assert_equal 'https://platform.test/v2-beta' "${CATTLE_URL_V2}" \
        'v2-beta URL'
    assert_equal 'https://platform.test/v1-catalog' "${CATTLE_URL_CATALOG}" \
        'catalog URL'
    assert_equal 'https://platform.test/v1-catalog/templates/example/versions/1' \
        "$(resolve_version_link '/v1-catalog/templates/example/versions/1')" \
        'relative version link'
    assert_equal 'https://catalog.test/versions/1' \
        "$(resolve_version_link 'https://catalog.test/versions/1')" \
        'absolute version link'
}

test_offline_help_and_version() {
    local help_output
    local version_output

    help_output="$(SYSTEM_IMAGE_PRELOADER_SOURCE_ONLY=false bash "${TEST_ROOT}/system-image-preloader" --help)"
    [[ "${help_output}" == *'Usage: system-image-preloader'* ]] \
        || fail 'offline help output is missing the program name'

    version_output="$(SYSTEM_IMAGE_PRELOADER_SOURCE_ONLY=false SYSTEM_IMAGE_PRELOADER_VERSION=fixture-test \
        bash "${TEST_ROOT}/system-image-preloader" --version)"
    assert_equal 'system-image-preloader fixture-test' "${version_output}" 'offline version output'
}

test_present_image_skips_pull
test_pull_succeeds_after_bounded_retries
test_pull_exhausts_exact_attempt_limit
test_invalid_attempt_limit_is_rejected_before_docker
test_registry_resolution
test_metadata_paths_do_not_repeat_latest
test_api_url_and_version_link_resolution
test_offline_help_and_version

printf 'PASS: offline bounded pull retry tests\n'
