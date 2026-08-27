def checksumShellQuote(value) {
    "'${value.toString().replace("'", "'\"'\"'")}'"
}

process RECORD_REFERENCE_CHECKSUMS {
    tag "${tool}:${reference.id}"
    label 'process_low'

    input:
    tuple val(tool), val(reference), val(sources)

    output:
    tuple val(tool), val(reference), path('source.sha256'), emit: manifests
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def entries = sources.collect { source ->
        "--entry ${checksumShellQuote(source.observed_sha256)} ${checksumShellQuote(source.logical_basename)}"
    }.join(' ')
    """
    write_reference_checksums.py \
        ${entries} \
        --output source.sha256 \
        --versions-output versions.yml \
        --process ${checksumShellQuote(task.process)}
    """

    stub:
    def entries = sources.collect { source ->
        "--entry ${checksumShellQuote(source.observed_sha256)} ${checksumShellQuote(source.logical_basename)}"
    }.join(' ')
    """
    write_reference_checksums.py \
        ${entries} \
        --output source.sha256 \
        --versions-output versions.yml \
        --process ${checksumShellQuote(task.process)}
    """
}
