process PROFILE_READS_WITH_SYLPH {
    tag "${meta.id}:${reference.id}"
    label 'process_high'

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
    """
    sylph profile \
        ${database} \
        ${sketch} \
        --minimum-ani ${reference.profile.minimum_ani} \
        --min-count-correct ${reference.profile.min_count_correct} \
        --min-number-kmers ${reference.profile.min_number_kmers} \
        --redundancy-threshold ${reference.profile.redundant_ani} \
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
    """
    printf '%s\\n' 'Sample_file\tGenome_file\tTaxonomic_abundance\tSequence_abundance\tAdjusted_ANI\tEff_cov\tANI_5-95_percentile\tEff_lambda\tLambda_5-95_percentile\tMedian_cov\tMean_cov_geq1\tContainment_ind\tNaive_ANI\tkmers_reassigned\tContig_name' > ${profile}
    export HAS_PROFILE_ROWS=false
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "stub"
    END_VERSIONS
    """
}
