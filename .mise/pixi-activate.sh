_pixi_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v pixi >/dev/null 2>&1 && [[ -d "${_pixi_project_root}/.pixi/envs/dev" ]]; then
  eval "$(pixi shell-hook \
    --manifest-path "${_pixi_project_root}/pyproject.toml" \
    --environment dev \
    --as-is \
    --no-completions \
    --change-ps1 false)"
fi

unset _pixi_project_root
