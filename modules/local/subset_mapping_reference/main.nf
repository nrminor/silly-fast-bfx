process SUBSET_MAPPING_REFERENCE {
    tag "${meta.id}:${meta.read_set}:${meta.deacon_id ?: '-'}:${reference.id}"

    input:
    tuple val(meta), val(reference), path(profile), path(fasta)

    output:
    tuple val(meta), val(reference), path('*.selected.fasta'), path('*.selection.tsv'), env('HAS_SELECTED_RECORDS'), path(profile), emit: selections
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    def selected_fasta = "${prefix}.selected.fasta"
    def report = "${prefix}.selection.tsv"
    def selection = reference.select
    def sequence_abundance_min_arg = selection.sequence_abundance.min == null ? '' : "--sequence-abundance-min ${selection.sequence_abundance.min}"
    def sequence_abundance_max_arg = selection.sequence_abundance.max == null ? '' : "--sequence-abundance-max ${selection.sequence_abundance.max}"
    def adjusted_ani_min_arg = selection.adjusted_ani.min == null ? '' : "--adjusted-ani-min ${selection.adjusted_ani.min}"
    def adjusted_ani_max_arg = selection.adjusted_ani.max == null ? '' : "--adjusted-ani-max ${selection.adjusted_ani.max}"
    """
    subset_mapping_reference.py \
        --profile ${profile} \
        --fasta ${fasta} \
        ${sequence_abundance_min_arg} \
        ${sequence_abundance_max_arg} \
        ${adjusted_ani_min_arg} \
        ${adjusted_ani_max_arg} \
        --output-fasta ${selected_fasta} \
        --report ${report} \
        --has-sequences-output selected.has-records \
        --versions-output versions.yml \
        --process ${task.process}

    export HAS_SELECTED_RECORDS="\$(cat selected.has-records)"
    """

    stub:
    def read_set_name = meta.read_set == 'input' ? 'input' : "deacon-${meta.deacon_id}"
    def prefix = task.ext.prefix ?: "${meta.id}__${read_set_name}"
    """
    : > ${prefix}.selected.fasta
    printf '%s\n' 'Contig_name\tstatus' > ${prefix}.selection.tsv
    export HAS_SELECTED_RECORDS=false
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "stub"
    END_VERSIONS
    """
}
