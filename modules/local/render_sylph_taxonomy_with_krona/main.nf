process RENDER_SYLPH_TAXONOMY_WITH_KRONA {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(taxonomy_profile)

    output:
    tuple val(meta), val(reference), path('*.krona.tsv'), optional: true, emit: contributions
    tuple val(meta), val(reference), path('*.krona.html'), optional: true, emit: charts
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = taxonomy_profile.name.replaceFirst(/\.sylphmpa$/, '')
    """
    export POLARS_MAX_THREADS=${task.cpus}
    render_sylph_taxonomy_contributions.py \
        --profile ${taxonomy_profile} \
        --output ${prefix}.krona.tsv \
        --versions versions.yml \
        --process ${task.process}

    if [[ -s ${prefix}.krona.tsv ]]; then
        ktImportText -o ${prefix}.krona.html -n 'Relative abundance (%)' ${prefix}.krona.tsv,${prefix}
    fi

    KRONA_HELP="\$(ktImportText 2>&1)"
    KRONA_VERSION="\${KRONA_HELP#*KronaTools }"
    cat <<-END_VERSIONS >> versions.yml
        krona: "\${KRONA_VERSION%% *}"
    END_VERSIONS
    """

    stub:
    def prefix = taxonomy_profile.name.replaceFirst(/\.sylphmpa$/, '')
    """
    printf '1\tstub\n' > ${prefix}.krona.tsv
    printf '<html>stub</html>\n' > ${prefix}.krona.html
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        polars: "stub"
        python: "stub"
        krona: "stub"
    END_VERSIONS
    """
}
