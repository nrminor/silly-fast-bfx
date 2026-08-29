process BUILD_DEACON_INDEX {
    tag "k${build.settings.kmer_length}/w${build.settings.window_size}"

    input:
    tuple val(build), path(fasta)

    output:
    tuple val(build), path('deacon.idx'), emit: indexes
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    deacon index build \
        -k ${build.settings.kmer_length} \
        -w ${build.settings.window_size} \
        -t ${task.cpus} \
        --output deacon.idx \
        ${fasta}

    DEACON_VERSION="\$(deacon --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deacon: "\${DEACON_VERSION#deacon }"
    END_VERSIONS
    """

    stub:
    """
    printf 'stub index' > deacon.idx
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deacon: "stub"
    END_VERSIONS
    """
}
