process SKETCH_READS_WITH_SYLPH {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}"

    input:
    tuple val(sample_sketch), val(meta), path(reads, stageAs: 'reads??????/*', arity: '1..*')

    output:
    tuple val(sample_sketch), val(meta), path('*.sylsp'), emit: sketches
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def sample_name = "${meta.id}__${read_set_name}"
    def no_dedup_arg = sample_sketch.no_dedup ? '--no-dedup' : ''
    """
    staged_reads=(reads??????/*)

    set -o pipefail
    cat -- "\${staged_reads[@]}" |
        sylph sketch \
            --reads /dev/stdin \
            --sample-names ${sample_name} \
            -k ${sample_sketch.kmer_length} \
            -c ${sample_sketch.compression} \
            ${no_dedup_arg} \
            -t ${task.cpus}

    SYLPH_VERSION="\$(sylph --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "\${SYLPH_VERSION#sylph }"
    END_VERSIONS
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def sample_name = "${meta.id}__${read_set_name}"
    """
    printf 'stub sample sketch' > ${sample_name}.sylsp
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "stub"
    END_VERSIONS
    """
}
