def downloadShellQuote(value) {
    "'${value.toString().replace("'", "'\"'\"'")}'"
}

process DOWNLOAD_REFERENCE {
    tag "${logical_basename}"
    label 'process_low'

    input:
    tuple val(location), val(logical_basename)

    output:
    tuple val(location), val(logical_basename), path("${logical_basename}"), emit: artifacts
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    download_reference.py \
        --url ${downloadShellQuote(location)} \
        --output ${downloadShellQuote(logical_basename)} \
        --versions-output versions.yml \
        --process ${downloadShellQuote(task.process)}
    """

    stub:
    """
    printf 'abc' > ${downloadShellQuote(logical_basename)}
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "stub"
    END_VERSIONS
    """
}
