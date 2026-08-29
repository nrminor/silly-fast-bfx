process DOWNLOAD_REFERENCE {
    tag "${logical_basename}"

    input:
    tuple val(location), val(logical_basename)

    output:
    tuple val(location), path("${logical_basename}"), emit: artifacts
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    download_reference.py \
        --url "${location}" \
        --output "${logical_basename}" \
        --versions-output versions.yml \
        --process ${task.process}
    """

    stub:
    """
    printf 'abc' > "${logical_basename}"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "stub"
    END_VERSIONS
    """
}
