process DOWNLOAD_SRACHA_FASTQ {
    tag "${meta.id}:${accession}"
    label 'process_medium'

    input:
    tuple val(meta), val(accession)

    output:
    tuple val(meta), path("${accession}*.fastq.gz", arity: '1..2'), emit: reads
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    sracha get \
        --split split-3 \
        --gzip-level 1 \
        --threads ${task.cpus} \
        --no-progress \
        --yes \
        --output-dir . \
        '${accession}'

    SRACHA_VERSION="\$(sracha --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sracha: "\${SRACHA_VERSION#sracha }"
    END_VERSIONS
    """

    stub:
    """
    printf '@stub\nA\n+\nI\n' | gzip -n > '${accession}.fastq.gz'
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sracha: "stub"
    END_VERSIONS
    """
}
