process COLLATE_FASTQ {
    tag "${meta.id}"

    input:
    tuple val(meta), path(reads, stageAs: 'reads??/*'), val(r1_count), val(r1_sources)

    output:
    tuple val(meta), path("${meta.id}_R*.fastq*", arity: '1..2'), emit: reads
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def single_end = meta.single_end ? '--single-end' : ''
    """
    collate_fastq.py \
        --sample-id "${meta.id}" \
        --r1-count ${r1_count} \
        ${single_end} \
        --versions-output versions.yml \
        --process ${task.process}
    """

    stub:
    def extension = reads[0].name.endsWith('.gz') ? '.fastq.gz' : '.fastq'
    def outputs = meta.single_end
        ? "touch ${meta.id}_R1${extension}"
        : "touch ${meta.id}_R1${extension} ${meta.id}_R2${extension}"
    """
    ${outputs}
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "stub"
    END_VERSIONS
    """
}
