process SKETCH_READS_WITH_SYLPH {
    tag "${meta.id}:${meta.read_set}"

    input:
    tuple val(sample_sketch), val(meta), path(reads, stageAs: 'reads??/*', arity: '1..2')

    output:
    tuple val(sample_sketch), val(meta), path('*.sylsp'), emit: sketches
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def sample_name = "${meta.id}__${read_set_name}"
    def read_args = meta.single_end
        ? "--reads ${reads[0]}"
        : "--first-pairs ${reads[0]} --second-pairs ${reads[1]}"
    """
    sylph sketch \
        ${read_args} \
        --sample-names ${sample_name} \
        -k ${sample_sketch.kmer_length} \
        -c ${sample_sketch.compression} \
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
    def paired_suffix = meta.single_end ? '' : '.paired'
    """
    printf 'stub sample sketch' > ${sample_name}${paired_suffix}.sylsp
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sylph: "stub"
    END_VERSIONS
    """
}
