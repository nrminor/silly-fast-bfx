process SUMMARIZE_MAPPING_COVERAGE {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(fasta), path(profile), path(bam), path(csi), path(counts)

    output:
    tuple val(meta), val(reference), path(fasta), path(bam), path(csi), path(counts), path('*.coverage.tsv'), path('*.coverage.intervals.tsv'), emit: coverage
    path 'versions.yml', topic: versions

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    """
    summarize_mapping_coverage.py \\
        --bam ${bam} \\
        --fasta ${fasta} \\
        --profile ${profile} \\
        --counts ${counts} \\
        --profile-read-set ${meta.profile_read_set} \\
        --mapped-read-set ${read_set_name} \\
        ${meta.sylph_estimate_read_counts ? '--sylph-estimate-read-counts' : ''} \\
        --coverage-output ${prefix}.coverage.tsv \\
        --intervals-output ${prefix}.coverage.intervals.tsv \\
        --versions-output versions.yml \\
        --process ${task.process}
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    """
    printf '%s\\n' 'reference_id\\treference_name\\treference_length\\tprofiling_read_set\\tmapped_read_set\\tTaxonomic_abundance\\tSequence_abundance\\tsylph_sequence_abundance_units\\tAdjusted_ANI\\tEff_cov\\tTrue_cov\\ttotal_read_count\\tmapper_mapped_read_count\\tsupporting_read_count\\texclusive_read_count\\tshared_read_count\\tmapped_read_fraction\\tcovered_bases\\tbreadth\\tmean_depth\\texclusive_breadth\\texclusive_mean_depth' > ${prefix}.coverage.tsv
    printf '%s\\n' 'reference_id\\treference_name\\tstart\\tend\\tdepth' > ${prefix}.coverage.intervals.tsv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        polars: "stub"
        pysam: "stub"
        python: "stub"
    END_VERSIONS
    """
}
