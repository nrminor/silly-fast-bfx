process PROFILE_READS_WITH_SYLPH {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(sketch), path(database)

    output:
    tuple val(meta), val(reference), path('*.profile.tsv'), env('HAS_PROFILE_ROWS'), emit: profiles
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def profile = "${prefix}.profile.tsv"
    def estimate_unknown_arg = reference.profile.estimate_unknown ? '--estimate-unknown' : ''
    def estimate_read_counts_arg = reference.profile.estimate_read_counts ? '--estimate-read-counts' : ''
    def read_seq_id_arg = reference.profile.read_seq_id == null ? '' : "--read-seq-id ${reference.profile.read_seq_id}"
    """
    sylph profile \
        ${database} \
        ${sketch} \
        --minimum-ani ${reference.profile.minimum_ani} \
        --min-count-correct ${reference.profile.min_count_correct} \
        --min-number-kmers ${reference.profile.min_number_kmers} \
        ${estimate_unknown_arg} \
        ${estimate_read_counts_arg} \
        ${read_seq_id_arg} \
        -t ${task.cpus} \
        --output-file ${profile}

    if [ "\$(wc -l < ${profile})" -gt 1 ]; then
        export HAS_PROFILE_ROWS=true
    else
        export HAS_PROFILE_ROWS=false
    fi

    SYLPH_VERSION="\$(sylph --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "\${SYLPH_VERSION#sylph }"
    END_VERSIONS
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def profile = "${prefix}.profile.tsv"
    def coverage_column = reference.profile.estimate_unknown || reference.profile.estimate_read_counts
        ? 'True_cov'
        : 'Eff_cov'
    """
    printf '%s\\n' 'Sample_file\tGenome_file\tTaxonomic_abundance\tSequence_abundance\tAdjusted_ANI\t${coverage_column}\tANI_5-95_percentile\tEff_lambda\tLambda_5-95_percentile\tMedian_cov\tMean_cov_geq1\tContainment_ind\tNaive_ANI\tkmers_reassigned\tContig_name' > ${profile}
    export HAS_PROFILE_ROWS=false
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "stub"
    END_VERSIONS
    """
}
