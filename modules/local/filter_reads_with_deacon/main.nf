process FILTER_READS_WITH_DEACON {
    tag "${meta.id}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(cbq), path(index)

    output:
    tuple val(meta), val(reference), path('*.fastq.gz', arity: '1..2'), path('*.summary.json'), env('HAS_READS'), emit: reads
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: meta.id
    def output_one = meta.single_end ? "${prefix}.fastq.gz" : "${prefix}_R1.fastq.gz"
    def output_two = "${prefix}_R2.fastq.gz"
    def summary = "${prefix}.summary.json"
    def deacon_output = meta.single_end ? output_one : "${prefix}.filtered.cbq"
    def complexity_arg = reference.filter.complexity_threshold == null
        ? ''
        : "--complexity-threshold ${reference.filter.complexity_threshold}"
    def deplete_arg = reference.filter.deplete ? '--deplete' : ''
    def decode_paired = meta.single_end ? '' : """
    if [ "\${HAS_READS}" = 'true' ]; then
        bqtools decode \
            --format q \
            --compress g \
            --threads ${task.cpus} \
            --prefix ${prefix} \
            ${deacon_output}
        mv ${prefix}_R1.fq.gz ${output_one}
        mv ${prefix}_R2.fq.gz ${output_two}
    else
        gzip --no-name --stdout </dev/null > ${output_one}
        gzip --no-name --stdout </dev/null > ${output_two}
    fi
    """
    """
    deacon filter \
        --abs-threshold ${reference.filter.abs_threshold} \
        --rel-threshold ${reference.filter.rel_threshold} \
        --prefix-length ${reference.filter.prefix_length} \
        ${complexity_arg} \
        ${deplete_arg} \
        --threads ${task.cpus} \
        --output ${deacon_output} \
        --summary ${summary} \
        ${index} \
        ${cbq}

    export HAS_READS="\$(check_deacon_reads.py --summary ${summary})"
    ${decode_paired}

    DEACON_VERSION="\$(deacon --version)"
    BQTOOLS_VERSION="\$(bqtools --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deacon: "\${DEACON_VERSION#deacon }"
        bqtools: "\${BQTOOLS_VERSION#bqtools }"
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    def output_one = meta.single_end ? "${prefix}.fastq.gz" : "${prefix}_R1.fastq.gz"
    def output_two = "${prefix}_R2.fastq.gz"
    def summary = "${prefix}.summary.json"
    def output_two_command = meta.single_end
        ? ''
        : "printf '@stub/2\\nA\\n+\\nI\\n' | gzip > ${output_two}"
    """
    printf '@stub/1\\nA\\n+\\nI\\n' | gzip > ${output_one}
    ${output_two_command}
    printf '{"seqs_out": 0}\\n' > ${summary}
    export HAS_READS="\$(check_deacon_reads.py --summary ${summary})"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deacon: "stub"
        bqtools: "stub"
    END_VERSIONS
    """
}
