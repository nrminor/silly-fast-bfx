process QUERY_READS_WITH_SKOPE {
    tag "${meta.id}:${reference.id}"

    input:
    tuple val(meta),
          val(reference),
          path(reads, stageAs: 'reads/read??.fastq', arity: '1..2'),
          path(query_index)

    output:
    tuple val(meta), val(reference), path('*.skope.tsv'), emit: results
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def result = "${prefix}.skope.tsv"
    def discriminatory_arg = reference.query.discriminatory ? '--discriminatory' : ''
    def confidence_arg = reference.query.confidence ? '--confidence' : ''
    def limit_arg = reference.query.limit == null ? '' : "--limit ${reference.query.limit}"
    """
    skope query \
        --names ${prefix} \
        --fraction ${reference.query.fraction} \
        --abundance-thresholds ${reference.query.abundance_thresholds.join(',')} \
        ${discriminatory_arg} \
        ${confidence_arg} \
        ${limit_arg} \
        --threads ${task.cpus} \
        --output ${result} \
        ${query_index} \
        reads

    SKOPE_VERSION="\$(skope --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        skope: "\${SKOPE_VERSION#skope }"
    END_VERSIONS
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def result = "${prefix}.skope.tsv"
    """
    printf '%s\n' 'target\tsample\tcontainment1\tcontainment1_hits\tmedian_nz_abundance\ttarget_kmers\ttarget_length\tsample_seqs\tsample_bases' > ${result}
    printf '%s\n' 'TOTAL\t${prefix}\t0.000\t0\t0\t0\t0\t0\t0' >> ${result}
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        skope: "stub"
    END_VERSIONS
    """
}
