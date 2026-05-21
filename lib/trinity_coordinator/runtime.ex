defmodule TrinityCoordinator.Runtime do
  @moduledoc """
  Runtime checks for GPU-backed Nx/EXLA execution.
  """

  @doc """
  Returns the EXLA platforms visible to this BEAM instance.
  """
  def supported_platforms do
    EXLA.Client.get_supported_platforms()
  end

  @doc """
  Raises unless EXLA reports at least one CUDA device.
  """
  def require_cuda! do
    platforms = supported_platforms()

    unless Map.get(platforms, :cuda, 0) > 0 do
      raise "EXLA CUDA platform is not available. XLA/EXLA must be fetched or compiled with XLA_TARGET=cuda12 before starting this task; setting XLA_TARGET only on the final mix invocation cannot add CUDA to an existing build. Check the current BEAM with: mix run --no-start -e 'IO.inspect(EXLA.Client.get_supported_platforms())'. Rebuild with: rm -rf _build/dev/lib/xla _build/dev/lib/exla deps/xla deps/exla && XLA_TARGET=cuda12 mix deps.get && XLA_TARGET=cuda12 mix deps.compile xla exla --force"
    end

    platforms
  end

  @doc """
  Sets the current process default Nx backend to the configured EXLA CUDA client.
  """
  def put_cuda_backend! do
    require_cuda!()
    Nx.default_backend({EXLA.Backend, client: :cuda})
  end

  @doc """
  Runs a function with the current process default backend set to EXLA CUDA.
  """
  def with_cuda_backend!(fun) when is_function(fun, 0) do
    require_cuda!()
    Nx.with_default_backend({EXLA.Backend, client: :cuda}, fun)
  end

  @doc """
  Returns a compact backend label for a tensor.
  """
  def tensor_backend(%Nx.Tensor{data: %backend_struct{}} = tensor) do
    inspected = inspect(tensor)

    cond do
      String.contains?(inspected, "EXLA.Backend<cuda") -> "EXLA.Backend<cuda:"
      String.contains?(inspected, "EXLA.Backend<host") -> "EXLA.Backend<host:"
      String.contains?(inspected, "EXLA.Backend<") -> "EXLA.Backend"
      backend_struct == Emily.Backend -> "Emily.Backend"
      backend_struct == Nx.BinaryBackend -> "Nx.BinaryBackend"
      String.contains?(inspected, "Nx.BinaryBackend") -> "Nx.BinaryBackend"
      true -> "unknown"
    end
  end
end
