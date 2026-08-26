# `nrminor/silly-fast-bfx`

`silly-fast-bfx` is an nf-core-style Nextflow pipeline for extremely fast metagenomics. The repository currently contains only its development, validation, container, and release scaffold; scientific workflow stages will be introduced as real vertical slices rather than placeholders.

Bootstrap the locked tools, agent reference repositories, Pixi development environment, and uv runtime environment with:

```bash
mise bootstrap
```

The reference repositories are cloned under `.agents/repos/` and remain outside version control and container build contexts. Once bootstrapped, Mise activates the locked Pixi `dev` environment when entering the repository.

Run the repository checks with:

```bash
mise run check
```

Inspect the pipeline entry point with:

```bash
nextflow run . --help
nextflow run . --version
```

Build and smoke-test the process monoimage with:

```bash
mise run container-build
mise run container-test
```
