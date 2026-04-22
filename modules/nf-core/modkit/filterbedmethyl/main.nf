process MODKIT_FILTERBEDMETHYL {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/92/92859404d861ae01afb87e2b789aebc71c0ab546397af890c7df74e4ee22c8dd/data' :
        'community.wave.seqera.io/library/htslib:1.21--ff8e28a189fbecaa' }"

    input:
    tuple val(meta), path(bedmethyl_gz), path(tbi)

    output:
    tuple val(meta), path("*.filtered.bed.gz"), path("*.filtered.bed.gz.tbi"), emit: bedmethyl
    tuple val("${task.process}"), val('bgzip'), eval("bgzip --version | sed '1!d;s/.* //'"), topic: versions, emit: versions_bgzip
    tuple val("${task.process}"), val('tabix'), eval("tabix --version | sed '1!d;s/.* //'"), topic: versions, emit: versions_tabix

    when:
    task.ext.when == null || task.ext.when

    script:
    // max_cov = keep rows where column 10 (valid_coverage) <= max_cov.
    // Default 65534 = 2^16 - 2, i.e. drop anything that hit the u16 ceiling (65535)
    // in modkit's bedMethyl writer. Override via task.ext.args, e.g. `ext.args = '--max-cov 50000'`.
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Parse optional --max-cov from ext.args; default 65534 (strict u16-safe cutoff).
    max_cov=65534
    for a in ${args}; do
        case "\${prev:-}" in
            --max-cov) max_cov="\$a" ;;
        esac
        prev="\$a"
    done

    before=\$(zcat ${bedmethyl_gz} | wc -l)

    zcat ${bedmethyl_gz} \\
        | awk -v MAX="\${max_cov}" 'BEGIN{FS=OFS="\\t"} \$10 <= MAX' \\
        | bgzip --threads ${task.cpus} \\
        > ${prefix}.filtered.bed.gz

    tabix --threads ${task.cpus} -p bed ${prefix}.filtered.bed.gz

    after=\$(zcat ${prefix}.filtered.bed.gz | wc -l)
    echo "[modkit/filterbedmethyl] ${meta.id}: kept \${after} / \${before} rows (dropped \$((before - after)) with valid_coverage > \${max_cov})" 1>&2
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "" | gzip > ${prefix}.filtered.bed.gz
    touch ${prefix}.filtered.bed.gz.tbi
    """
}
