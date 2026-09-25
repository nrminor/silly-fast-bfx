process MAP_READS_WITH_MINIMAP2 {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(fasta), path(reads, stageAs: 'reads??????/*', arity: '1..*'), path(collisions), path(read_count)

    output:
    tuple val(meta), val(reference), path('*.bam'), path('*.bam.csi'), path('*.counts.json'), emit: alignments
    path 'versions.yml', topic: versions

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    def alignment = meta.platform == 'illumina' ? reference.align.illumina : reference.align.ont
    def input_args = reads.collect { "--input ${it}" }.join(' ')
    """
    set -o pipefail
    INDEX_BATCH_SIZE="\$(( \$(wc -c < ${fasta}) + 1 ))"
    minimap2 \\
        -I \${INDEX_BATCH_SIZE} \\
        -d ${prefix}.mmi \\
        -x ${alignment.preset} \\
        ${fasta}
    stream_mapping_reads.py \\
        ${input_args} \\
        --collisions ${collisions} | \\
    minimap2 \\
        -ax ${alignment.preset} \\
        --frag=no \\
        --secondary=yes \\
        -N ${alignment.max_secondary} \\
        -p ${alignment.secondary_score_ratio} \\
        -t ${task.cpus} \\
        ${prefix}.mmi - | \\
    samtools sort -@ ${task.cpus} -o ${prefix}.bam
    samtools index -@ ${task.cpus} -c ${prefix}.bam
    TOTAL_READS="\$(cat ${read_count})"
    MAPPED_READS="\$(samtools view -c -F 2308 ${prefix}.bam)"
    printf '{"total_reads": %s, "mapped_reads": %s, "unmapped_reads": %s}\\n' \\
        "\${TOTAL_READS}" "\${MAPPED_READS}" "\$(( TOTAL_READS - MAPPED_READS ))" > ${prefix}.counts.json
    MINIMAP2_VERSION="\$(minimap2 --version)"
    SAMTOOLS_VERSION="\$(samtools --version | awk 'NR == 1 { print \$2 }')"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: "\${MINIMAP2_VERSION}"
        samtools: "\${SAMTOOLS_VERSION}"
    END_VERSIONS
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    """
    : > ${prefix}.bam
    : > ${prefix}.bam.csi
    printf '{"total_reads": 1, "mapped_reads": 0, "unmapped_reads": 1}\\n' > ${prefix}.counts.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: "stub"
        samtools: "stub"
    END_VERSIONS
    """
}
