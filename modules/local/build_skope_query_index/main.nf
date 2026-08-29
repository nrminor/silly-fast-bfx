process BUILD_SKOPE_QUERY_INDEX {
    tag "k${build.settings.kmer_length}/s${build.settings.smer_length}"

    input:
    tuple val(build), path(targets)

    output:
    tuple val(build), path('query_index.sk'), emit: query_indexes
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def individual_arg = build.settings.individual ? '--individual' : ''
    def positions_arg = build.settings.positions ? '--positions' : ''
    """
    skope index build-query \
        --kmer ${build.settings.kmer_length} \
        --smer ${build.settings.smer_length} \
        --fraction ${build.settings.fraction} \
        ${individual_arg} \
        ${positions_arg} \
        --threads ${task.cpus} \
        --output query_index.sk \
        ${targets}

    SKOPE_VERSION="\$(skope --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        skope: "\${SKOPE_VERSION#skope }"
    END_VERSIONS
    """

    stub:
    """
    printf 'stub query index' > query_index.sk
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        skope: "stub"
    END_VERSIONS
    """
}
