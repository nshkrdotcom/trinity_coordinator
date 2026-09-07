defmodule TrinityCoordinator.RuntimeProfile do
  @moduledoc """
  Declarative description of a coordinator runtime / backend lane.

  A `%RuntimeProfile{}` captures the Nx backend tuple, whether CUDA is
  required, whether the Qwen3-0.6B base must be loadable, and other facts that
  used to be scattered through Mix-task defaults and `Coordinator.load/1`'s
  CUDA-shaped option list.

  ## Built-in profiles

    * `:cuda_exla` — canonical production lane. Requires CUDA platform.
    * `:rocm_exla` - AMD ROCm for AMD hosts.
    * `:host_exla` — CPU EXLA lane for compatibility / non-CUDA hosts.
    * `:binary` — pure Nx binary backend; tiny tests only.
    * `:mock_tiny` — synthetic tiny coordinator with no Qwen load (Phase 5).
    * `:emlx` — Apple Silicon path. Descriptive only unless the EMLX backend
      module is actually loaded by the host application.

  Custom profiles can be passed through directly:

      %RuntimeProfile{name: :custom_x, nx_backend: {EXLA.Backend, client: :host}, ...}

  No `lib/**` code reads from `System.get_env/1` to pick the profile — the
  caller decides, either by a Mix task flag, a `Config.Provider`, or an
  explicit struct.
  """

  # Phase 5 — per-profile defaults for the prompt-eval suite. CUDA-empirical
  # 80% floors observed on 2026-05-20 (agent worst = 0.301 on `unicode_emoji`,
  # role worst = 1.335 on `root_cause`). Every built-in profile keeps the
  # CUDA defaults so behaviour is bytewise unchanged unless a profile
  # explicitly overrides via `override_default_margins/2`.
  @canonical_min_agent_margin 0.24
  @canonical_min_role_margin 1.06

  @enforce_keys [:name, :nx_backend]
  defstruct [
    :name,
    :nx_backend,
    require_cuda?: false,
    qwen_runtime?: true,
    export_svd?: false,
    large_svd?: false,
    artifact_runtime?: true,
    default_slm_profile: :qwen_coordinator,
    default_min_agent_margin: @canonical_min_agent_margin,
    default_min_role_margin: @canonical_min_role_margin,
    notes: [],
    warnings: []
  ]

  @type backend_tuple :: {module(), keyword()} | module()

  @type t :: %__MODULE__{
          name: atom() | binary(),
          nx_backend: backend_tuple(),
          require_cuda?: boolean(),
          qwen_runtime?: boolean(),
          export_svd?: boolean(),
          large_svd?: boolean(),
          artifact_runtime?: boolean(),
          default_slm_profile: atom(),
          default_min_agent_margin: float(),
          default_min_role_margin: float(),
          notes: [String.t()],
          warnings: [String.t()]
        }

  @doc """
  Resolves a profile name (or passthrough struct) into a `%RuntimeProfile{}`.

  Raises `ArgumentError` for unknown names so misconfiguration fails loud
  rather than silently falling back to a CUDA default.
  """
  @spec resolve(atom() | t() | {atom(), keyword()}) :: t()
  def resolve(%__MODULE__{} = profile), do: profile

  def resolve(:cuda_exla) do
    %__MODULE__{
      name: :cuda_exla,
      nx_backend: {EXLA.Backend, client: :cuda},
      require_cuda?: true,
      qwen_runtime?: true,
      export_svd?: true,
      large_svd?: true,
      artifact_runtime?: true,
      default_slm_profile: :qwen_coordinator,
      notes: ["Canonical production lane; requires a CUDA-capable GPU."]
    }
  end

  def resolve(:rocm_exla) do
    %__MODULE__{
      name: :rocm_exla,
      nx_backend: {EXLA.Backend, client: :rocm},
      require_cuda?: false,
      qwen_runtime?: true,
      export_svd?: true,
      large_svd?: true,
      artifact_runtime?: true,
      default_slm_profile: :qwen_coordinator,
      notes: ["Canonical production lane; requires a CUDA-capable GPU."]
    }
  end

  def resolve(:host_exla) do
    %__MODULE__{
      name: :host_exla,
      nx_backend: {EXLA.Backend, client: :host},
      require_cuda?: false,
      qwen_runtime?: true,
      export_svd?: true,
      large_svd?: false,
      artifact_runtime?: true,
      default_slm_profile: :qwen_coordinator,
      notes: ["CPU EXLA; useful for compatibility checks but slow for full Qwen."]
    }
  end

  def resolve(:binary) do
    %__MODULE__{
      name: :binary,
      nx_backend: Nx.BinaryBackend,
      require_cuda?: false,
      qwen_runtime?: false,
      export_svd?: false,
      large_svd?: false,
      artifact_runtime?: false,
      default_slm_profile: :tiny_synthetic,
      notes: ["Pure Nx binary backend. Tests / tiny fixtures only."]
    }
  end

  def resolve(:mock_tiny) do
    %__MODULE__{
      name: :mock_tiny,
      nx_backend: Nx.BinaryBackend,
      require_cuda?: false,
      qwen_runtime?: false,
      export_svd?: false,
      large_svd?: false,
      artifact_runtime?: true,
      default_slm_profile: :tiny_synthetic,
      notes: ["Synthetic tiny coordinator; no real Qwen load. See Phase 5."]
    }
  end

  def resolve(:emlx) do
    %__MODULE__{
      name: :emlx,
      nx_backend: {EMLX.Backend, device: :gpu},
      require_cuda?: false,
      qwen_runtime?: true,
      export_svd?: true,
      large_svd?: false,
      artifact_runtime?: true,
      default_slm_profile: :qwen_coordinator,
      notes: [
        "Apple Silicon profile. Requires the optional {:emlx, \"~> 0.3\"} dependency. ",
        "See guides/runtime_profiles.md for setup."
      ]
    }
  end

  # Apple Silicon research/validation lane backed by the Emily MLX
  # backend. Mirrors :emlx's Apple-shaped flags but routes to
  # Emily.Backend and seeds the per-profile margin floors from
  # ausimian's empirical 2026-05-21 validation pass on Qwen3-0.6B + the
  # thin-SVD fix in Nx PR #1753: agent worst 0.417 (two_assistant_turns),
  # role worst 1.029 (escalate_to_human) — 80% floors are 0.33 / 0.82.
  # Without this override, every clean Emily run would mark the
  # escalate_to_human case as a near-miss against the canonical CUDA
  # role floor of 1.06.
  #
  # Emily is an OPTIONAL dependency for hosts that want this lane;
  # add `{:emily, "~> 0.4", only: [:dev, :test]}` to your parent app's
  # mix.exs (do not commit it to trinity_coordinator's own mix.exs).
  # See guides/runtime_profiles.md for the full Apple-Silicon recipe.
  def resolve(:emily) do
    %__MODULE__{
      name: :emily,
      nx_backend: {Emily.Backend, []},
      require_cuda?: false,
      qwen_runtime?: true,
      export_svd?: true,
      large_svd?: false,
      artifact_runtime?: true,
      default_slm_profile: :qwen_coordinator,
      notes: [
        "Apple Silicon (Emily MLX) research/validation profile. ",
        "Requires the optional {:emily, \"~> 0.4\"} dependency. ",
        "See guides/runtime_profiles.md for setup."
      ]
    }
    |> override_default_margins(agent: 0.33, role: 0.82)
  end

  def resolve({:custom, backend, opts}) when is_atom(backend) and is_list(opts) do
    %__MODULE__{
      name: :custom,
      nx_backend: {backend, opts},
      notes: ["Custom backend tuple supplied by caller."]
    }
  end

  def resolve(other) do
    raise ArgumentError,
          "unknown runtime profile #{inspect(other)}; " <>
            "valid built-ins: :cuda_exla, :rocm_exla, :host_exla, :binary, :mock_tiny, :emlx, :emily; " <>
            "or pass a %TrinityCoordinator.RuntimeProfile{} struct or {:custom, backend, opts}"
  end

  @doc """
  Returns the list of built-in profile names.
  """
  @spec builtin_names() :: [atom()]
  def builtin_names, do: [:cuda_exla, :rocm_exla, :host_exla, :binary, :mock_tiny, :emlx, :emily]

  @doc """
  Sets the current process default Nx backend to the profile's backend.

  Behaviour:

    * `:require_cuda? == true` profiles delegate to
      `TrinityCoordinator.Runtime.put_cuda_backend!/0` for back-compat.
    * Profiles whose `:nx_backend` module is loaded set the global default
      via `Nx.global_default_backend/1`.
    * Profiles whose `:nx_backend` module is **not** loaded raise an
      informative error naming the profile and the missing module.

  The not-loaded path is what catches a user invoking
  `--runtime-profile emlx` on a host that has not added `{:emlx, "~> 0.3"}`
  to their parent application.
  """
  @spec put_default_backend!(t() | atom() | {atom(), keyword()}) :: :ok
  def put_default_backend!(name_or_profile) do
    profile = resolve(name_or_profile)
    do_put_default_backend!(profile)
  end

  defp do_put_default_backend!(%__MODULE__{require_cuda?: true}) do
    TrinityCoordinator.Runtime.put_cuda_backend!()
    :ok
  end

  defp do_put_default_backend!(%__MODULE__{nx_backend: backend} = profile) do
    {mod, _opts} = backend_module_and_opts(backend)

    if Code.ensure_loaded?(mod) do
      Nx.global_default_backend(backend)
      :ok
    else
      raise "Runtime profile #{inspect(profile.name)} requires backend " <>
              inspect(mod) <>
              " which is not loaded in this BEAM. Add the corresponding dependency " <>
              "to your parent application\'s mix.exs and run mix deps.get. " <>
              "See guides/runtime_profiles.md."
    end
  end

  defp backend_module_and_opts({mod, opts}) when is_atom(mod) and is_list(opts), do: {mod, opts}
  defp backend_module_and_opts(mod) when is_atom(mod), do: {mod, []}

  @doc """
  Returns true when the given tensor-backend label (as produced by
  `TrinityCoordinator.Runtime.tensor_backend/1`) is one this profile
  accepts.

  Used by the exporter\'s per-tensor backend validation: a profile is
  expected to receive tensors materialised on its own backend; anything
  else is a configuration error.

  ## Examples

      iex> profile = TrinityCoordinator.RuntimeProfile.resolve(:cuda_exla)
      iex> TrinityCoordinator.RuntimeProfile.accepts_backend_label?(profile, "EXLA.Backend<cuda:0>")
      true
      iex> TrinityCoordinator.RuntimeProfile.accepts_backend_label?(profile, "EMLX.Backend")
      false
  """
  @spec accepts_backend_label?(t(), String.t()) :: boolean()
  def accepts_backend_label?(%__MODULE__{nx_backend: backend}, observed)
      when is_binary(observed) do
    {mod, opts} = backend_module_and_opts(backend)
    expected_prefixes = expected_label_prefixes(mod, opts)
    Enum.any?(expected_prefixes, &String.starts_with?(observed, &1))
  end

  defp expected_label_prefixes(EXLA.Backend, opts) do
    case Keyword.get(opts, :client) do
      :cuda -> ["EXLA.Backend<cuda:"]
      :host -> ["EXLA.Backend<host:"]
      _ -> ["EXLA.Backend<"]
    end
  end

  defp expected_label_prefixes(Nx.BinaryBackend, _opts), do: ["Nx.BinaryBackend"]

  defp expected_label_prefixes(mod, _opts) do
    # Default: use the module\'s inspect representation as a label prefix.
    label =
      mod
      |> Module.split()
      |> Enum.join(".")

    [label]
  end

  @doc """
  Returns this profile's `%{agent: float, role: float}` default margin floors
  for the prompt-eval suite.

  Every built-in profile inherits the CUDA-empirical defaults
  (`agent: 0.24`, `role: 1.06`) unless a future profile explicitly overrides
  them via `override_default_margins/2`. The CLI flags
  `--min-agent-margin` / `--min-role-margin` of
  `examples/qwen_router_prompt_eval.exs` still win when supplied.
  """
  @spec default_margins(t()) :: %{agent: float(), role: float()}
  def default_margins(%__MODULE__{
        default_min_agent_margin: agent,
        default_min_role_margin: role
      }) do
    %{agent: agent, role: role}
  end

  @doc """
  Returns a copy of `profile` with one or both default margin floors overridden.

  Accepted keys: `:agent`, `:role`. Unspecified axes are left at the
  profile's existing default. Useful for caller-side overrides without
  having to construct a `%RuntimeProfile{}` from scratch, and for
  ergonomic per-profile seeding (e.g. an eventual `:emily` clause that
  wants `0.33` / `0.82` rather than the CUDA defaults).
  """
  @spec override_default_margins(t(), keyword()) :: t()
  def override_default_margins(%__MODULE__{} = profile, overrides) when is_list(overrides) do
    %{
      profile
      | default_min_agent_margin:
          Keyword.get(overrides, :agent, profile.default_min_agent_margin),
        default_min_role_margin: Keyword.get(overrides, :role, profile.default_min_role_margin)
    }
  end
end
