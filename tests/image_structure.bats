#!/usr/bin/env bats
# Image structure tests — verify binaries, files, environment variables,
# and configuration baked into the image.  These tests run ephemeral
# containers and do not require long-running processes or the Docker socket.

bats_require_minimum_version 1.5.0

IMAGE="${IMAGE_NAME:-pygmystack/ssh-agent:test}"

# ---------------------------------------------------------------------------
# Binaries
# ---------------------------------------------------------------------------

@test "ssh-agent binary is available in PATH" {
    run docker run --rm --entrypoint which "${IMAGE}" ssh-agent
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "ssh-add binary is available in PATH" {
    run docker run --rm --entrypoint which "${IMAGE}" ssh-add
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "ssh binary is available in PATH" {
    run docker run --rm --entrypoint which "${IMAGE}" ssh
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "sudo binary is available in PATH" {
    run docker run --rm --entrypoint which "${IMAGE}" sudo
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "openssh version matches Dockerfile" {
    local expected_version
    expected_version="$(grep -oE 'openssh=~[0-9]+\.[0-9]+' "${BATS_TEST_DIRNAME}/../Dockerfile" | grep -oE '[0-9]+\.[0-9]+')"
    run docker run --rm --entrypoint sh "${IMAGE}" -c 'ssh -V 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" =~ "${expected_version}" ]]
}

# ---------------------------------------------------------------------------
# Required files
# ---------------------------------------------------------------------------

@test "/run.sh exists" {
    run docker run --rm --entrypoint sh "${IMAGE}" -c 'test -f /run.sh'
    [ "$status" -eq 0 ]
}

@test "/run.sh is executable" {
    run docker run --rm --entrypoint sh "${IMAGE}" -c 'test -x /run.sh'
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# User configuration
# ---------------------------------------------------------------------------

@test "drupal user exists in the image" {
    run docker run --rm --entrypoint sh "${IMAGE}" -c 'id drupal'
    [ "$status" -eq 0 ]
}

@test "drupal user has uid 1000" {
    run docker run --rm --entrypoint sh "${IMAGE}" -c 'id -u drupal'
    [ "$status" -eq 0 ]
    [ "$output" = "1000" ]
}

# ---------------------------------------------------------------------------
# Environment variables
# ---------------------------------------------------------------------------

@test "SOCKET_DIR is set to /tmp/amazeeio_ssh-agent" {
    run docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "${IMAGE}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SOCKET_DIR=/tmp/amazeeio_ssh-agent" ]]
}

@test "SSH_AUTH_SOCK is set to /tmp/amazeeio_ssh-agent/socket" {
    run docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "${IMAGE}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH_AUTH_SOCK=/tmp/amazeeio_ssh-agent/socket" ]]
}

# ---------------------------------------------------------------------------
# Volume declaration (image metadata)
# ---------------------------------------------------------------------------

@test "image declares /tmp/amazeeio_ssh-agent as a volume" {
    run docker inspect --format='{{json .Config.Volumes}}' "${IMAGE}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "/tmp/amazeeio_ssh-agent" ]]
}
