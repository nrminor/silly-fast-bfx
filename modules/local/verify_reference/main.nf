def verifyShellQuote(value) {
    "'${value.toString().replace("'", "'\"'\"'")}'"
}

process VERIFY_REFERENCE {
    tag "${logical_basename}"
    label 'process_low'

    input:
    tuple val(location), val(logical_basename), path(artifact), val(expected_sha256s)

    output:
    tuple val(location), val(logical_basename), path(artifact), path('observed.sha256'), emit: artifacts
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def expected_args = expected_sha256s.collect { digest ->
        "--expected ${verifyShellQuote(digest)}"
    }.join(' ')
    """
    verify_reference.py \
        --artifact ${verifyShellQuote(artifact)} \
        --location ${verifyShellQuote(location)} \
        ${expected_args} \
        --output observed.sha256 \
        --versions-output versions.yml \
        --process ${verifyShellQuote(task.process)}
    """

    stub:
    def expected_args = expected_sha256s.collect { digest ->
        "--expected ${verifyShellQuote(digest)}"
    }.join(' ')
    """
    verify_reference.py \
        --artifact ${verifyShellQuote(artifact)} \
        --location ${verifyShellQuote(location)} \
        ${expected_args} \
        --output observed.sha256 \
        --versions-output versions.yml \
        --process ${verifyShellQuote(task.process)}
    """
}
