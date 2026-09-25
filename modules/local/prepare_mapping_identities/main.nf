process PREPARE_MAPPING_IDENTITIES {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}"

    input:
    tuple val(meta), path(reads, stageAs: 'reads??????/*', arity: '1..*')

    output:
    tuple val(meta), path(reads), path('*.mapping-collisions.tsv'), path('*.read-count.txt'), env('HAS_READS'), emit: identities
    path 'versions.yml', topic: versions

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def input_args = reads.collect { "--input ${it}" }.join(' ')
    """
    prepare_mapping_identities.py \\
        ${input_args} \\
        --collisions ${prefix}.mapping-collisions.tsv \\
        --count-output ${prefix}.read-count.txt \\
        --has-reads-output prepared.has-reads \\
        --versions-output versions.yml \\
        --process ${task.process}

    export HAS_READS="\$(cat prepared.has-reads)"
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    """
    printf '%s\n' 'ordinal\tmapped_name' > ${prefix}.mapping-collisions.tsv
    printf '1\n' > ${prefix}.read-count.txt
    export HAS_READS=true
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        polars: "stub"
        pysam: "stub"
        python: "stub"
    END_VERSIONS
    """
}
