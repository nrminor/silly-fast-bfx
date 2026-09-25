process RENDER_MAPPING_PILEUPS_WITH_ALIGNOTH {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(fasta), path(bam), path(csi), path(counts), path(coverage), path(intervals), val(max_read_depth)

    output:
    tuple val(meta), val(reference), path('*.pileups'), emit: pileups
    path 'versions.yml', topic: versions

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    """
    render_mapping_pileups.py \\
        --bam ${bam} \\
        --fasta ${fasta} \\
        --coverage ${coverage} \\
        --output ${prefix}.pileups \\
        --max-read-depth ${max_read_depth}
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alignoth: "\$(alignoth --version)"
    END_VERSIONS
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}__${reference.id}"
    """
    mkdir ${prefix}.pileups
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alignoth: "stub"
    END_VERSIONS
    """
}
