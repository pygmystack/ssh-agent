#!/usr/bin/env bats
# Runtime tests — start a long-running ssh-agent container and exercise
# its behaviour.
#
# A dedicated container is started once in setup_file() and torn down in
# teardown_file().  Key-management tests generate a temporary ed25519 key
# that lives only for the duration of the suite.
#
# Tests are ordered intentionally: the "no identities" assertion runs before
# the key-add tests so the agent is still empty at that point.

bats_require_minimum_version 1.5.0

IMAGE="${IMAGE_NAME:-pygmystack/ssh-agent:test}"
SSH_AUTH_SOCK_PATH="/tmp/amazeeio_ssh-agent/socket"

# Container name is restored in setup() from the suffix written by setup_file(),
# because BATS re-sources the file for every individual test.
SSH_AGENT_CONTAINER=""

# ---------------------------------------------------------------------------
# File-level setup / teardown — container is started once for the whole file.
# ---------------------------------------------------------------------------

setup_file() {
    # Generate a unique suffix and persist it so every test shares the same
    # container name despite BATS re-sourcing the file per test.
    local suffix
    suffix="$(openssl rand -hex 4)"
    echo "${suffix}" > "${BATS_SUITE_TMPDIR}/.suffix"
    SSH_AGENT_CONTAINER="ssh-agent-bats-test-${suffix}"

    # Remove any leftover container from a previous (failed) run.
    docker rm -f "${SSH_AGENT_CONTAINER}" 2>/dev/null || true

    docker run -d --name "${SSH_AGENT_CONTAINER}" "${IMAGE}"

    # Wait up to 15 seconds for the ssh-agent socket to appear.
    local max_wait=15
    local waited=0
    until docker exec "${SSH_AGENT_CONTAINER}" \
            sh -c "test -S '${SSH_AUTH_SOCK_PATH}'" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$max_wait" ]; then
            echo "# Timed out waiting for SSH agent socket at ${SSH_AUTH_SOCK_PATH}" >&3
            docker logs "${SSH_AGENT_CONTAINER}" >&3 2>&3
            return 1
        fi
    done

    # Generate a temporary ed25519 key for later key-management tests.
    ssh-keygen -t ed25519 -q \
        -f "${BATS_SUITE_TMPDIR}/test_id_ed25519" \
        -N "" -C "bats-test-key"
}

teardown_file() {
    local suffix
    suffix="$(cat "${BATS_SUITE_TMPDIR}/.suffix" 2>/dev/null || true)"
    docker rm -f "ssh-agent-bats-test-${suffix}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Per-test setup — restore the container name variable from the stable suffix.
# ---------------------------------------------------------------------------

setup() {
    local suffix
    suffix="$(cat "${BATS_SUITE_TMPDIR}/.suffix" 2>/dev/null || true)"
    SSH_AGENT_CONTAINER="ssh-agent-bats-test-${suffix}"
}

# ---------------------------------------------------------------------------
# Container lifecycle
# ---------------------------------------------------------------------------

@test "container is running" {
    run docker inspect --format='{{.State.Status}}' "${SSH_AGENT_CONTAINER}"
    [ "$status" -eq 0 ]
    [ "$output" = "running" ]
}

@test "ssh-agent process is running inside the container" {
    run docker exec "${SSH_AGENT_CONTAINER}" sh -c 'ps | grep "[s]sh-agent"'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# ---------------------------------------------------------------------------
# Socket
# ---------------------------------------------------------------------------

@test "agent socket file exists at SSH_AUTH_SOCK path" {
    run docker exec "${SSH_AGENT_CONTAINER}" \
        sh -c "test -S '${SSH_AUTH_SOCK_PATH}' && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "agent socket is owned by the drupal user" {
    run docker exec "${SSH_AGENT_CONTAINER}" \
        stat -c '%U' "${SSH_AUTH_SOCK_PATH}"
    [ "$status" -eq 0 ]
    [ "$output" = "drupal" ]
}

# ---------------------------------------------------------------------------
# Key management
# ---------------------------------------------------------------------------

@test "ssh-add -l reports no identities when the agent is empty" {
    run docker run --rm \
        --volumes-from "${SSH_AGENT_CONTAINER}" \
        "${IMAGE}" ssh-add -l
    # ssh-add -l exits 1 and prints "no identities" when the agent is empty.
    [ "$status" -eq 1 ]
    [[ "$output" =~ "no identities" ]]
}

@test "an SSH key can be added to the agent" {
    run docker run --rm \
        --volumes-from "${SSH_AGENT_CONTAINER}" \
        -v "${BATS_SUITE_TMPDIR}:/bats-keys:ro" \
        --entrypoint sh \
        "${IMAGE}" -c '
            cp /bats-keys/test_id_ed25519 /tmp/test_key
            chmod 400 /tmp/test_key
            ssh-add /tmp/test_key
        '
    [ "$status" -eq 0 ]
}

@test "added SSH key appears in ssh-add -l output" {
    run docker run --rm \
        --volumes-from "${SSH_AGENT_CONTAINER}" \
        "${IMAGE}" ssh-add -l
    [ "$status" -eq 0 ]
    [[ "$output" =~ "bats-test-key" ]]
}
