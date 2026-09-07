process CONCATENATE_CBQS_WITH_BQTOOLS {
    tag "${meta.id}"

    input:
    tuple val(meta), path(cbqs, stageAs: 'cbqs??????/*', arity: '2..*')

    output:
    tuple val(meta), path("${meta.id}.cbq", arity: '1'), emit: encodings
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    staged_cbqs=(cbqs??????/*)

    bqtools cat \
        "\${staged_cbqs[@]}" \
        --threads ${task.cpus} \
        --output ${meta.id}.cbq

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
