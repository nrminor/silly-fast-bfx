process RENDER_COMBINED_SYLPH_TAXONOMY_WITH_KRONA {
    tag "${reference.id}"

    input:
    tuple val(reference), val(labels), path(contributions, stageAs: 'inputs/*', arity: '1..*')

    output:
    tuple val(reference), path('all-samples.krona.html', arity: '1'), emit: charts
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def datasets = contributions.withIndex().collect { input, index -> "\"${input},${labels[index]}\"" }.join(' ')
    """
    ktImportText -o all-samples.krona.html -n 'Relative abundance (%)' ${datasets}

    KRONA_HELP="\$(ktImportText 2>&1)"
    KRONA_VERSION="\${KRONA_HELP#*KronaTools }"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        krona: "\${KRONA_VERSION%% *}"
    END_VERSIONS
    """

    stub:
    """
    printf '<html>stub</html>\n' > all-samples.krona.html
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        krona: "stub"
    END_VERSIONS
    """
}
