process STORE_CLASSIFIED_READS {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(fasta), path(bam), path(reads, stageAs: 'reads??????/*', arity: '1..*'), path(collisions), path(allowlist)

    output:
    tuple val(meta), val(reference), path('*.classified-reads.parquet'), emit: stores
    path 'versions.yml', topic: versions

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    def input_args = reads.collect { read -> "--input ${read}" }.join(' ')
    def allowlist_arg = allowlist ? "--allowlist ${allowlist}" : ''
    """
    store_classified_reads.py \\
        --bam ${bam} \\
        --fasta ${fasta} \\
        ${input_args} \\
        --collisions ${collisions} ${allowlist_arg} \\
        --output ${prefix}.classified-reads.parquet \\
        --sample-id ${meta.id} \\
        --mapped-read-set ${read_set_name} \\
        --reference-specification ${reference.id} \\
        --versions-output versions.yml \\
        --process ${task.process}
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    """
    : > ${prefix}.classified-reads.parquet
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        polars: "stub"
        pysam: "stub"
        python: "stub"
    END_VERSIONS
    """
}
