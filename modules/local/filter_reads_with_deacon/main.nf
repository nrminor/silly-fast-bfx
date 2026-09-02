process FILTER_READS_WITH_DEACON {
    tag "${meta.id}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(cbq), path(index)

    output:
    tuple val(meta), val(reference), path('*.fastq.gz', arity: '1'), path('*.summary.json'), env('HAS_READS'), emit: reads
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: meta.id
    def output = "${prefix}.fastq.gz"
    def summary = "${prefix}.summary.json"
    def complexity_arg = reference.filter.complexity_threshold == null
        ? ''
        : "--complexity-threshold ${reference.filter.complexity_threshold}"
    def deplete_arg = reference.filter.deplete ? '--deplete' : ''
    """
    deacon filter \
        --abs-threshold ${reference.filter.abs_threshold} \
        --rel-threshold ${reference.filter.rel_threshold} \
        --prefix-length ${reference.filter.prefix_length} \
        ${complexity_arg} \
        ${deplete_arg} \
        --threads ${task.cpus} \
        --output ${output} \
        --summary ${summary} \
        ${index} \
        ${cbq}

    export HAS_READS="\$(check_deacon_reads.py --summary ${summary})"

    DEACON_VERSION="\$(deacon --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deacon: "\${DEACON_VERSION#deacon }"
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: meta.id
    def output = "${prefix}.fastq.gz"
    def summary = "${prefix}.summary.json"
    """
    printf '@stub\\nA\\n+\\nI\\n' | gzip > ${output}
    printf '{"seqs_out": 0}\\n' > ${summary}
    export HAS_READS="\$(check_deacon_reads.py --summary ${summary})"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        deacon: "stub"
    END_VERSIONS
    """
}
