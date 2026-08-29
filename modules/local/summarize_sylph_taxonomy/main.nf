process SUMMARIZE_SYLPH_TAXONOMY {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta),
          val(reference),
          path(profile),
          path(taxonomy_metadata, stageAs: 'taxonomy??/*', arity: '1..*')

    output:
    tuple val(meta), val(reference), path('*.sylphmpa', arity: '1'), emit: taxonomy_profiles
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def output = "${prefix}.sylphmpa"
    """
    sylph-tax \
        --no-config \
        taxprof \
        ${profile} \
        --taxonomy-metadata ${taxonomy_metadata} \
        --output-prefix sylph-tax-

    mv sylph-tax-*.sylphmpa ${output}

    SYLPH_TAX_VERSION="\$(sylph-tax --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph-tax: "\${SYLPH_TAX_VERSION}"
    END_VERSIONS
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def output = "${prefix}.sylphmpa"
    """
    cat <<-END_PROFILE > ${output}
    #SampleID\t${prefix}\tTaxonomies_used:stub
    clade_name\trelative_abundance\tsequence_abundance\tANI (if strain-level)\tCoverage (if strain-level)
    END_PROFILE
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph-tax: "stub"
    END_VERSIONS
    """
}
