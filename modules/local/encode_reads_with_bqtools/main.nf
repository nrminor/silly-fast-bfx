process ENCODE_READS_WITH_BQTOOLS {
    tag "${meta.id}"
    label 'process_low'

    input:
    tuple val(meta), path(reads, stageAs: 'reads??/*', arity: '1..2')

    output:
    tuple val(meta), path("${meta.id}.cbq"), emit: encodings
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def read_args = reads.join(' ')
    """
    bqtools encode \
        --mode cbq \
        --block-size 128K \
        --level 3 \
        --threads ${task.cpus} \
        --output ${meta.id}.cbq \
        ${read_args}

    BQTOOLS_VERSION="\$(bqtools --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bqtools: "\${BQTOOLS_VERSION#bqtools }"
    END_VERSIONS
    """

    stub:
    """
    printf 'stub cbq' > ${meta.id}.cbq
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bqtools: "stub"
    END_VERSIONS
    """
}
