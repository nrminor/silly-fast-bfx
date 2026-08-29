process VALIDATE_SRACHA_RUN {
    tag "${meta.id}:${accession}"
    label 'process_low'

    input:
    tuple val(meta), val(accession)

    output:
    tuple val(meta), val(accession), emit: runs
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    sracha info --format tsv '${accession}' > /dev/null

    SRACHA_VERSION="\$(sracha --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sracha: "\${SRACHA_VERSION#sracha }"
    END_VERSIONS
    """

    stub:
    """
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sracha: "stub"
    END_VERSIONS
    """
}
