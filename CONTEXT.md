# silly-fast-bfx

`silly-fast-bfx` is a prototype metagenomic screening pipeline for comparing rapid searches across samples, reference collections, tools, read sets, and read encodings.

## Language

This glossary is the primary purpose of this document. Every proposed project-specific term must be weighed as a potential glossary addition before it becomes established vocabulary. Prefer an existing term when it already names the concept precisely; add a term only when the domain needs a distinct concept.

**Samplesheet**:
An NVD-compatible CSV that identifies samples and describes their platform and read source using `sample_id`, `srr`, `platform`, `fastq1`, `fastq2`, `fastq1_glob`, and `fastq2_glob`. It preserves the complete NVD format even when a pipeline release does not yet execute every source mode.
_Avoid_: input manifest, FASTQ list

**Reference specification**:
A named, tool-specific declaration of one reference source together with its build and search parameters. Several reference specifications may use the same underlying FASTA, index, or sketch with different settings.
_Avoid_: database config, index entry

**Read set**:
A defined collection of read records associated with one sample at one filtering state. The input read set and each Deacon-filtered read set are distinct even when they originate from the same sample.
_Avoid_: read dataset, read representation

**Read encoding**:
A material encoding of a read set, such as FASTQ or CBQ. Changing the encoding does not change which read records belong to the read set.
_Avoid_: read set, read format stage

**Sample sketch**:
A Sylph sketch derived from one read set for reuse across one or more Sylph reference specifications. It is neither a read set nor a lossless read encoding.
_Avoid_: reference sketch, read set

**Results bundle**:
The curated user-facing output of one pipeline execution. It presents summaries first and progressively discloses per-sample, per-tool, per-reference, and provenance artifacts without exposing incidental work files.
_Avoid_: output directory, work directory, results dump

## Repository rules

1. **Vocabulary**: Weigh every proposed project-specific term as a potential glossary addition before using it as established vocabulary. Prefer an existing precise term over a new synonym. Use plain descriptions for ordinary implementation details; do not invent formal-sounding names for tuples, files, stages, or boundaries that do not represent distinct domain concepts.

2. **Naming**: Names for processes, process modules, and `bin` scripts begin with verbs. Workflow and subworkflow names may be nouns.

3. **Python style**: Scripts under `bin/` are written in Python and primarily orchestrate libraries implemented in native code, such as Polars. Prefer typed, expression-oriented transformations and composition over mutable, row-wise Python. This is the project's “Python that reads like Haskell” style.

4. **Workflow style**: Keep project workflow files high-level and declarative. Prefer named subworkflows and declarative Nextflow operators over inline Groovy and imperative control flow. Assign channels directly to variables whose names begin with `ch_`; do not use postfix `.set { channel_name }` assignment. Use a consistent nesting depth across comparable branches: a subworkflow should own a cohesive, local behavior and a meaningful separation of concerns, not merely wrap one process or create a one-off extra layer. A small bundle of adjacent processes is not by itself enough reason to extract a subworkflow. If the prevailing shape is `workflow -> subworkflow -> process`, do not introduce an isolated `workflow -> subworkflow -> subworkflow -> process` chain without a clear architectural reason that applies consistently.

5. **Nextflow ownership**: Do not recreate facilities that Nextflow already provides. Use Nextflow tracing, error handling, retries, caching, and task state rather than adding parallel pipeline-specific layers.

6. **Empty data**: Handle absent or empty data at the process that produces it. Do not force every downstream process to accept missing, sentinel, or header-only inputs and rediscover whether meaningful data exists.

7. **Module conventions**: Every process is defined in an nf-core-style module with `main.nf` and `meta.yml`; do not define processes inline in workflow or subworkflow files. Custom tool modules follow nf-core process, named-output, versions-topic, stub, and `meta.yml` conventions. Do not add placeholder Conda environment files or container directives before the project adopts them deliberately. Do not add copied or shared Groovy shell-escaping helpers; prefer ordinary nf-core command interpolation and controlled path staging. An exception requires a reproduced failure and a focused regression test.

8. **Prototype posture**: Do not design for backwards compatibility, migration paths, stable public interfaces, or production hardening at this stage. Treat schema-validated paths and URLs as trusted run configuration. Add filename restrictions only for a scientific or results-bundle contract, or for a reproduced Nextflow/tool failure covered by a focused test; do not proactively blacklist task filenames, punctuation, or shell metacharacters. Decide case by case whether a question is answered most efficiently by a disposable experiment or by implementing the intended design directly.

9. **Tool execution**: Agents may use host development infrastructure such as Jujutsu, GitHub CLI, and container tooling, but must not discover or execute ambient project or scientific tools from the global environment or an unrelated Conda environment. Run project tools only through repository-declared Mise, Pixi, uv, workflow, or container entry points.

10. **Data handling**: Use the already-adopted nf-schema plugin to validate the samplesheet and convert its rows into native values during workflow initialization. Treat schema-validated shape and uniqueness as established; do not repeat those checks in workflow code. Do not hand-write CSV or JSON parsing in workflow code or pass structured-data control files between processes. Use Nextflow to arrange processes, channels, paths, and small metadata maps. Keep reference arrangement tool-specific; do not introduce generic declaration/resolution metadata frameworks, or hide equivalent workflow logic in `lib/`, Python, or control files, without two implemented consumers and a demonstrated net reduction at their callsites. Put substantive data transformation that exceeds channel arrangement in verb-named Python scripts under `bin/`, following Rule 3.
