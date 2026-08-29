process BUILD_SYLPH_DATABASE {
    tag "k${build.settings.kmer_length}/c${build.settings.compression}"

    input:
    tuple val(build), path(fastas)

    output:
    tuple val(build), path('database.syldb'), emit: databases
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def fasta_args = fastas.join(' ')
    def individual_arg = build.settings.individual_records ? '--individual-records' : ''
    """
    sylph sketch \
        --genomes ${fasta_args} \
        --out-name-db database \
        -k ${build.settings.kmer_length} \
        -c ${build.settings.compression} \
        --min-spacing ${build.settings.min_spacing} \
        ${individual_arg} \
        -t ${task.cpus}

    SYLPH_VERSION="\$(sylph --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "\${SYLPH_VERSION#sylph }"
    END_VERSIONS
    """

    stub:
    """
    printf 'stub database' > database.syldb
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "stub"
    END_VERSIONS
    """
}
