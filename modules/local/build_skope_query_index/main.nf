process BUILD_SKOPE_QUERY_INDEX {
    tag "k${build.settings.kmer_length}/${build.settings.all_kmers ? 'all-kmers' : 's' + build.settings.smer_length}"

    input:
    tuple val(build), path(targets, stageAs: 'targets/*')

    output:
    tuple val(build), path('query_index.sk'), emit: query_indexes
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def selection_arg = build.settings.all_kmers ? '--all-kmers' : "--smer ${build.settings.smer_length}"
    def individual_arg = build.settings.individual ? '--individual' : ''
    def positions_arg = build.settings.positions ? '--positions' : ''
    def target_arg = targets instanceof List ? 'targets' : targets
    """
    skope index build-query \
        --kmer ${build.settings.kmer_length} \
        ${selection_arg} \
        --fraction ${build.settings.fraction} \
        ${individual_arg} \
        ${positions_arg} \
        --threads ${task.cpus} \
        --output query_index.sk \
        ${target_arg}

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
